import Foundation

enum StartupItemControlAction: String, Codable, Equatable, Sendable {
    case disable
    case enable
    case stopHomebrew
    case startHomebrew
    case disableCron
    case enableCron
    case disableShellLine
    case enableShellLine
    case disableGlobalAgent
    case enableGlobalAgent
    case disableDaemon
    case enableDaemon

    var title: String {
        switch self {
        case .disable: "停用"
        case .enable: "恢复启用"
        case .stopHomebrew: "停止服务"
        case .startHomebrew: "启动服务"
        case .disableCron, .disableShellLine: "安全停用"
        case .enableCron, .enableShellLine: "恢复启用"
        case .disableGlobalAgent: "停用全局 Agent"
        case .enableGlobalAgent: "恢复全局 Agent"
        case .disableDaemon: "停用 LaunchDaemon"
        case .enableDaemon: "恢复 LaunchDaemon"
        }
    }

    var isDestructive: Bool {
        self == .disable || self == .stopHomebrew || self == .disableCron || self == .disableShellLine || self == .disableGlobalAgent || self == .disableDaemon
    }

    var inverse: StartupItemControlAction {
        switch self {
        case .disable: .enable
        case .enable: .disable
        case .stopHomebrew: .startHomebrew
        case .startHomebrew: .stopHomebrew
        case .disableCron: .enableCron
        case .enableCron: .disableCron
        case .disableShellLine: .enableShellLine
        case .enableShellLine: .disableShellLine
        case .disableGlobalAgent: .enableGlobalAgent
        case .enableGlobalAgent: .disableGlobalAgent
        case .disableDaemon: .enableDaemon
        case .enableDaemon: .disableDaemon
        }
    }

    var confirmationTitle: String {
        switch self {
        case .disable: "停用这个 LaunchAgent？"
        case .enable: "恢复启用这个 LaunchAgent？"
        case .stopHomebrew: "停止这个 Homebrew 服务？"
        case .startHomebrew: "启动这个 Homebrew 服务？"
        case .disableCron: "停用这条 Cron 规则？"
        case .enableCron: "恢复这条 Cron 规则？"
        case .disableShellLine: "停用这条 Shell 命令？"
        case .enableShellLine: "恢复这条 Shell 命令？"
        case .disableGlobalAgent: "停用当前用户的全局 LaunchAgent？"
        case .enableGlobalAgent: "恢复当前用户的全局 LaunchAgent？"
        case .disableDaemon: "停用这个系统级 LaunchDaemon？"
        case .enableDaemon: "恢复这个系统级 LaunchDaemon？"
        }
    }

    var confirmationMessage: String {
        switch self {
        case .disable:
            "LaunchScope 会禁止该项目后续自动加载，并卸载当前任务；不会删除或改写 plist，可以随时恢复。"
        case .enable:
            "LaunchScope 会恢复 launchd 允许状态，并重新加载原有 plist。"
        case .stopHomebrew:
            "LaunchScope 会调用 brew services stop，立即停止服务并取消登录时自动启动；以后可以重新启动。"
        case .startHomebrew:
            "LaunchScope 会调用 brew services start，立即启动服务并注册为登录时自动启动。"
        case .disableCron:
            "LaunchScope 会重新读取完整 crontab，确认目标行未变化后将该行标记为停用；原文保留在可恢复标记中。"
        case .enableCron:
            "LaunchScope 只会恢复由自身标记且内容完全匹配的 Cron 行。"
        case .disableShellLine:
            "LaunchScope 会确认文件归当前用户所有且目标行未变化，再原子地注释这一行；不会执行其中的命令。"
        case .enableShellLine:
            "LaunchScope 只会恢复由自身标记且内容完全匹配的 Shell 行；文件变化时会拒绝覆盖。"
        case .disableGlobalAgent:
            "管理员辅助程序会重新校验 root 所有权、路径、文件指纹、Label 与非 Apple 执行目标，再停用当前用户的实例；不会改写 plist。"
        case .enableGlobalAgent:
            "管理员辅助程序会重新执行全部安全校验，再恢复当前用户的允许状态并加载原 plist。"
        case .disableDaemon:
            "该操作影响整个系统。辅助程序会重新校验 root 所有权、路径、指纹、Label 与非 Apple 目标，再停用并卸载任务；不会改写 plist。"
        case .enableDaemon:
            "该操作影响整个系统。辅助程序会重新执行全部安全校验，再恢复允许状态并加载原 plist。"
        }
    }
}

