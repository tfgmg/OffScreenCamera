import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var cameraService: CameraService
    @EnvironmentObject private var videoStorage: VideoStorage
    @ObservedObject private var settings = AppSettings.shared

    @StateObject private var volumeMonitor = VolumeButtonMonitor()
    @State private var isRecordingPresented = false
    @State private var isPreparing = false
    @State private var alertMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.08, green: 0.08, blue: 0.1), .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        header
                        quickSettingsCard
                        actionButtons
                        notes
                    }
                    .padding(24)
                }
            }
            .navigationTitle("黑屏录像")
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $isRecordingPresented, onDismiss: handleRecordingDismiss) {
                RecordingView()
            }
            .alert("提示", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("好的", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
            .onAppear {
                settings.applyToCameraService(cameraService)
                videoStorage.refresh()
                volumeMonitor.onVolumeUpTriple = {
                guard !cameraService.isRecording, !isPreparing, !isRecordingPresented else { return }
                Task { await startRecordingFlow() }
            }
                volumeMonitor.start()
            }
            .onDisappear {
                volumeMonitor.stop()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "moon.fill")
                .font(.system(size: 42))
                .foregroundStyle(.white.opacity(0.9))
            Text("伪息屏摄像头录像")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text("分段 \(settings.segmentDuration.title) · \(settings.quality.resolution.title) · 音量+×3 开始 / 音量-×3 停止")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
        }
    }

    private var quickSettingsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("摄像头", selection: $settings.cameraPosition) {
                ForEach(CameraPosition.allCases) { position in
                    Text(position.title).tag(position)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isPreparing || cameraService.isRecording)
            .onChange(of: settings.cameraPosition) { _, newValue in
                Task {
                    do { try await cameraService.switchCamera(to: newValue) }
                    catch { alertMessage = error.localizedDescription }
                }
            }

            Toggle(isOn: $settings.isMicrophoneEnabled) {
                Text("录制声音")
                    .foregroundStyle(.white)
            }
            .tint(.green)
            .disabled(isPreparing || cameraService.isRecording)
            .onChange(of: settings.isMicrophoneEnabled) { _, enabled in
                Task {
                    do { try await cameraService.setMicrophoneEnabled(enabled) }
                    catch { alertMessage = error.localizedDescription }
                }
            }
        }
        .padding(20)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                Task { await startRecordingFlow() }
            } label: {
                HStack {
                    if isPreparing { ProgressView().tint(.black) }
                    Text(isPreparing ? "准备中..." : "开始黑屏录像")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(.white, in: RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(.black)
            }
            .disabled(isPreparing)

            Button {
                Task { await startRecordingFlow() }
            } label: {
                Label("息屏并开始录制", systemImage: "moon.zzz.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .disabled(isPreparing)
        }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("全黑界面录制，请手动调低亮度。", systemImage: "light.min")
            Label("系统相机绿点无法隐藏。", systemImage: "camera.fill")
            Label("详细选项请前往「设置」。", systemImage: "gearshape")
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(0.55))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @MainActor
    private func startRecordingFlow() async {
        isPreparing = true
        defer { isPreparing = false }

        settings.applyToCameraService(cameraService)
        cameraService.segmentDuration = settings.segmentDuration.seconds
        cameraService.maxRecordingDuration = settings.maxRecordingDuration.seconds

        let granted = await cameraService.requestPermissions()
        guard granted else {
            alertMessage = cameraService.errorMessage
            return
        }

        setupRecordingCallbacks()

        do {
            try await cameraService.prepareSession()
            try await cameraService.startRecordingSession {
                videoStorage.makeOutputURL(segmentIndex: cameraService.currentSegmentIndex)
            }
            isRecordingPresented = true
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func setupRecordingCallbacks() {
        cameraService.onSegmentFinished = { _, _ in
            videoStorage.refresh()
        }
        cameraService.onRecordingStopped = { reason in
            if reason != .user && reason != .volumeKey {
                alertMessage = stopReasonMessage(reason)
            }
            videoStorage.refresh()
        }
    }

    private func stopReasonMessage(_ reason: RecordingStopReason) -> String {
        switch reason {
        case .maxDuration: return "已达到最长录制时间。"
        case .lowBattery: return "电量过低，录像已停止。"
        case .storageFull: return "存储空间不足，录像已停止。"
        case .interruption: return "来电或中断，录像已停止。"
        default: return "录像已停止。"
        }
    }

    private func handleRecordingDismiss() {
        if cameraService.isRecording {
            cameraService.stopRecording(reason: .user)
        }
        cameraService.tearDownSession()
        videoStorage.refresh()
    }
}
