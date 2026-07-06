import SwiftUI

struct RootView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var appLock = AppLockService.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var showMainApp = false
    @State private var needsPINSetup = false

    var body: some View {
        Group {
            if !settings.hasCompletedOnboarding {
                OnboardingView {
                    needsPINSetup = !appLock.hasPIN
                }
            } else if needsPINSetup || !appLock.hasPIN {
                SetupPINView(appLock: appLock) {
                    needsPINSetup = false
                    showMainApp = false
                }
            } else if settings.disguiseEnabled && !showMainApp {
                CalculatorDisguiseView(appLock: appLock) {
                    showMainApp = true
                }
            } else if !appLock.isUnlocked {
                AppLockView(appLock: appLock) {
                    showMainApp = true
                }
            } else {
                MainTabView()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                appLock.lock()
                showMainApp = false
            }
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("录制", systemImage: "video.fill") }

            VideoLibraryView()
                .tabItem { Label("文件", systemImage: "folder.fill") }

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
        .tint(.white)
    }
}
