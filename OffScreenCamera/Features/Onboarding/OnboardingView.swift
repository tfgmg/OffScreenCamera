import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void

    var body: some View {
        TabView {
            onboardingPage(
                icon: "moon.fill",
                title: "黑屏录像",
                text: "录制时使用全黑界面，可手动调低亮度。按电源键锁屏会停止录像。"
            )
            onboardingPage(
                icon: "camera.fill",
                title: "系统限制",
                text: "相机绿点无法隐藏。音量键三连仅在黑屏录制页有效。"
            )
            onboardingPage(
                icon: "lock.fill",
                title: "隐私保护",
                text: "默认计算器伪装入口，App 内密码保护。文件默认仅存 App 内。"
            )
            VStack(spacing: 24) {
                onboardingPage(
                    icon: "film.stack",
                    title: "分段与画质",
                    text: "可自定义分段时长、分辨率与低光优化。支持批量导出与合并。"
                )
                Button("开始使用") {
                    AppSettings.shared.hasCompletedOnboarding = true
                    onFinish()
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 12)
            }
        }
        .tabViewStyle(.page)
    }

    private func onboardingPage(icon: String, title: String, text: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 52))
                .foregroundStyle(.primary)
            Text(title)
                .font(.title2.weight(.bold))
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.vertical, 40)
    }
}
