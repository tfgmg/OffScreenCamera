import AVFoundation
import Foundation

enum CameraPosition: String, CaseIterable, Identifiable, Codable {
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

enum VideoResolution: String, CaseIterable, Identifiable, Codable {
    case p720
    case p1080
    case p4K

    var id: String { rawValue }

    var title: String {
        switch self {
        case .p720: return "720p"
        case .p1080: return "1080p"
        case .p4K: return "4K"
        }
    }

    var sessionPreset: AVCaptureSession.Preset {
        switch self {
        case .p720: return .hd1280x720
        case .p1080: return .hd1920x1080
        case .p4K: return .hd4K3840x2160
        }
    }
}

enum VideoFrameRate: Int, CaseIterable, Identifiable, Codable {
    case fps24 = 24
    case fps30 = 30

    var id: Int { rawValue }

    var title: String { "\(rawValue) fps" }
}

enum VideoBitrateLevel: String, CaseIterable, Identifiable, Codable {
    case low
    case medium
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: return "低（省空间）"
        case .medium: return "中（均衡）"
        case .high: return "高（清晰）"
        }
    }

    var bitsPerSecond: Int {
        switch self {
        case .low: return 2_000_000
        case .medium: return 4_000_000
        case .high: return 8_000_000
        }
    }
}

enum SegmentDurationOption: Int, CaseIterable, Identifiable, Codable {
    case five = 5
    case ten = 10
    case fifteen = 15
    case thirty = 30

    var id: Int { rawValue }

    var title: String { "\(rawValue) 分钟" }

    var seconds: TimeInterval { TimeInterval(rawValue * 60) }
}

enum MaxRecordingDuration: Int, CaseIterable, Identifiable, Codable {
    case thirtyMinutes = 30
    case oneHour = 60
    case twoHours = 120
    case unlimited = 0

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .thirtyMinutes: return "30 分钟"
        case .oneHour: return "1 小时"
        case .twoHours: return "2 小时"
        case .unlimited: return "不限"
        }
    }

    var seconds: TimeInterval? {
        rawValue == 0 ? nil : TimeInterval(rawValue * 60)
    }
}

struct VideoQualitySettings: Codable, Equatable {
    var resolution: VideoResolution = .p1080
    var frameRate: VideoFrameRate = .fps30
    var bitrate: VideoBitrateLevel = .medium
}

struct RecordedVideo: Identifiable, Equatable, Hashable {
    let id: UUID
    let url: URL
    let createdAt: Date
    let fileSize: Int64
    let duration: TimeInterval?

    var fileName: String { url.lastPathComponent }

    var formattedDate: String {
        createdAt.formatted(date: .abbreviated, time: .standard)
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var formattedDuration: String {
        guard let duration, duration > 0 else { return "--:--" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

enum CameraServiceError: LocalizedError {
    case cameraUnavailable
    case microphoneUnavailable
    case permissionDenied(String)
    case configurationFailed
    case recordingFailed(String)
    case storageFull
    case maxDurationReached
    case lowBattery

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable: return "找不到可用的摄像头。"
        case .microphoneUnavailable: return "找不到可用的麦克风。"
        case .permissionDenied(let message): return message
        case .configurationFailed: return "相机初始化失败，请重试。"
        case .recordingFailed(let message): return "录像失败：\(message)"
        case .storageFull: return "存储空间不足，录像已停止。"
        case .maxDurationReached: return "已达到最长录制时间。"
        case .lowBattery: return "电量过低，录像已停止。"
        }
    }
}

enum RecordingStopReason: Equatable {
    case user
    case volumeKey
    case maxDuration
    case lowBattery
    case storageFull
    case interruption
}
