import Foundation

enum DashboardFilter: Hashable, Identifiable {
    case all
    case thirdParty
    case apple
    case running
    case missingTarget
    case disabled
    case untrusted
    case highRisk
    case findings
    case issues
    case source(StartupSource)

    var id: String {
        switch self {
        case .all: "all"
        case .thirdParty: "thirdParty"
        case .apple: "apple"
        case .running: "running"
        case .missingTarget: "missingTarget"
        case .disabled: "disabled"
        case .untrusted: "untrusted"
        case .highRisk: "highRisk"
        case .findings: "findings"
        case .issues: "issues"
        case .source(let source): "source.\(source.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .all: "全部项目"
        case .thirdParty: "自启动项目"
        case .apple: "Apple 系统项"
        case .running: "正在运行"
        case .missingTarget: "目标已缺失"
        case .disabled: "已停用"
        case .untrusted: "尚未确认"
        case .highRisk: "待核查项目"
        case .findings: "发现与关联"
        case .issues: "扫描问题"
        case .source(let source): source.title
        }
    }

    var systemImage: String {
        switch self {
        case .all: "square.stack.3d.up"
        case .thirdParty: "person.crop.square"
        case .apple: "apple.logo"
        case .running: "play.circle"
        case .missingTarget: "exclamationmark.triangle"
        case .disabled: "pause.circle"
        case .untrusted: "shield.lefthalf.filled"
        case .highRisk: "exclamationmark.triangle.fill"
        case .findings: "arrow.triangle.branch"
        case .issues: "bell.badge"
        case .source(let source): source.systemImage
        }
    }
}
