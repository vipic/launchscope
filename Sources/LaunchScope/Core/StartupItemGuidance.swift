import Foundation

struct StartupItemGuidance: Equatable, Sendable {
    var title: String
    var summary: String
    var diagnosticCommand: String?
    var opensLoginItemSettings: Bool
}

extension StartupItem {
    var guidance: StartupItemGuidance {
        if isAppleItem || source.isAppleSystemLocation {
            return StartupItemGuidance(
                title: "仅建议查看",
                summary: "这是 Apple 系统位置中的项目。LaunchScope 不提供停用或移除入口，以免影响系统功能。",
                diagnosticCommand: launchctlPrintCommand,
                opensLoginItemSettings: false
            )
        }

        switch source {
        case .userLaunchAgent:
            return StartupItemGuidance(
                title: isEnabled == false ? "可恢复启用" : "可安全停用",
                summary: "LaunchScope 只修改当前用户的 launchd 允许状态并加载或卸载任务，不删除或改写 plist；操作后会重新扫描验证。",
                diagnosticCommand: launchctlPrintCommand,
                opensLoginItemSettings: false
            )
        case .globalLaunchAgent, .launchDaemon:
            return StartupItemGuidance(
                title: "需要管理员权限",
                summary: "该项目作用于系统或所有用户。建议优先使用所属应用的卸载器，不要直接删除 plist。",
                diagnosticCommand: launchctlPrintCommand,
                opensLoginItemSettings: false
            )
        case .backgroundTask, .loginItem:
            return StartupItemGuidance(
                title: "在系统设置中管理",
                summary: "macOS 负责该项目的允许状态。请在“登录项与扩展”中关闭后台活动或移除登录项。",
                diagnosticCommand: nil,
                opensLoginItemSettings: true
            )
        case .homebrewService:
            let serviceName = configuration["服务名"] ?? displayName
            return StartupItemGuidance(
                title: "使用 Homebrew 管理",
                summary: "建议通过 brew services 停止或启动，避免手工修改 Homebrew 生成的启动配置。",
                diagnosticCommand: "brew services info \(Self.shellQuote(serviceName))",
                opensLoginItemSettings: false
            )
        case .cron:
            return StartupItemGuidance(
                title: "先备份完整 crontab",
                summary: "Cron 项目共享同一份用户 crontab。修改前应整体备份，并按原始行精确处理。",
                diagnosticCommand: "/usr/bin/crontab -l",
                opensLoginItemSettings: false
            )
        case .shellConfiguration:
            return StartupItemGuidance(
                title: "谨慎编辑 Shell 配置",
                summary: "建议先备份文件，再注释对应命令并打开新终端验证；不要直接删除整份配置。",
                diagnosticCommand: sourcePath.map { "/usr/bin/sed -n '1,160p' \(Self.shellQuote($0))" },
                opensLoginItemSettings: false
            )
        case .systemLaunchAgent, .systemLaunchDaemon:
            // Apple 系统位置已在上方统一处理。
            return StartupItemGuidance(
                title: "仅建议查看",
                summary: "系统启动项目不应由 LaunchScope 修改。",
                diagnosticCommand: launchctlPrintCommand,
                opensLoginItemSettings: false
            )
        }
    }

    var revealableSourcePath: String? {
        guard let sourcePath, sourcePath.hasPrefix("/") else { return nil }
        return sourcePath
    }

    private var launchctlPrintCommand: String? {
        guard let domain = runtime.domain else { return nil }
        return "/bin/launchctl print \(Self.shellQuote("\(domain)/\(label)"))"
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