enum StartupItemControlOutcome: String, Codable, Equatable, Sendable {
    case success
    case partial
    case failure
}

struct StartupItemControlResult: Identifiable, Sendable {
    var id = UUID()
    var outcome: StartupItemControlOutcome
    var title: String
    var message: String
}

struct StartupItemController: Sendable {
    var runner: any CommandRunning = CommandRunner()
    var homeDirectory = NSHomeDirectory()
    var userIdentifier = getuid()
    var homebrewExecutable = HomebrewLocator.executablePath()
    var privilegedController: any PrivilegedControlling = PrivilegedHelperClient()

    func availableAction(for item: StartupItem) -> StartupItemControlAction? {
        if validatedLaunchAgentTarget(for: item) != nil {
            return item.isEnabled == false ? .enable : .disable
        }
        if validatedHomebrewService(for: item) != nil {
            return item.runtime.state == .running ? .stopHomebrew : .startHomebrew
        }
        if validatedGlobalAgent(for: item) != nil {
            return item.isEnabled == false ? .enableGlobalAgent : .disableGlobalAgent
        }
        if validatedDaemon(for: item) != nil {
            return item.isEnabled == false ? .enableDaemon : .disableDaemon
        }
        if validatedTextLine(for: item, source: .cron) != nil {
            return item.isEnabled == false ? .enableCron : .disableCron
        }
        if validatedShellLine(for: item) != nil {
            return item.isEnabled == false ? .enableShellLine : .disableShellLine
        }
        return nil
    }

    func perform(_ action: StartupItemControlAction, on item: StartupItem) -> StartupItemControlResult {
        guard availableAction(for: item) == action else {
            return StartupItemControlResult(
                outcome: .failure,
                title: "无法执行操作",
                message: "项目状态已变化，或该项目不满足安全操作条件。请重新扫描后再试。"
            )
        }

        switch action {
        case .disable, .enable:
            return performLaunchAgent(action, on: item)
        case .stopHomebrew, .startHomebrew:
            return performHomebrew(action, on: item)
        case .disableCron, .enableCron:
            return performCron(action, on: item)
        case .disableShellLine, .enableShellLine:
            return performShellLine(action, on: item)
        case .disableGlobalAgent, .enableGlobalAgent:
            return privilegedController.setGlobalAgentEnabled(item: item, enabled: action == .enableGlobalAgent)
        case .disableDaemon, .enableDaemon:
            return privilegedController.setDaemonEnabled(item: item, enabled: action == .enableDaemon)
        }
    }

    private func performLaunchAgent(
        _ action: StartupItemControlAction,
        on item: StartupItem
    ) -> StartupItemControlResult {
        guard let target = validatedLaunchAgentTarget(for: item), let sourcePath = item.sourcePath else {
            return invalidTargetResult()
        }

        let overrideVerb = action == .disable ? "disable" : "enable"
        let override = runner.run(
            executable: "/bin/launchctl",
            arguments: [overrideVerb, target.serviceTarget],
            timeout: 4
        )
        guard override.exitCode == 0 else {
            return failureResult(action: action, phase: "更新允许状态", command: override)
        }

        let runtime: CommandResult
        switch action {
        case .disable:
            runtime = runner.run(
                executable: "/bin/launchctl",
                arguments: ["bootout", target.domain, sourcePath],
                timeout: 4
            )
        case .enable:
            runtime = runner.run(
                executable: "/bin/launchctl",
                arguments: ["bootstrap", target.domain, sourcePath],
                timeout: 4
            )
        case .stopHomebrew, .startHomebrew, .disableCron, .enableCron, .disableShellLine, .enableShellLine, .disableGlobalAgent, .enableGlobalAgent, .disableDaemon, .enableDaemon:
            return invalidTargetResult()
        }

        if runtime.exitCode == 0 {
            return StartupItemControlResult(
                outcome: .success,
                title: action == .disable ? "已停用" : "已恢复启用",
                message: action == .disable
                    ? "launchd 已禁止后续自动加载，并已卸载当前任务。配置文件保持不变。"
                    : "launchd 已恢复允许状态，并已重新加载配置文件。"
            )
        }

        let detail = commandMessage(runtime)
        return StartupItemControlResult(
            outcome: .partial,
            title: "允许状态已更新",
            message: action == .disable
                ? "项目已标记为停用，但卸载当前任务失败：\(detail)"
                : "项目已恢复允许，但重新加载失败：\(detail)"
        )
    }

