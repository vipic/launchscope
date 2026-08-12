import Foundation
import LaunchScopePrivilegedProtocol
import ServiceManagement

enum PrivilegedHelperAuthorizationStatus: Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound

    var title: String {
        switch self {
        case .notRegistered: "尚未注册"
        case .enabled: "已授权并启用"
        case .requiresApproval: "等待管理员批准"
        case .notFound: "辅助程序不在应用包内"
        }
    }
}

@MainActor
final class PrivilegedHelperManager: ObservableObject {
    @Published private(set) var status: PrivilegedHelperAuthorizationStatus = .notRegistered
    @Published private(set) var connectionMessage: String?
    @Published private(set) var errorMessage: String?
    private var connection: NSXPCConnection?

    init() { refreshStatus() }

    func refreshStatus() {
        let plistURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LaunchDaemons", isDirectory: true)
            .appendingPathComponent(PrivilegedServiceIdentity.plistName)
        guard FileManager.default.fileExists(atPath: plistURL.path) else {
            status = .notFound
            return
        }
        status = switch service.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        case .notRegistered: .notRegistered
        @unknown default: .notRegistered
        }
    }

    func register() {
        do {
            try service.register()
            errorMessage = nil
        } catch {
            errorMessage = "注册辅助程序失败：\(error.localizedDescription)"
        }
        refreshStatus()
    }

    func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func testConnection() {
        connection?.invalidate()
        let connection = NSXPCConnection(
            machServiceName: PrivilegedServiceIdentity.machServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: LaunchScopePrivilegedHelperProtocol.self)
        connection.setCodeSigningRequirement(PrivilegedServiceIdentity.helperRequirement)
        connection.invalidationHandler = { [weak self] in
            Task { @MainActor in self?.connection = nil }
        }
        connection.resume()
        self.connection = connection
        let proxy = connection.remoteObjectProxyWithErrorHandler { [weak self] error in
            Task { @MainActor in
                self?.errorMessage = "辅助程序连接失败：\(error.localizedDescription)"
            }
        } as? LaunchScopePrivilegedHelperProtocol
        proxy?.ping { [weak self] version, message in
            Task { @MainActor in
                guard version == PrivilegedServiceIdentity.helperVersion else {
                    self?.errorMessage = "辅助程序协议版本不匹配。"
                    return
                }
                self?.connectionMessage = message
                self?.errorMessage = nil
            }
        }
    }

    private var service: SMAppService {
        SMAppService.daemon(plistName: PrivilegedServiceIdentity.plistName)
    }
}
