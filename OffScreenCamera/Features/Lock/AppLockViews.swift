import SwiftUI

struct SetupPINView: View {
    @ObservedObject var appLock: AppLockService
    let onComplete: () -> Void

    @State private var pin = ""
    @State private var confirmPIN = ""
    @State private var step = 0
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text(step == 0 ? "设置 App 密码" : "再次输入确认")
                    .font(.title2.weight(.semibold))

                Text("至少 4 位数字。伪装计算器界面输入密码后按 = 解锁。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                SecureField("密码", text: step == 0 ? $pin : $confirmPIN)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 40)

                Button(step == 0 ? "下一步" : "完成") {
                    handleNext()
                }
                .buttonStyle(.borderedProminent)
                .disabled((step == 0 ? pin : confirmPIN).count < 4)
            }
            .padding(24)
            .navigationTitle("安全设置")
            .alert("提示", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好的", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func handleNext() {
        if step == 0 {
            step = 1
        } else {
            guard pin == confirmPIN else {
                errorMessage = "两次输入不一致。"
                confirmPIN = ""
                return
            }
            do {
                try appLock.setPIN(pin)
                onComplete()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct AppLockView: View {
    @ObservedObject var appLock: AppLockService
    let onUnlocked: () -> Void

    @State private var pin = ""

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)

            Text("输入密码解锁")
                .font(.title3.weight(.semibold))

            SecureField("密码", text: $pin)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 40)

            Button("解锁") {
                if appLock.verifyPIN(pin) {
                    onUnlocked()
                }
            }
            .buttonStyle(.borderedProminent)

            if AppSettings.shared.biometricEnabled {
                Button("使用 Face ID / 指纹") {
                    Task { @MainActor in
                        if await appLock.unlockWithBiometrics() {
                            onUnlocked()
                        }
                    }
                }
            }
        }
        .padding(24)
    }
}
