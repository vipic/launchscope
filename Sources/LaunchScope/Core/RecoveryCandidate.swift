import Foundation

struct RecoveryCandidate: Identifiable, Sendable {
    var item: StartupItem
    var action: StartupItemControlAction
    var id: String { item.id }
}

extension StartupItemControlAction {
    var isRecoveryAction: Bool {
        switch self {
        case .enable, .enableCron, .enableShellLine, .startHomebrew: true
        case .disable, .disableCron, .disableShellLine, .stopHomebrew: false
        }
    }
}