    private func performCron(_ action: StartupItemControlAction, on item: StartupItem) -> StartupItemControlResult {
        guard let target = validatedTextLine(for: item, source: .cron) else { return invalidTargetResult() }
        let current = runner.run(executable: "/usr/bin/crontab", arguments: ["-l"], timeout: 3)
        guard current.exitCode == 0 else { return failureResult(action: action, phase: "读取 crontab", command: current) }
        do {
            guard ManagedTextLine.fingerprint(current.standardOutput) == target.fingerprint else {
                throw ManagedTextLineError.lineChanged
            }
            let updated = try ManagedTextLine.replacingLine(
                in: current.standardOutput,
                lineNumber: target.lineNumber,
                expectedOriginal: target.original,
                enable: action == .enableCron
            )
            let url = try secureCrontabFile(contents: Data(updated.utf8))
            defer { try? FileManager.default.removeItem(at: url) }
            let install = runner.run(executable: "/usr/bin/crontab", arguments: [url.path], timeout: 4)
            guard install.exitCode == 0 else { return failureResult(action: action, phase: "更新 crontab", command: install) }
            return successResult(action: action, kind: "Cron 规则")
        } catch {
            return textFailure(error)
        }
    }

    private func secureCrontabFile(contents: Data) throws -> URL {
        var template = Array("/tmp/com.nekutai.launchscope.crontab.XXXXXX".utf8CString)
        let descriptor = mkstemp(&template)
        guard descriptor >= 0 else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: "无法创建安全的临时 crontab 文件。"])
        }
        let url = URL(fileURLWithPath: String(cString: template))
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: contents)
            try handle.close()
            return url
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    private func performShellLine(_ action: StartupItemControlAction, on item: StartupItem) -> StartupItemControlResult {
        guard let target = validatedShellLine(for: item) else { return invalidTargetResult() }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == userIdentifier else {
                throw ManagedTextLineError.unsafeFile
            }
            let data = try Data(contentsOf: URL(fileURLWithPath: target.path))
            guard let current = String(data: data, encoding: .utf8) else { throw ManagedTextLineError.invalidEncoding }
            guard ManagedTextLine.fingerprint(current) == target.fingerprint else {
                throw ManagedTextLineError.lineChanged
            }
            let updated = try ManagedTextLine.replacingLine(
                in: current,
                lineNumber: target.lineNumber,
                expectedOriginal: target.original,
                enable: action == .enableShellLine
            )
            try Data(updated.utf8).write(to: URL(fileURLWithPath: target.path), options: .atomic)
            if let permissions = attributes[.posixPermissions] {
                try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.path)
            }
            return successResult(action: action, kind: "Shell 命令")
        } catch {
            return textFailure(error)
        }
    }

    private func validatedTextLine(for item: StartupItem, source: StartupSource) -> (lineNumber: Int, original: String, fingerprint: String)? {
        guard item.source == source, !item.isAppleItem,
              let value = item.controlMetadata["line"], let lineNumber = Int(value), lineNumber > 0,
              let original = item.controlMetadata["original"], !original.contains("\n"),
              let fingerprint = item.controlMetadata["fingerprint"], fingerprint.count == 64 else { return nil }
        return (lineNumber, original, fingerprint)
    }

    private func validatedShellLine(for item: StartupItem) -> (path: String, lineNumber: Int, original: String, fingerprint: String)? {
        guard let line = validatedTextLine(for: item, source: .shellConfiguration), let path = item.sourcePath else { return nil }
        guard item.configuration["可安全单行修改"] == "是" else { return nil }
        let allowed = Set(ShellConfigScanner(homeDirectory: homeDirectory).files.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard allowed.contains(standardized) else { return nil }
        return (standardized, line.lineNumber, line.original, line.fingerprint)
    }

    private func validatedGlobalAgent(for item: StartupItem) -> String? {
        guard item.source == .globalLaunchAgent,
              !item.isAppleItem,
              item.runtime.domain == "gui/\(userIdentifier)",
              let path = item.sourcePath,
              URL(fileURLWithPath: path).standardizedFileURL.deletingLastPathComponent().path == "/Library/LaunchAgents",
              let hash = item.controlMetadata["fileSHA256"], hash.count == 64 else { return nil }
        return path
    }

    private func validatedDaemon(for item: StartupItem) -> String? {
        guard item.source == .launchDaemon,
              !item.isAppleItem,
              item.runtime.domain == "system",
              let path = item.sourcePath,
              URL(fileURLWithPath: path).standardizedFileURL.deletingLastPathComponent().path == "/Library/LaunchDaemons",
              let hash = item.controlMetadata["fileSHA256"], hash.count == 64 else { return nil }
        return path
    }

    private func successResult(action: StartupItemControlAction, kind: String) -> StartupItemControlResult {
        let enabled = action == .enableCron || action == .enableShellLine
        return StartupItemControlResult(
            outcome: .success,
            title: enabled ? "已恢复启用" : "已安全停用",
            message: enabled ? "\(kind)已按保留的原文恢复。" : "\(kind)已标记为停用，原文保留，可随时恢复。"
        )
    }

    private func textFailure(_ error: Error) -> StartupItemControlResult {
        StartupItemControlResult(outcome: .failure, title: "安全操作已停止", message: error.localizedDescription)
    }

    private func performHomebrew(
        _ action: StartupItemControlAction,
        on item: StartupItem
    ) -> StartupItemControlResult {
        guard let service = validatedHomebrewService(for: item) else {
            return invalidTargetResult()
        }
        let verb = action == .stopHomebrew ? "stop" : "start"
        let command = runner.run(
            executable: service.executable,
            arguments: ["services", verb, service.name],
            timeout: 15
        )
        guard command.exitCode == 0 else {
            return failureResult(action: action, phase: "Homebrew 服务操作", command: command)
        }
        return StartupItemControlResult(
            outcome: .success,
            title: action == .stopHomebrew ? "服务已停止" : "服务已启动",
            message: action == .stopHomebrew
                ? "Homebrew 已停止该服务并取消登录时自动启动。"
                : "Homebrew 已启动该服务并注册为登录时自动启动。"
        )
    }

    private func validatedLaunchAgentTarget(for item: StartupItem) -> (domain: String, serviceTarget: String)? {
        guard item.source == .userLaunchAgent,
              !item.isAppleItem,
              !item.label.isEmpty,
              !item.label.contains("/"),
              let sourcePath = item.sourcePath,
              let domain = item.runtime.domain,
              domain == "gui/\(userIdentifier)" else { return nil }

        let launchAgentsDirectory = URL(fileURLWithPath: homeDirectory, isDirectory: true)
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .standardizedFileURL.path
        let sourceURL = URL(fileURLWithPath: sourcePath).standardizedFileURL
        guard sourceURL.pathExtension.lowercased() == "plist",
              sourceURL.deletingLastPathComponent().path == launchAgentsDirectory else { return nil }

        return (domain, "\(domain)/\(item.label)")
    }

    private func validatedHomebrewService(for item: StartupItem) -> (executable: String, name: String)? {
        guard item.source == .homebrewService,
              !item.isAppleItem,
              let executable = homebrewExecutable else { return nil }
        let name = item.configuration["服务名"] ?? item.displayName
        guard name.count <= 200,
              name.range(
                of: #"^[A-Za-z0-9][A-Za-z0-9@+._-]*(/[A-Za-z0-9][A-Za-z0-9@+._-]*){0,2}$"#,
                options: .regularExpression
              ) != nil else { return nil }
        return (executable, name)
    }

    private func invalidTargetResult() -> StartupItemControlResult {
        StartupItemControlResult(
            outcome: .failure,
            title: "无法执行操作",
            message: "该项目不满足安全操作条件。请重新扫描后再试。"
        )
    }

    private func failureResult(
        action: StartupItemControlAction,
        phase: String,
        command: CommandResult
    ) -> StartupItemControlResult {
        StartupItemControlResult(
            outcome: .failure,
            title: "\(action.title)失败",
            message: "\(phase)失败：\(commandMessage(command))"
        )
    }

    private func commandMessage(_ result: CommandResult) -> String {
        if result.timedOut { return "命令执行超时" }
        let error = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        if !error.isEmpty { return error }
        let output = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? "退出码 \(result.exitCode)" : output
    }
}
