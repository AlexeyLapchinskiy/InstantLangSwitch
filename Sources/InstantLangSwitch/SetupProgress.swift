import Foundation

struct SetupProgress {
    let inputMonitoringGranted: Bool
    let globeKeyAction: Int?
    let keyboardOpenedAt: Date?
    let now: Date

    var keyboardDone: Bool {
        if let globeKeyAction { return globeKeyAction == 0 }
        guard let keyboardOpenedAt else { return false }
        return now.timeIntervalSince(keyboardOpenedAt) >= 15
    }

    var isComplete: Bool {
        inputMonitoringGranted && keyboardDone
    }
}
