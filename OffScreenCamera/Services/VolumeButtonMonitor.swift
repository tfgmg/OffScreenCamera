import AVFoundation
import Combine
import MediaPlayer
import UIKit

@MainActor
final class VolumeButtonMonitor: ObservableObject {
    var onVolumeUpTriple: (@MainActor () -> Void)?
    var onVolumeDownTriple: (@MainActor () -> Void)?

    private var volumeView: MPVolumeView?
    private var observation: NSKeyValueObservation?
    private var lastVolume: Float = 0
    private var pressTimestamps: [Date] = []
    private var lastDirection: VolumeDirection?
    private let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1, height: 1))

    enum VolumeDirection {
        case up
        case down
    }

    func start() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, options: [.mixWithOthers, .defaultToSpeaker])
        try? session.setActive(true)

        lastVolume = session.outputVolume

        let view = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 0, height: 0))
        view.isHidden = false
        view.alpha = 0.01
        window.rootViewController = UIViewController()
        window.windowLevel = UIWindow.Level(UIWindow.Level.alert.rawValue - 1)
        window.isHidden = false
        window.rootViewController?.view.addSubview(view)
        volumeView = view

        observation = session.observe(\.outputVolume, options: [.new, .old]) { [weak self] _, change in
            guard let newValue = change.newValue, let oldValue = change.oldValue else { return }
            Task { @MainActor [weak self] in
                self?.handleVolumeChange(from: oldValue, to: newValue)
            }
        }
    }

    func stop() {
        observation?.invalidate()
        observation = nil
        volumeView?.removeFromSuperview()
        volumeView = nil
        window.isHidden = true
        pressTimestamps.removeAll()
        lastDirection = nil
    }

    private func handleVolumeChange(from oldValue: Float, to newValue: Float) {
        let delta = newValue - oldValue
        guard abs(delta) > 0.001 else { return }

        let direction: VolumeDirection = delta > 0 ? .up : .down
        let now = Date()

        if lastDirection != direction {
            pressTimestamps.removeAll()
        }
        lastDirection = direction
        pressTimestamps.append(now)
        pressTimestamps = pressTimestamps.filter { now.timeIntervalSince($0) <= 2.0 }

        restoreVolume(oldValue)

        if pressTimestamps.count >= 3 {
            pressTimestamps.removeAll()
            switch direction {
            case .up: onVolumeUpTriple?()
            case .down: onVolumeDownTriple?()
            }
        }
    }

    private func restoreVolume(_ volume: Float) {
        guard let slider = volumeView?.subviews.compactMap({ $0 as? UISlider }).first else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000)
            slider.value = volume
        }
    }
}
