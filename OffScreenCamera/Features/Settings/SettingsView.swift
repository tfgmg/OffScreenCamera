import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var appLock = AppLockService.shared
    @EnvironmentObject private var cameraService: CameraService

    @State private var oldPIN = ""
    @State private var newPIN = ""
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("录制") {
                    Picker("分段时长", selection: $settings.segmentDuration) {
                        ForEach(SegmentDurationOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    Picker("最长录制", selection: $settings.maxRecordingDuration) {
                        ForEach(MaxRecordingDuration.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    Toggle("低光增强", isOn: $settings.lowLightBoostEnabled)
                }

                Section("画质") {
                    Picker("分辨率", selection: $settings.quality.resolution) {
                        ForEach(VideoResolution.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    Picker("帧率", selection: $settings.quality.frameRate) {
                        ForEach(VideoFrameRate.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    Picker("码率", selection: $settings.quality.bitrate) {
                        ForEach(VideoBitrateLevel.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                }

                Section("文件") {
                    Toggle("导出相册后删除 App 内副本", isOn: $settings.deleteAfterExport)
                }

                Section("安全") {
                    Toggle("计算器伪装入口", isOn: $settings.disguiseEnabled)
                    Toggle("Face ID / 指纹", isOn: $settings.biometricEnabled)

                    SecureField("旧密码", text: $oldPIN)
                        .keyboardType(.numberPad)
                    SecureField("新密码", text: $newPIN)
                        .keyboardType(.numberPad)
                    Button("修改密码") {
                        do {
                            try appLock.changePIN(from: oldPIN, to: newPIN)
                            message = "密码已更新。"
                            oldPIN = ""
                            newPIN = ""
                        } catch {
                            message = error.localizedDescription
                        }
                    }
                }

                Section("说明") {
                    Label("无定时启停功能", systemImage: "clock.badge.xmark")
                    Label("锁屏后录像停止", systemImage: "lock.fill")
                    Label("相机绿点无法隐藏", systemImage: "camera.fill")
                }
            }
            .navigationTitle("设置")
            .onChange(of: settings.cameraPosition) { _, _ in syncCamera() }
            .onChange(of: settings.isMicrophoneEnabled) { _, _ in syncCamera() }
            .onChange(of: settings.lowLightBoostEnabled) { _, _ in syncCamera() }
            .onChange(of: settings.quality.resolution) { _, _ in syncQuality() }
            .onChange(of: settings.quality.frameRate) { _, _ in syncQuality() }
            .onChange(of: settings.quality.bitrate) { _, _ in syncQuality() }
            .alert("提示", isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("好的", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }
    }

    private func syncCamera() {
        settings.applyToCameraService(cameraService)
    }

    private func syncQuality() {
        if let data = try? JSONEncoder().encode(settings.quality) {
            UserDefaults.standard.set(data, forKey: "settings.quality")
        }
        settings.applyToCameraService(cameraService)
    }
}
