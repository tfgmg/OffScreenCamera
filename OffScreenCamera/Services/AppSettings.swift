import Combine
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var cameraPosition: CameraPosition {
        didSet { save(cameraPosition.rawValue, for: Keys.cameraPosition) }
    }
    @Published var isMicrophoneEnabled: Bool {
        didSet { save(isMicrophoneEnabled, for: Keys.microphone) }
    }
    @Published var quality: VideoQualitySettings {
        didSet { saveEncoded(quality, for: Keys.quality) }
    }
    @Published var segmentDuration: SegmentDurationOption {
        didSet { save(segmentDuration.rawValue, for: Keys.segmentDuration) }
    }
    @Published var maxRecordingDuration: MaxRecordingDuration {
        didSet { save(maxRecordingDuration.rawValue, for: Keys.maxDuration) }
    }
    @Published var deleteAfterExport: Bool {
        didSet { save(deleteAfterExport, for: Keys.deleteAfterExport) }
    }
    @Published var disguiseEnabled: Bool {
        didSet { save(disguiseEnabled, for: Keys.disguiseEnabled) }
    }
    @Published var biometricEnabled: Bool {
        didSet { save(biometricEnabled, for: Keys.biometricEnabled) }
    }
    @Published var lowLightBoostEnabled: Bool {
        didSet { save(lowLightBoostEnabled, for: Keys.lowLightBoost) }
    }
    @Published var hasCompletedOnboarding: Bool {
        didSet { save(hasCompletedOnboarding, for: Keys.onboarding) }
    }

    private enum Keys {
        static let cameraPosition = "settings.cameraPosition"
        static let microphone = "settings.microphone"
        static let quality = "settings.quality"
        static let segmentDuration = "settings.segmentDuration"
        static let maxDuration = "settings.maxDuration"
        static let deleteAfterExport = "settings.deleteAfterExport"
        static let disguiseEnabled = "settings.disguiseEnabled"
        static let biometricEnabled = "settings.biometricEnabled"
        static let lowLightBoost = "settings.lowLightBoost"
        static let onboarding = "settings.onboarding"
    }

    private let defaults = UserDefaults.standard

    init() {
        cameraPosition = CameraPosition(rawValue: defaults.string(forKey: Keys.cameraPosition) ?? "") ?? .back
        isMicrophoneEnabled = defaults.object(forKey: Keys.microphone) as? Bool ?? true
        quality = Self.loadEncoded(VideoQualitySettings.self, key: Keys.quality) ?? VideoQualitySettings()
        let segmentRaw = defaults.integer(forKey: Keys.segmentDuration)
        segmentDuration = SegmentDurationOption(rawValue: segmentRaw == 0 ? 10 : segmentRaw) ?? .ten
        let maxRaw = defaults.integer(forKey: Keys.maxDuration)
        maxRecordingDuration = MaxRecordingDuration(rawValue: maxRaw) ?? .unlimited
        deleteAfterExport = defaults.bool(forKey: Keys.deleteAfterExport)
        disguiseEnabled = defaults.object(forKey: Keys.disguiseEnabled) as? Bool ?? true
        biometricEnabled = defaults.bool(forKey: Keys.biometricEnabled)
        lowLightBoostEnabled = defaults.object(forKey: Keys.lowLightBoost) as? Bool ?? true
        hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarding)
    }

    func applyToCameraService(_ camera: CameraService) {
        camera.cameraPosition = cameraPosition
        camera.isMicrophoneEnabled = isMicrophoneEnabled
        camera.qualitySettings = quality
        camera.lowLightBoostEnabled = lowLightBoostEnabled
    }

    func syncFromCameraService(_ camera: CameraService) {
        cameraPosition = camera.cameraPosition
        isMicrophoneEnabled = camera.isMicrophoneEnabled
        quality = camera.qualitySettings
    }

    private func save(_ value: Any, for key: String) {
        defaults.set(value, forKey: key)
    }

    private func saveEncoded<T: Encodable>(_ value: T, for key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private static func loadEncoded<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
