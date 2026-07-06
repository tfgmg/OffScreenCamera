import SwiftUI
import AVKit

struct VideoLibraryView: View {
    @EnvironmentObject private var videoStorage: VideoStorage
    @ObservedObject private var settings = AppSettings.shared

    @State private var selectedIDs = Set<UUID>()
    @State private var isSelecting = false
    @State private var previewVideo: RecordedVideo?
    @State private var alertMessage: String?
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            Group {
                if videoStorage.videos.isEmpty {
                    ContentUnavailableView(
                        "暂无录像",
                        systemImage: "video.slash",
                        description: Text("完成录制后，分段文件会保存在这里。")
                    )
                } else {
                    List {
                        ForEach(videoStorage.videos) { video in
                            row(for: video)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("录像文件")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !videoStorage.videos.isEmpty {
                        Button(isSelecting ? "取消" : "选择") {
                            isSelecting.toggle()
                            if !isSelecting { selectedIDs.removeAll() }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSelecting {
                        Button(selectedIDs.count == videoStorage.videos.count ? "取消全选" : "全选") {
                            if selectedIDs.count == videoStorage.videos.count {
                                selectedIDs.removeAll()
                            } else {
                                selectedIDs = Set(videoStorage.videos.map(\.id))
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isSelecting, !selectedIDs.isEmpty {
                    batchToolbar
                }
            }
            .onAppear { videoStorage.refresh() }
            .sheet(item: $previewVideo) { video in
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

    private func row(for video: RecordedVideo) -> some View {
        Button {
            if isSelecting {
                toggleSelection(video)
            } else {
                previewVideo = video
            }
        } label: {
            HStack(spacing: 14) {
                if isSelecting {
                    Image(systemName: selectedIDs.contains(video.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selectedIDs.contains(video.id) ? .blue : .secondary)
                }
                Image(systemName: "film")
                    .foregroundStyle(.blue)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(video.fileName)
                        .lineLimit(1)
                        .font(.body.weight(.medium))
                    Text("\(video.formattedDate) · \(video.formattedDuration) · \(video.formattedSize)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private var batchToolbar: some View {
        HStack(spacing: 12) {
            Text("已选 \(selectedIDs.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("合并") { Task { await mergeSelected() } }
            Button("导出") { Task { await exportSelected() } }
            Button("分享") { shareSelected() }
            Button("删除", role: .destructive) { deleteSelected() }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private var selectedVideos: [RecordedVideo] {
        videoStorage.videos.filter { selectedIDs.contains($0.id) }
    }

    private func toggleSelection(_ video: RecordedVideo) {
        if selectedIDs.contains(video.id) {
            selectedIDs.remove(video.id)
        } else {
            selectedIDs.insert(video.id)
        }
    }

    private func deleteSelected() {
        do {
            try videoStorage.delete(selectedVideos)
            selectedIDs.removeAll()
            isSelecting = false
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func exportSelected() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await videoStorage.exportToPhotoLibrary(
                selectedVideos,
                deleteAfterExport: settings.deleteAfterExport
            )
            alertMessage = settings.deleteAfterExport ? "已导出并删除 App 内副本。" : "已保存到相册。"
            selectedIDs.removeAll()
            isSelecting = false
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func mergeSelected() async {
        guard selectedVideos.count >= 2 else {
            alertMessage = "请至少选择 2 个文件合并。"
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await videoStorage.merge(selectedVideos)
            alertMessage = "合并完成。"
            selectedIDs.removeAll()
            isSelecting = false
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func shareSelected() {
        guard let first = selectedURLs.first else { return }
        let controller = UIActivityViewController(activityItems: selectedURLs, applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(controller, animated: true)
        }
    }

    private var selectedURLs: [URL] {
        selectedVideos.map(\.url)
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
                        Button("关闭") { dismiss() }
                    }
                }
        }
    }
}
