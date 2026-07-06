import AVFoundation
import Combine
import Foundation
import UIKit

@MainActor
final class SystemProtectionMonitor: ObservableObject {
    @Published var warningMessage: String?
    private var interruptionObserver: NSObjectProtocol?

    func stopMonitoring() {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }
    }

    func checkStorage(minimumFreeBytes: Int64 = 500_000_000) -> Bool {
        guard let free = freeDiskSpace else { return true }
        if free < minimumFreeBytes {
            warningMessage = "存储空间不足（剩余 \(ByteCountFormatter.string(fromByteCount: free, countStyle: .file))）。"
            return false
        }
        return true
    }

    func checkBattery(minimumLevel: Float = 0.05) -> Bool {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        if level >= 0, level < minimumLevel {
            warningMessage = "电量过低（\(Int(level * 100))%），录像已停止。"
            return false
        }
        return true
    }

    func setupInterruptionHandler(onInterruption: @escaping () -> Void) {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard
                let info = notification.userInfo,
                let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                let type = AVAudioSession.InterruptionType(rawValue: typeValue),
                type == .began
            else { return }
            onInterruption()
        }
    }

    var freeDiskSpace: Int64? {
        let path = NSHomeDirectory()
        guard
            let attrs = try? FileManager.default.attributesOfFileSystem(forPath: path),
            let free = attrs[.systemFreeSize] as? NSNumber
        else { return nil }
        return free.int64Value
    }
}
