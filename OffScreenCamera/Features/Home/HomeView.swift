import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var cameraService: CameraService
    @EnvironmentObject private var videoStorage: VideoStorage

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

                VStack(spacing: 24) {
                    header
                    settingsCard
                    startButton
                    notes
                    Spacer()
                }
                .padding(24)
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
                videoStorage.refresh()
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

            Text("开始后会进入全黑界面。这不是锁屏录制，按电源键锁屏会停止录像。")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
        }
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("摄像头")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))

                Picker("摄像头", selection: $cameraService.cameraPosition) {
                    ForEach(CameraPosition.allCases) { position in
                        Text(position.title).tag(position)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(isPreparing || cameraService.isRecording)
                .onChange(of: cameraService.cameraPosition) { _, newValue in
                    Task {
                        do {
                            try await cameraService.switchCamera(to: newValue)
                        } catch {
                            alertMessage = error.localizedDescription
                        }
                    }
                }
            }

            Toggle(isOn: Binding(
                get: { cameraService.isMicrophoneEnabled },
                set: { newValue in
                    Task {
                        do {
                            try await cameraService.setMicrophoneEnabled(newValue)
                        } catch {
                            alertMessage = error.localizedDescription
                        }
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("录制声音")
                        .foregroundStyle(.white)
                    Text("关闭后仅保存画面，不采集麦克风。")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .tint(.green)
            .disabled(isPreparing || cameraService.isRecording)
        }
        .padding(20)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
    }

    private var startButton: some View {
        Button {
            Task { await startRecordingFlow() }
        } label: {
            HStack {
                if isPreparing {
                    ProgressView()
                        .tint(.black)
                }
                Text(isPreparing ? "准备中..." : "开始黑屏录像")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(.white, in: RoundedRectangle(cornerRadius: 16))
            .foregroundStyle(.black)
        }
        .disabled(isPreparing)
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("录像时屏幕保持纯黑，可手动调低系统亮度。", systemImage: "light.min")
            Label("系统可能显示相机绿点，无法隐藏。", systemImage: "camera.fill")
            Label("免费 Apple ID 安装的 App 约 7 天需重装。", systemImage: "arrow.clockwise")
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(0.55))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @MainActor
    private func startRecordingFlow() async {
        isPreparing = true
        defer { isPreparing = false }

        let granted = await cameraService.requestPermissions()
        guard granted else {
            alertMessage = cameraService.errorMessage
            return
        }

        do {
            try await cameraService.prepareSession()
            let outputURL = videoStorage.makeOutputURL()
            try await cameraService.startRecording(to: outputURL)
            isRecordingPresented = true
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func handleRecordingDismiss() {
        cameraService.tearDownSession()
        videoStorage.refresh()
        if let errorMessage = cameraService.errorMessage {
            alertMessage = errorMessage
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(CameraService())
        .environmentObject(VideoStorage())
}
