import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("录制", systemImage: "video.fill")
                }

            VideoLibraryView()
                .tabItem {
                    Label("文件", systemImage: "folder.fill")
                }
        }
        .tint(.white)
    }
}

#Preview {
    ContentView()
        .environmentObject(CameraService())
        .environmentObject(VideoStorage())
}
