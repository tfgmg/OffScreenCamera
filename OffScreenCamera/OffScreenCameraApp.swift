import SwiftUI

@main
struct OffScreenCameraApp: App {
    @StateObject private var cameraService = CameraService()
    @StateObject private var videoStorage = VideoStorage()
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var appLock = AppLockService.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(cameraService)
                .environmentObject(videoStorage)
                .environmentObject(settings)
                .environmentObject(appLock)
                .onAppear {
                    settings.applyToCameraService(cameraService)
                }
        }
    }
}
