import SwiftUI

struct RecordingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var cameraService: CameraService
    @EnvironmentObject private var videoStorage: VideoStorage

    @StateObject private var volumeMonitor = VolumeButtonMonitor()
    @StateObject private var protection = SystemProtectionMonitor()
    @State private var protectionTimer: Timer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack {
                HStack {
                    recordingBadge
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(formattedElapsed)
                            .font(.caption.monospacedDigit())
                        Text("段 \(cameraService.currentSegmentIndex)")
                            .font(.caption2.monospacedDigit())
                    }
                    .foregroundStyle(.white.opacity(0.3))
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Spacer()

                Text("音量+ ×3 开始 · 音量- ×3 停止")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.18))
                    .padding(.bottom, 40)
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            volumeMonitor.onVolumeDownTriple = {
                stopAndDismiss(reason: .volumeKey)
            }
            volumeMonitor.start()

            protection.setupInterruptionHandler {
                stopAndDismiss(reason: .interruption)
            }

            protectionTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
                Task { @MainActor in
                    if !protection.checkBattery() {
                        stopAndDismiss(reason: .lowBattery)
                    } else if !protection.checkStorage() {
                        stopAndDismiss(reason: .storageFull)
                    }
                }
            }
        }
        .onDisappear {
            volumeMonitor.stop()
            protection.stopMonitoring()
            protectionTimer?.invalidate()
        }
    }

    private var recordingBadge: some View {
        HStack(spacing: 8) {
            Circle().fill(.red).frame(width: 8, height: 8)
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

    @MainActor
    private func stopAndDismiss(reason: RecordingStopReason) {
        guard cameraService.isRecording else {
            dismiss()
            return
        }
        cameraService.stopRecording(reason: reason)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            videoStorage.refresh()
            dismiss()
        }
    }
}
