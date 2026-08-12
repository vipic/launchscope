import Foundation

enum RiskLevel: Int, Codable, Comparable, Sendable {
    case low
    case medium
    case high

    static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    var requiresAttention: Bool { self >= .medium }

    var title: String {
        switch self {
        case .low: "低风险"
        case .medium: "需关注"
        case .high: "高风险"
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

    static func assess(_ item: StartupItem, isNew: Bool = false) -> RiskAssessment {
        var level: RiskLevel = .low
        var reasons: [String] = []

        func raise(_ candidate: RiskLevel, _ reason: String) {
            level = max(level, candidate)
            reasons.append(reason)
        }

        if item.targetExists == false {
            raise(.high, "配置仍存在，但执行目标已经缺失，可能是卸载后的残留。")
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
            raise(.medium, "当前无法验证执行目标的签名状态。")
        case .developerID, .appStore:
            reasons.append("代码签名可验证为已识别的第三方发布渠道。")
        case .apple:
            reasons.append("代码签名可验证为 Apple。")
        }

        if !item.isAppleItem {
            switch item.source {
            case .launchDaemon:
                raise(.medium, "项目在系统级 LaunchDaemon 域中运行，影响所有用户。")
            case .globalLaunchAgent:
                raise(.medium, "项目由全局 LaunchAgent 配置为用户登录后启动。")
            case .cron:
                raise(.medium, "Cron 可按计划或重启触发命令，通常不隶属于应用界面。")
            case .shellConfiguration:
                raise(.medium, "命令来自 Shell 初始化文件，会随交互式终端环境加载。")
            default:
                break
            }
        }

        if item.runAtLoad == true {
            raise(.medium, "配置要求加载后立即执行。")
        }
        if let keepAlive = item.keepAliveDescription, !keepAlive.isEmpty, keepAlive != "false" {
            raise(.medium, "配置包含 KeepAlive 持续运行条件。")
        }
        if isNew && !item.isAppleItem {
            raise(.medium, "这是相较上次扫描新增且尚未建立历史基线的第三方项目。")
        }

        if reasons.isEmpty {
            reasons.append(item.isAppleItem ? "系统位置与 Apple 身份判断未发现异常。" : "未发现缺失目标、异常签名或高权限持久化特征。")
        }
        return RiskAssessment(level: level, reasons: reasons)
    }
}
