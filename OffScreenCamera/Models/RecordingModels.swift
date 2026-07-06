import AVFoundation
import Foundation

enum CameraPosition: String, CaseIterable, Identifiable {
    case back
    case front

    var id: String { rawValue }

    var title: String {
        switch self {
        case .back: return "后置"
        case .front: return "前置"
        }
    }

    var avPosition: AVCaptureDevice.Position {
        switch self {
        case .back: return .back
        case .front: return .front
        }
    }
}

struct RecordedVideo: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let createdAt: Date
    let fileSize: Int64

    var fileName: String {
        url.lastPathComponent
    }

    var formattedDate: String {
        createdAt.formatted(date: .abbreviated, time: .standard)
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

enum CameraServiceError: LocalizedError {
    case cameraUnavailable
    case microphoneUnavailable
    case permissionDenied(String)
    case configurationFailed
    case recordingFailed(String)

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            return "找不到可用的摄像头。"
        case .microphoneUnavailable:
            return "找不到可用的麦克风。"
        case .permissionDenied(let message):
            return message
        case .configurationFailed:
            return "相机初始化失败，请重试。"
        case .recordingFailed(let message):
            return "录像失败：\(message)"
        }
    }
}
