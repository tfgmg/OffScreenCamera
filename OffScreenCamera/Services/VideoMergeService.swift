import AVFoundation

enum VideoMergeService {
    static func merge(videos: [RecordedVideo], outputURL: URL) async throws {
        guard !videos.isEmpty else { return }

        let composition = AVMutableComposition()

        guard
            let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
            let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else {
            throw CameraServiceError.recordingFailed("无法创建合并轨道。")
        }

        var cursor = CMTime.zero

        for video in videos.sorted(by: { $0.createdAt < $1.createdAt }) {
            let asset = AVURLAsset(url: video.url)
            let duration = try await asset.load(.duration)
            let timeRange = CMTimeRange(start: .zero, duration: duration)

            if let sourceVideo = try await asset.loadTracks(withMediaType: .video).first {
                try videoTrack.insertTimeRange(timeRange, of: sourceVideo, at: cursor)
            }
            if let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first {
                try audioTrack.insertTimeRange(timeRange, of: sourceAudio, at: cursor)
            }
            cursor = CMTimeAdd(cursor, duration)
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw CameraServiceError.recordingFailed("无法启动导出。")
        }

        export.outputURL = outputURL
        export.outputFileType = .mov

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            export.exportAsynchronously {
                if let error = export.error {
                    continuation.resume(throwing: error)
                } else if export.status == .completed {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: CameraServiceError.recordingFailed("合并失败。"))
                }
            }
        }
    }
}
