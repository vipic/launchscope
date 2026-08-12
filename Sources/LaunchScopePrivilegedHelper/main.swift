import Foundation
import LaunchScopePrivilegedCore
import LaunchScopePrivilegedProtocol

private final class PrivilegedHelperService: NSObject, LaunchScopePrivilegedHelperProtocol {
    private let userIdentifier: uid_t
    private let controller = PrivilegedLaunchItemController()

    init(userIdentifier: uid_t) { self.userIdentifier = userIdentifier }

    func ping(reply: @escaping (Int, String) -> Void) {
        reply(PrivilegedServiceIdentity.helperVersion, "LaunchScope privileged helper ready")
    }

    func setGlobalLaunchAgentEnabled(
        path: String,
        label: String,
        expectedSHA256: String,
        enabled: Bool,
        reply: @escaping (String, String, String) -> Void
    ) {
        let result = controller.setGlobalAgentEnabled(
            path: path,
            label: label,
            expectedSHA256: expectedSHA256,
            enabled: enabled,
            userIdentifier: userIdentifier
        )
        reply(result.outcome, result.title, result.message)
    }

    func setLaunchDaemonEnabled(
        path: String,
        label: String,
        expectedSHA256: String,
        enabled: Bool,
        reply: @escaping (String, String, String) -> Void
    ) {
        let result = controller.setDaemonEnabled(
            path: path, label: label, expectedSHA256: expectedSHA256, enabled: enabled
        )
        reply(result.outcome, result.title, result.message)
    }
}

private final class PrivilegedHelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard getuid() == 0 else { return false }
        connection.setCodeSigningRequirement(PrivilegedServiceIdentity.appRequirement)
        connection.exportedInterface = NSXPCInterface(with: LaunchScopePrivilegedHelperProtocol.self)
        connection.exportedObject = PrivilegedHelperService(userIdentifier: connection.effectiveUserIdentifier)
        connection.resume()
        return true
    }
}

private let delegate = PrivilegedHelperListenerDelegate()
let listener = NSXPCListener(machServiceName: PrivilegedServiceIdentity.machServiceName)
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
