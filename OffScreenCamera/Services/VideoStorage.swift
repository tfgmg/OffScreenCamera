import AVFoundation
import Combine
import CoreMedia
import Foundation
import Photos

@MainActor
final class VideoStorage: ObservableObject {
    @Published private(set) var videos: [RecordedVideo] = []

    private let fileManager = FileManager.default

    var recordingsDirectory: URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("Recordings", isDirectory: true)
    }

    private func ensureRecordingsDirectory() throws {
        try fileManager.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: recordingsDirectory.path
        )
    }

    func refresh() {
        Task { @MainActor in await loadVideos() }
    }

    private func loadDuration(from asset: AVURLAsset) async -> TimeInterval? {
        guard let time = try? await asset.load(.duration), time.isValid else { return nil }
        return time.seconds
    }

    func loadVideos() async {
        do {
            try ensureRecordingsDirectory()

            let urls = try fileManager.contentsOfDirectory(
                at: recordingsDirectory,
                includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
            .filter { ["mov", "mp4"].contains($0.pathExtension.lowercased()) }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return lhsDate > rhsDate
            }

            var loaded: [RecordedVideo] = []
            for url in urls {
                guard
                    let values = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey]),
                    let createdAt = values.creationDate
                else { continue }

                let asset = AVURLAsset(url: url)
                let duration = await loadDuration(from: asset)

                loaded.append(RecordedVideo(
                    id: UUID(),
                    url: url,
                    createdAt: createdAt,
                    fileSize: Int64(values.fileSize ?? 0),
                    duration: duration
                ))
            }
            videos = loaded
        } catch {
            videos = []
        }
    }

    func makeOutputURL(segmentIndex: Int) -> URL {
        try? ensureRecordingsDirectory()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let name = "REC_\(formatter.string(from: Date()))_\(String(format: "%03d", segmentIndex)).mov"
        return recordingsDirectory.appendingPathComponent(name)
    }

    func makeMergedOutputURL() -> URL {
        try? ensureRecordingsDirectory()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return recordingsDirectory.appendingPathComponent("MERGE_\(formatter.string(from: Date())).mov")
    }

    func delete(_ videos: [RecordedVideo]) throws {
        for video in videos {
            try fileManager.removeItem(at: video.url)
        }
        refresh()
    }

    func exportToPhotoLibrary(_ videos: [RecordedVideo], deleteAfterExport: Bool) async throws {
        try await PHPhotoLibrary.requestAuthorization(for: .addOnly).checkAddOnlyAccess()

        for video in videos {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: video.url)
                }, completionHandler: { success, error in
                    if let error { continuation.resume(throwing: error) }
                    else if success { continuation.resume() }
                    else { continuation.resume(throwing: CameraServiceError.recordingFailed("保存到相册失败")) }
                })
            }
        }

        if deleteAfterExport {
            try delete(videos)
        }
    }

    func merge(_ videos: [RecordedVideo]) async throws -> RecordedVideo {
        let outputURL = makeMergedOutputURL()
        try await VideoMergeService.merge(videos: videos, outputURL: outputURL)

        let values = try outputURL.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
        let asset = AVURLAsset(url: outputURL)
        let duration = await loadDuration(from: asset)
        let merged = RecordedVideo(
            id: UUID(),
            url: outputURL,
            createdAt: values.creationDate ?? Date(),
            fileSize: Int64(values.fileSize ?? 0),
            duration: duration
        )
        await loadVideos()
        return merged
    }
}

private extension PHAuthorizationStatus {
    func checkAddOnlyAccess() throws {
        switch self {
        case .authorized, .limited: return
        case .notDetermined: throw CameraServiceError.permissionDenied("请先允许访问相册。")
        case .denied, .restricted: throw CameraServiceError.permissionDenied("相册权限被拒绝，请到系统设置中开启。")
        @unknown default: throw CameraServiceError.permissionDenied("相册权限不可用。")
        }
    }
}
