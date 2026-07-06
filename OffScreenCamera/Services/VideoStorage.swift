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

    func refresh() {
        do {
            try fileManager.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)

            let urls = try fileManager.contentsOfDirectory(
                at: recordingsDirectory,
                includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
            .filter { $0.pathExtension.lowercased() == "mov" || $0.pathExtension.lowercased() == "mp4" }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return lhsDate > rhsDate
            }

            videos = urls.compactMap { url in
                guard
                    let values = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey]),
                    let createdAt = values.creationDate
                else {
                    return nil
                }

                return RecordedVideo(
                    id: UUID(),
                    url: url,
                    createdAt: createdAt,
                    fileSize: Int64(values.fileSize ?? 0)
                )
            }
        } catch {
            videos = []
        }
    }

    func makeOutputURL() -> URL {
        try? fileManager.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let name = "REC_\(formatter.string(from: Date())).mov"
        return recordingsDirectory.appendingPathComponent(name)
    }

    func delete(_ video: RecordedVideo) throws {
        try fileManager.removeItem(at: video.url)
        refresh()
    }

    func exportToPhotoLibrary(_ video: RecordedVideo) async throws {
        try await PHPhotoLibrary.requestAuthorization(for: .addOnly).checkAddOnlyAccess()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: video.url)
            }, completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: CameraServiceError.recordingFailed("保存到相册失败"))
                }
            })
        }
    }
}

private extension PHAuthorizationStatus {
    func checkAddOnlyAccess() throws {
        switch self {
        case .authorized, .limited:
            return
        case .notDetermined:
            throw CameraServiceError.permissionDenied("请先允许访问相册。")
        case .denied, .restricted:
            throw CameraServiceError.permissionDenied("相册权限被拒绝，请到系统设置中开启。")
        @unknown default:
            throw CameraServiceError.permissionDenied("相册权限不可用。")
        }
    }
}
