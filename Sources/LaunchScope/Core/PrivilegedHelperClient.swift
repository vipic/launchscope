import Foundation
import LaunchScopePrivilegedProtocol

protocol PrivilegedControlling: Sendable {
    func setGlobalAgentEnabled(item: StartupItem, enabled: Bool) -> StartupItemControlResult
    func setDaemonEnabled(item: StartupItem, enabled: Bool) -> StartupItemControlResult
}

struct PrivilegedHelperClient: PrivilegedControlling, Sendable {
    func setGlobalAgentEnabled(item: StartupItem, enabled: Bool) -> StartupItemControlResult {
        guard let path = item.sourcePath,
              let hash = item.controlMetadata["fileSHA256"] else {
            return failure("缺少扫描时的安全校验信息，请重新扫描。")
        }
        let connection = NSXPCConnection(
            machServiceName: PrivilegedServiceIdentity.machServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: LaunchScopePrivilegedHelperProtocol.self)
        connection.setCodeSigningRequirement(PrivilegedServiceIdentity.helperRequirement)
        connection.resume()
        defer { connection.invalidate() }

        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var result: StartupItemControlResult?
        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            lock.lock()
            result = self.failure("无法连接管理员辅助程序：\(error.localizedDescription)。请先在“管理员辅助程序”中完成注册和批准。")
            lock.unlock()
            semaphore.signal()
        } as? LaunchScopePrivilegedHelperProtocol
        proxy?.setGlobalLaunchAgentEnabled(
            path: path,
            label: item.label,
            expectedSHA256: hash,
            enabled: enabled
        ) { outcome, title, message in
            lock.lock()
            result = StartupItemControlResult(
                outcome: StartupItemControlOutcome(rawValue: outcome) ?? .failure,
                title: title,
                message: message
            )
            lock.unlock()
            semaphore.signal()
        }
        guard proxy != nil, semaphore.wait(timeout: .now() + 10) == .success else {
            return failure("管理员辅助程序响应超时。请检查批准状态后重试。")
        }
        lock.lock()
        defer { lock.unlock() }
        return result ?? failure("管理员辅助程序未返回结果。")
    }

    func setDaemonEnabled(item: StartupItem, enabled: Bool) -> StartupItemControlResult {
        perform(item: item) { proxy, path, hash, reply in
            proxy.setLaunchDaemonEnabled(
                path: path, label: item.label, expectedSHA256: hash, enabled: enabled, reply: reply
            )
        }
    }

    private func perform(
        item: StartupItem,
        request: (LaunchScopePrivilegedHelperProtocol, String, String, @escaping (String, String, String) -> Void) -> Void
    ) -> StartupItemControlResult {
        guard let path = item.sourcePath, let hash = item.controlMetadata["fileSHA256"] else {
            return failure("缺少扫描时的安全校验信息，请重新扫描。")
        }
        let connection = NSXPCConnection(machServiceName: PrivilegedServiceIdentity.machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: LaunchScopePrivilegedHelperProtocol.self)
        connection.setCodeSigningRequirement(PrivilegedServiceIdentity.helperRequirement)
        connection.resume()
        defer { connection.invalidate() }
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var result: StartupItemControlResult?
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
            lock.lock()
            result = self.failure("无法连接管理员辅助程序：\(error.localizedDescription)。请先完成注册和批准。")
            lock.unlock()
            semaphore.signal()
        }) as? LaunchScopePrivilegedHelperProtocol else { return failure("无法创建管理员辅助程序连接。") }
        request(proxy, path, hash) { outcome, title, message in
            lock.lock()
            result = StartupItemControlResult(
                outcome: StartupItemControlOutcome(rawValue: outcome) ?? .failure,
                title: title, message: message
            )
            lock.unlock()
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 10) == .success else { return failure("管理员辅助程序响应超时。") }
        lock.lock()
        defer { lock.unlock() }
        return result ?? failure("管理员辅助程序未返回结果。")
    }

    private func failure(_ message: String) -> StartupItemControlResult {
        StartupItemControlResult(outcome: .failure, title: "管理员操作失败", message: message)
    }
}
