import AVFoundation
import Combine

final class CameraService: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var isSessionRunning = false
    @Published var cameraPosition: CameraPosition = .back
    @Published var isMicrophoneEnabled = true
    @Published var elapsedSeconds = 0
    @Published var currentSegmentIndex = 1
    @Published var errorMessage: String?
    @Published var qualitySettings = VideoQualitySettings()
    @Published var lowLightBoostEnabled = true

    var segmentDuration: TimeInterval = 600
    var maxRecordingDuration: TimeInterval?
    var onSegmentFinished: (@MainActor (URL, Int) -> Void)?
    var onRecordingStopped: (@MainActor (RecordingStopReason) -> Void)?

    private let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let sessionQueue = DispatchQueue(label: "com.offscreen.camera.session")

    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var timerCancellable: AnyCancellable?
    private var segmentTimer: Timer?
    private var recordingStartedAt: Date?
    private var currentOutputURL: URL?
    private var isRotatingSegment = false
    private var pendingStopReason: RecordingStopReason = .user
    private var makeOutputURL: (@MainActor () -> URL)?

    override init() {
        super.init()
    }

    func requestPermissions() async -> Bool {
        let cameraGranted = await requestAccess(for: .video)
        guard cameraGranted else {
            errorMessage = CameraServiceError.permissionDenied("相机权限被拒绝，请到系统设置中开启。").localizedDescription
            return false
        }

        if isMicrophoneEnabled {
            let micGranted = await requestAccess(for: .audio)
            if !micGranted {
                errorMessage = CameraServiceError.permissionDenied("麦克风权限被拒绝，已改为静音录像。").localizedDescription
                isMicrophoneEnabled = false
            }
        }

        return true
    }

    func prepareSession() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    try self.configureSession()
                    continuation.resume()
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

        isRecording = true
        recordingStartedAt = Date()
        elapsedSeconds = 0
        PowerGuard.setRecordingActive(true)
        startElapsedTimer()
        scheduleSegmentRotation()
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
        isSessionRunning = false
        isRecording = false
        PowerGuard.setRecordingActive(false)
        stopElapsedTimer()
        recordingStartedAt = nil
        makeOutputURL = nil
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
            Task { @MainActor in self?.rotateSegmentNow() }
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
