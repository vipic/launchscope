import Foundation

enum RiskLevel: Int, Codable, Comparable, Sendable {
    case low
    case medium
    case high

    static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    var requiresAttention: Bool { self >= .medium }

    var title: String {
        switch self {
        case .low: "未见异常"
        case .medium: "待核实"
        case .high: "优先核查"
        }
    }

    var systemImage: String {
        switch self {
        case .low: "checkmark.shield"
        case .medium: "exclamationmark.shield"
        case .high: "exclamationmark.triangle.fill"
        }
    }
}

struct RiskAssessment: Equatable, Sendable {
    var level: RiskLevel
    var reasons: [String]
    var hasUnknownEvidence: Bool = false

    var title: String { level == .low && hasUnknownEvidence ? "信息不足" : level.title }
    var systemImage: String { level == .low && hasUnknownEvidence ? "questionmark.circle" : level.systemImage }

    static func assess(_ item: StartupItem, isNew: Bool = false) -> RiskAssessment {
        var level: RiskLevel = .low
        var reasons: [String] = []

        func raise(_ candidate: RiskLevel, _ reason: String) {
            level = max(level, candidate)
            reasons.append(reason)
        }

        if item.targetExists == false {
            raise(.medium, "本次核实未找到执行目标，可能是卸载残留或应用迁移；不代表恶意软件。")
        }

        switch item.signature.kind {
        case .invalid:
            raise(.high, "执行目标的代码签名无效。")
        case .unsigned:
            let privileged = item.source == .launchDaemon || item.source == .globalLaunchAgent
            raise(privileged ? .high : .medium, privileged ? "高权限启动目标未签名。" : "执行目标未签名，发布者身份无法验证。")
        case .adHoc:
            raise(.medium, "执行目标仅使用临时签名，无法确认稳定发布者。")
        case .unavailable:
            reasons.append("当前无法验证执行目标的签名状态；未知不等于签名无效。")
        case .developerID, .appStore:
            reasons.append("代码签名可验证为已识别的第三方发布渠道。")
        case .apple:
            reasons.append("代码签名可验证为 Apple。")
        }

        if !item.isAppleItem {
            switch item.source {
            case .launchDaemon:
                reasons.append("项目在系统级 LaunchDaemon 域中运行，影响所有用户。")
            case .globalLaunchAgent:
                reasons.append("项目由全局 LaunchAgent 配置为用户登录后启动。")
            case .cron:
                reasons.append("Cron 可按计划或重启触发命令，通常不隶属于应用界面。")
            case .shellConfiguration:
                reasons.append("命令来自 Shell 初始化文件，不一定在开机时执行。")
            default:
                break
            }
        }

        if item.runAtLoad == true {
            reasons.append("配置要求加载后立即执行，这是正常的启动条件。")
        }
        if let keepAlive = item.keepAliveDescription, !keepAlive.isEmpty, keepAlive != "false" {
            reasons.append("配置包含 KeepAlive 持续运行条件，本身不表示异常。")
        }
        if isNew && !item.isAppleItem {
            raise(.medium, "这是相较上次扫描新增且尚未建立历史基线的第三方项目。")
        }

        switch item.runtime.state {
        case .running:
            reasons.append("项目当前正在运行；运行状态本身不说明是否异常。")
        case .loaded:
            reasons.append("项目当前已加载但未报告运行进程。")
        case .disabled:
            reasons.append("项目当前已停用；已有核查线索仍保留，供恢复前确认。")
        case .notLoaded:
            reasons.append("项目当前未加载，不代表配置已被移除。")
        case .unknown:
            reasons.append("当前无法确认运行状态，不推断其正在运行或已经停止。")
        }

        if reasons.isEmpty {
            reasons.append(item.isAppleItem ? "系统位置与 Apple 身份判断未发现异常。" : "未发现缺失目标、异常签名或高权限持久化特征。")
        }
        if item.targetExists == nil { reasons.append("执行目标尚未核实；不会将未知状态判为目标缺失。") }
        return RiskAssessment(level: level, reasons: reasons,
                              hasUnknownEvidence: item.targetExists == nil || item.signature.kind == .unavailable)
    }
}
