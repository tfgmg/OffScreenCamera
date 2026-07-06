import SwiftUI

@main
struct OffScreenCameraApp: App {
    @StateObject private var cameraService = CameraService()
    @StateObject private var videoStorage = VideoStorage()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(cameraService)
                .environmentObject(videoStorage)
        }
    }
}
