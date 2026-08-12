import Foundation
import LaunchScopePrivilegedProtocol

private final class PrivilegedHelperService: NSObject, LaunchScopePrivilegedHelperProtocol {
    func ping(reply: @escaping (Int, String) -> Void) {
        reply(PrivilegedServiceIdentity.helperVersion, "LaunchScope privileged helper ready")
    }
}

private final class PrivilegedHelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service = PrivilegedHelperService()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard getuid() == 0 else { return false }
        connection.setCodeSigningRequirement(PrivilegedServiceIdentity.appRequirement)
        connection.exportedInterface = NSXPCInterface(with: LaunchScopePrivilegedHelperProtocol.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }
}

private let delegate = PrivilegedHelperListenerDelegate()
let listener = NSXPCListener(machServiceName: PrivilegedServiceIdentity.machServiceName)
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
