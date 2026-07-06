import Combine
import CryptoKit
import Foundation
import LocalAuthentication
import Security

@MainActor
final class AppLockService: ObservableObject {
    static let shared = AppLockService()

    @Published private(set) var isUnlocked = false
    @Published var hasPIN: Bool

    private let pinKey = "com.offscreen.camera.pinHash"
    private let service = "com.offscreen.camera.lock"
    private let failedAttemptsKey = "lock.failedAttempts"
    private let lockedUntilKey = "lock.lockedUntil"
    private let defaults = UserDefaults.standard

    init() {
        hasPIN = KeychainHelper.read(key: pinKey, service: service) != nil
        isUnlocked = !hasPIN
    }

    func setPIN(_ pin: String) throws {
        guard pin.count >= 4, pin.allSatisfy(\.isNumber) else {
            throw AppLockError.invalidPIN
        }
        let hash = Self.hash(pin)
        try KeychainHelper.save(hash, key: pinKey, service: service)
        hasPIN = true
        isUnlocked = true
    }

    func verifyPIN(_ pin: String) -> Bool {
        guard !isTemporarilyLocked else { return false }
        guard let stored = KeychainHelper.read(key: pinKey, service: service) else { return false }
        let valid = stored == Self.hash(pin)
        if valid {
            defaults.set(0, forKey: failedAttemptsKey)
            defaults.removeObject(forKey: lockedUntilKey)
            isUnlocked = true
        } else {
            registerFailedAttempt()
        }
        return valid
    }

    func unlockWithBiometrics(reason: String = "解锁黑屏录像") async -> Bool {
        guard AppSettings.shared.biometricEnabled else { return false }

        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return false
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            if success { isUnlocked = true }
            return success
        } catch {
            return false
        }
    }

    func lock() {
        guard hasPIN else { return }
        isUnlocked = false
    }

    func changePIN(from oldPIN: String, to newPIN: String) throws {
        guard verifyPIN(oldPIN) else { throw AppLockError.wrongPIN }
        try setPIN(newPIN)
    }

    private static func hash(_ pin: String) -> String {
        let digest = SHA256.hash(data: Data(pin.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private var isTemporarilyLocked: Bool {
        Date().timeIntervalSince1970 < defaults.double(forKey: lockedUntilKey)
    }

    private func registerFailedAttempt() {
        let attempts = defaults.integer(forKey: failedAttemptsKey) + 1
        defaults.set(attempts, forKey: failedAttemptsKey)

        if attempts >= 5 {
            defaults.set(Date().addingTimeInterval(60).timeIntervalSince1970, forKey: lockedUntilKey)
            defaults.set(0, forKey: failedAttemptsKey)
        }
    }
}

enum AppLockError: LocalizedError {
    case invalidPIN
    case wrongPIN

    var errorDescription: String? {
        switch self {
        case .invalidPIN: return "密码至少 4 位数字。"
        case .wrongPIN: return "密码错误。"
        }
    }
}

enum KeychainHelper {
    static func save(_ value: String, key: String, service: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw AppLockError.invalidPIN }
    }

    static func read(key: String, service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
