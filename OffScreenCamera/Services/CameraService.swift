进口 AVFoundation
进口 结合

最后的 班级 照相机服务:NSObject，ObservableObject {
    @已发布 定义变量 正在记录 = 错误的
    @已发布 定义变量 isSessionRunning = 错误的
    @已发布 定义变量 摄影位置:摄像机位置=。背部
    @已发布 定义变量 isMicrophoneEnabled = 真实的
    @已发布 定义变量 消逝秒 = 0
    @已发布 定义变量 currentSegmentIndex = 1
    @已发布 定义变量 错误消息:字符串？
    @已发布 定义变量 质量设置= VideoQualitySettings()
    @已发布 定义变量 lowLightBoostEnabled = 真实的

    定义变量 分段持续时间:时间间隔=600
    定义变量 maxRecordingDuration:时间间隔？
    定义变量 on segment完成: (@MainActor(URL，Int) -> Void)？
    定义变量 onRecordingStopped: (@MainActor(recordingstopfreason)-> Void)？

    私人的 让 会议= AVCaptureSession()
    私人的 让 电影输出= AVCaptureMovieFileOutput()
    私人的 让 会话队列= DispatchQueue(标签:" com.offscreen.camera.session ")

    私人的 定义变量 视频输入:AVCaptureDeviceInput？
    私人的 定义变量 音频输入:AVCaptureDeviceInput？
    私人的 定义变量 时间可取消:可以取消吗？
    私人的 定义变量 分段计时器:定时器？
    私人的 定义变量 记录开始日期:日期？
    私人的 定义变量 当前输出URL:网址？
    私人的 定义变量 旋转分段 = 错误的
    私人的 定义变量 pendingStopReason:记录停止原因=。用户
    私人的 定义变量 makeOutputURL: (@MainActor()->网址)？

    推翻 初始化() {
        极好的。初始化()
    }

    功能 请求权限() 异步ˌ非同步(asynchronous)->布尔{
        让 照相机拍摄的 = 等待请求访问(为: 。录像)
        防护装置照相机拍摄的其他 {
error message = CameraServiceError。权限被拒绝("相机权限被拒绝,请到系统设置中开启。")。本地化描述
            返回 错误的
        }

        如果isMicrophoneEnabled {
            让 micGranted = 等待请求访问(为: 。声音的)
            如果！micGranted {
error message = CameraServiceError。权限被拒绝("麦克风权限被拒绝,已改为静音录像。")。本地化描述
isMicrophoneEnabled =错误的
            }
        }

        返回 真实的
    }

    功能 准备会话() 异步ˌ非同步(asynchronous) 投 {
        尝试 等待withCheckedThrowingContinuation {(continuation:checked continuation < Void，Error >)在
会话队列。异步ˌ非同步(asynchronous) {
                做 {
                    尝试 自己。配置会话()
继续。简历()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        await startSessionIfNeeded()
    }

    func startRecordingSession(makeURL: @MainActor @escaping () -> URL) async throws {
        guard !isRecording else { return }
        makeOutputURL = makeURL
        currentSegmentIndex = 1

        if !isSessionRunning {
            try await prepareSession()
        }

        let url = await MainActor.run { makeURL() }
        try await startSegmentRecording(to: url)

        await MainActor.run {
            isRecording = true
            recordingStartedAt = Date()
            elapsedSeconds = 0
            PowerGuard.setRecordingActive(true)
            startElapsedTimer()
            scheduleSegmentRotation()
        }
    }

    func stopRecording(reason: RecordingStopReason = .user) {
        guard isRecording else { return }
        pendingStopReason = reason
        isRotatingSegment = false
        segmentTimer?.invalidate()
        segmentTimer = nil

        sessionQueue.async {
            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            }
        }
    }

    func rotateSegmentNow() {
        guard isRecording, !isRotatingSegment else { return }
        isRotatingSegment = true
        sessionQueue.async {
            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            }
        }
    }

    func switchCamera(to position: CameraPosition) async throws {
        guard !isRecording else {
            errorMessage = "录制中无法切换摄像头，请先停止。"
            return
        }
        cameraPosition = position
        try await reconfigureCameraOnQueue()
    }

    func setMicrophoneEnabled(_ enabled: Bool) async throws {
        guard !isRecording else {
            errorMessage = "录制中无法切换麦克风，请先停止。"
            return
        }

        if enabled {
            let granted = await requestAccess(for: .audio)
            guard granted else {
                errorMessage = CameraServiceError.permissionDenied("麦克风权限被拒绝。").localizedDescription
                isMicrophoneEnabled = false
                return
            }
        }

        isMicrophoneEnabled = enabled
        try await reconfigureAudioOnQueue()
    }

    func tearDownSession() {
        segmentTimer?.invalidate()
        segmentTimer = nil
        sessionQueue.async {
            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            }
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
        Task { @MainActor in
            isSessionRunning = false
            isRecording = false
            PowerGuard.setRecordingActive(false)
            stopElapsedTimer()
            recordingStartedAt = nil
            makeOutputURL = nil
        }
    }

    private func startSegmentRecording(to url: URL) async throws {
        currentOutputURL = url

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                guard self.session.outputs.contains(self.movieOutput) else {
                    continuation.resume(throwing: CameraServiceError.configurationFailed)
                    return
                }

                if self.movieOutput.isRecording {
                    continuation.resume(throwing: CameraServiceError.recordingFailed("相机仍在结束上一段录像。"))
                    return
                }

                if let connection = self.movieOutput.connection(with: .video) {
                    if connection.isVideoOrientationSupported {
                        connection.videoOrientation = .portrait
                    }
                    if self.cameraPosition == .front, connection.isVideoMirroringSupported {
                        connection.isVideoMirrored = true
                    }
                }

                self.movieOutput.startRecording(to: url, recordingDelegate: self)
                continuation.resume()
            }
        }
    }

    private func scheduleSegmentRotation() {
        segmentTimer?.invalidate()
        segmentTimer = Timer.scheduledTimer(withTimeInterval: segmentDuration, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
    self?.rotateSegmentNow()
}
        }
    }

    private func reconfigureCameraOnQueue() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    try self.reconfigureCameraInput()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func reconfigureAudioOnQueue() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    try self.reconfigureAudioInput()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func startSessionIfNeeded() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                if !self.session.isRunning {
                    self.session.startRunning()
                }
                continuation.resume()
            }
        }
        isSessionRunning = true
    }

    private func configureSession() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        let preset = qualitySettings.resolution.sessionPreset
        if session.canSetSessionPreset(preset) {
            session.sessionPreset = preset
        } else if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        }

        for input in session.inputs { session.removeInput(input) }
        for output in session.outputs { session.removeOutput(output) }
        videoInput = nil
        audioInput = nil

        try addCameraInput()
        guard session.canAddOutput(movieOutput) else {
            throw CameraServiceError.configurationFailed
        }
        session.addOutput(movieOutput)
        try addAudioInput()
    }

    private func reconfigureCameraInput() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        removeCameraInput()
        try addCameraInput()
    }

    private func reconfigureAudioInput() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        removeAudioInput()
        try addAudioInput()
    }

    private func removeCameraInput() {
        if let videoInput {
            session.removeInput(videoInput)
            self.videoInput = nil
        }
    }

    private func addCameraInput() throws {
        guard let device = Self.cameraDevice(for: cameraPosition.avPosition) else {
            throw CameraServiceError.cameraUnavailable
        }

        try configureDevice(device)

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CameraServiceError.configurationFailed
        }
        session.addInput(input)
        videoInput = input
    }

    private func configureDevice(_ device: AVCaptureDevice) throws {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        if device.isLowLightBoostSupported {
            device.automaticallyEnablesLowLightBoostWhenAvailable = lowLightBoostEnabled
        }

        let fps = Double(qualitySettings.frameRate.rawValue)
        if device.activeFormat.videoSupportedFrameRateRanges.contains(where: {
            $0.minFrameRate <= fps && fps <= $0.maxFrameRate
        }) {
            let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
            device.activeVideoMinFrameDuration = frameDuration
            device.activeVideoMaxFrameDuration = frameDuration
        }
    }

    private func removeAudioInput() {
        if let audioInput {
            session.removeInput(audioInput)
            self.audioInput = nil
        }
    }

    private func addAudioInput() throws {
        guard isMicrophoneEnabled else { return }
        guard let device = AVCaptureDevice.default(for: .audio) else {
            throw CameraServiceError.microphoneUnavailable
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CameraServiceError.configurationFailed
        }
        session.addInput(input)
        audioInput = input
    }

    private func requestAccess(for mediaType: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: mediaType) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted: return false
        @unknown default: return false
        }
    }

    private static func cameraDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: position
        ).devices.first
    }

    private func startElapsedTimer() {
        stopElapsedTimer()
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let recordingStartedAt else { return }
                self.elapsedSeconds = Int(Date().timeIntervalSince(recordingStartedAt))
                if let max = self.maxRecordingDuration, TimeInterval(self.elapsedSeconds) >= max {
                    self.stopRecording(reason: .maxDuration)
                }
            }
    }

    private func stopElapsedTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    @MainActor
    private func handleSegmentFinished(url: URL, error: Error?) {
        if let error {
            errorMessage = CameraServiceError.recordingFailed(error.localizedDescription).localizedDescription
            finalizeStop(reason: pendingStopReason)
            return
        }

        onSegmentFinished?(url, currentSegmentIndex)

        if isRotatingSegment, isRecording, let makeOutputURL {
            currentSegmentIndex += 1
            isRotatingSegment = false
            Task { @MainActor in
                do {
                    let nextURL = makeOutputURL()
                    try await startSegmentRecording(to: nextURL)
                } catch {
                    errorMessage = error.localizedDescription
                    finalizeStop(reason: .user)
                }
            }
            return
        }

        finalizeStop(reason: pendingStopReason)
    }

    @MainActor
    private func finalizeStop(reason: RecordingStopReason) {
        isRecording = false
        PowerGuard.setRecordingActive(false)
        stopElapsedTimer()
        recordingStartedAt = nil
        segmentTimer?.invalidate()
        segmentTimer = nil
        currentOutputURL = nil
        onRecordingStopped?(reason)
    }
}

extension CameraService: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        Task { @MainActor [weak self] in
            self?.errorMessage = nil
        }
    }

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            self?.handleSegmentFinished(url: outputFileURL, error: error)
        }
    }
}
