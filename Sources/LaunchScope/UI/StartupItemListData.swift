import Foundation

struct StartupItemGroup: Identifiable {
    var id: String
    var name: String
    var items: [StartupItem]
    var enabledCount: Int { items.count { $0.isEnabled != false && $0.runtime.state != .disabled } }
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
