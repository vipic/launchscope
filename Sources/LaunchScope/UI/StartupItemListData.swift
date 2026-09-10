import Foundation

struct StartupItemGroup: Identifiable {
    var id: String
    var name: String
    var items: [StartupItem]
    var enabledCount: Int {
        items.count {
            $0.isEnabled == true || $0.runtime.state == .running || $0.runtime.state == .loaded
        }
    }
    var runningCount: Int { items.count { $0.runtime.state == .running } }
    var disabledCount: Int { items.count { $0.isEnabled == false || $0.runtime.state == .disabled } }
    var isRunning: Bool { runningCount > 0 }
    var isFullyDisabled: Bool { !items.isEmpty && disabledCount == items.count }
    var statusSummary: String {
        switch (runningCount, disabledCount) {
        case let (running, disabled) where running > 0 && disabled > 0:
            return "\(running) 条组件正在运行 · \(disabled) 条已停用"
        case let (running, _) where running > 0:
            return "\(running) 条组件正在运行"
        case let (_, disabled) where disabled > 0 && enabledCount > 0:
            return "\(enabledCount) 条组件已启用 · \(disabled) 条已停用"
        case let (_, disabled) where disabled > 0:
            return "\(disabled) 条组件已停用"
        default:
            if items.contains(where: { $0.runtime.state == .loaded }) {
                return "组件已加载，按需运行"
            }
            if items.contains(where: { $0.isEnabled == true }) {
                return "组件已启用，按需运行"
            }
            return "组件状态未知"
        }
    }
    var statusSystemImage: String {
        if runningCount > 0 { return "play.circle.fill" }
        if disabledCount > 0 { return "pause.circle" }
        if items.contains(where: { $0.runtime.state == .loaded || $0.isEnabled == true }) {
            return "checkmark.circle"
        }
        return "questionmark.circle"
    }
    var roleSummary: String {
        let roles = items.map(\.componentRole)
        var counts: [String: Int] = [:]
        roles.forEach { counts[$0, default: 0] += 1 }
        return counts
            .sorted { $0.value == $1.value ? $0.key.localizedStandardCompare($1.key) == .orderedAscending : $0.value > $1.value }
            .map { $0.value > 1 ? "\($0.key) ×\($0.value)" : $0.key }
            .joined(separator: "、")
    }
}

enum StartupItemListData {
    static func groups(for items: [StartupItem]) -> [StartupItemGroup] {
        Dictionary(grouping: items, by: \.groupIdentifier)
            .map { key, items in
                let ordered = items.sorted { sourcePriority($0.source) < sourcePriority($1.source) }
                return StartupItemGroup(id: key, name: ordered.first?.groupName ?? key, items: ordered)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func matchesSearch(query: String, searchableText: String) -> Bool {
        query.isEmpty || searchableText.contains(query)
    }

    static func statusGroups(for items: [StartupItem], filter: DashboardFilter) -> [StartupItemGroup] {
        let groups = groups(for: items)
        switch filter {
        case .running:
            return groups.filter(\.isRunning)
        case .disabled:
            return groups.filter(\.isFullyDisabled)
        default:
            return groups
        }
    }

    private static func sourcePriority(_ source: StartupSource) -> Int {
        switch source {
        case .homebrewService: 0
        case .userLaunchAgent: 1
        case .backgroundTask, .loginItem: 2
        case .globalLaunchAgent, .launchDaemon: 3
        case .cron, .shellConfiguration: 4
        case .systemLaunchAgent, .systemLaunchDaemon: 5
        }
    }
}
