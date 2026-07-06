import UIKit

enum PowerGuard {
    static func setRecordingActive(_ active: Bool) {
        UIApplication.shared.isIdleTimerDisabled = active
    }
}
