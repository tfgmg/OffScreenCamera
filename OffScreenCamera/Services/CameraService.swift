import AVFoundation
import Combine

@MainActor
final class CameraService: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var isSessionRunning = false
    @Published var cameraPosition: CameraPosition = .back
    @Published var isMicrophoneEnabled = true
    @Published var elapsedSeconds = 0
    @Published var errorMessage: String?

    private let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let sessionQueue = DispatchQueue(label: "com.offscreen.camera.session")

    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var timerCancellable: AnyCancellable?
    private var recordingStartedAt: Date?
    private var currentOutputURL: URL?

    override init() {
        super.init()
        session.sessionPreset = .high
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

    func startRecording(to url: URL) async throws {
        guard !isRecording else { return }

        if !isSessionRunning {
            try await prepareSession()
        }

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

                if let connection = self.movieOutput.connection(with: .video), connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }

                if self.cameraPosition == .front,
                   let connection = self.movieOutput.connection(with: .video),
                   connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = true
                }

                self.movieOutput.startRecording(to: url, recordingDelegate: self)
                continuation.resume()
            }
        }

        isRecording = true
        recordingStartedAt = Date()
        elapsedSeconds = 0
        PowerGuard.setRecordingActive(true)
        startElapsedTimer()
    }

    func stopRecording() {
        guard isRecording else { return }

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

    func tearDownSession() {
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

        for input in session.inputs {
            session.removeInput(input)
        }
        for output in session.outputs {
            session.removeOutput(output)
        }
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

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CameraServiceError.configurationFailed
        }
        session.addInput(input)
        videoInput = input
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
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: mediaType) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private static func cameraDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: position
        )
        return discovery.devices.first
    }

    private func startElapsedTimer() {
        stopElapsedTimer()
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let recordingStartedAt else { return }
                self.elapsedSeconds = Int(Date().timeIntervalSince(recordingStartedAt))
            }
    }

    private func stopElapsedTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
        recordingStartedAt = nil
    }

    private func finishRecording(success: Bool) {
        isRecording = false
        PowerGuard.setRecordingActive(false)
        stopElapsedTimer()

        if !success {
            if let url = currentOutputURL {
                try? FileManager.default.removeItem(at: url)
            }
        }

        currentOutputURL = nil
    }
}

extension CameraService: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        Task { @MainActor in
            self.errorMessage = nil
        }
    }

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                self.errorMessage = CameraServiceError.recordingFailed(error.localizedDescription).localizedDescription
                self.finishRecording(success: false)
            } else {
                self.finishRecording(success: true)
            }
        }
    }
}
