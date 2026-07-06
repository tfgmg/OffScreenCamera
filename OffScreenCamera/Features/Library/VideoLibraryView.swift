import SwiftUI
import AVKit

struct VideoLibraryView: View {
    @EnvironmentObject private var videoStorage: VideoStorage

    @State private var selectedVideo: RecordedVideo?
    @State private var alertMessage: String?
    @State private var exportingVideoID: UUID?

    var body: some View {
        NavigationStack {
            Group {
                if videoStorage.videos.isEmpty {
                    ContentUnavailableView(
                        "暂无录像",
                        systemImage: "video.slash",
                        description: Text("完成一次黑屏录像后，文件会出现在这里。")
                    )
                } else {
                    List {
                        ForEach(videoStorage.videos) { video in
                            Button {
                                selectedVideo = video
                            } label: {
                                VideoRow(
                                    video: video,
                                    isExporting: exportingVideoID == video.id
                                )
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button("保存相册") {
                                    Task { await export(video) }
                                }
                                .tint(.blue)

                                Button(role: .destructive) {
                                    delete(video)
                                } label: {
                                    Text("删除")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("录像文件")
            .onAppear {
                videoStorage.refresh()
            }
            .sheet(item: $selectedVideo) { video in
                VideoPlayerSheet(video: video)
            }
            .alert("提示", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("好的", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }

    private func export(_ video: RecordedVideo) async {
        exportingVideoID = video.id
        defer { exportingVideoID = nil }

        do {
            try await videoStorage.exportToPhotoLibrary(video)
            alertMessage = "已保存到相册。"
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func delete(_ video: RecordedVideo) {
        do {
            try videoStorage.delete(video)
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}

private struct VideoRow: View {
    let video: RecordedVideo
    let isExporting: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "film")
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(video.fileName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text("\(video.formattedDate) · \(video.formattedSize)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isExporting {
                ProgressView()
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct VideoPlayerSheet: View {
    let video: RecordedVideo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VideoPlayer(player: AVPlayer(url: video.url))
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("预览")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("关闭") {
                            dismiss()
                        }
                    }
                }
        }
    }
}

#Preview {
    VideoLibraryView()
        .environmentObject(VideoStorage())
}
