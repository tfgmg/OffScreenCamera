import SwiftUI

struct RecordingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var cameraService: CameraService
    @EnvironmentObject private var videoStorage: VideoStorage

    @State private var showStopHint = true

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack {
                HStack {
                    recordingBadge
                    Spacer()
                    Text(formattedElapsed)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.35))
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Spacer()

                if showStopHint {
                    Text("双击屏幕停止录像")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.25))
                        .padding(.bottom, 40)
                }
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onTapGesture(count: 2) {
            stopAndDismiss()
        }
        .onAppear {
            showStopHint = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                withAnimation {
                    showStopHint = false
                }
            }
        }
        .onDisappear {
            if cameraService.isRecording {
                cameraService.stopRecording()
            }
        }
    }

    private var recordingBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
            Text(cameraService.isMicrophoneEnabled ? "录像中" : "静音录像中")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.white.opacity(0.08), in: Capsule())
    }

    private var formattedElapsed: String {
        let minutes = cameraService.elapsedSeconds / 60
        let seconds = cameraService.elapsedSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func stopAndDismiss() {
        cameraService.stopRecording()
        videoStorage.refresh()
        dismiss()
    }
}

#Preview {
    RecordingView()
        .environmentObject(CameraService())
        .environmentObject(VideoStorage())
}
