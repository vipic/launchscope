import Foundation

struct StartupItemGroup: Identifiable {
    var name: String
    var items: [StartupItem]
    var id: String { name }
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
        Dictionary(grouping: items, by: \.groupName)
            .map { StartupItemGroup(name: $0.key, items: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func matchesSearch(query: String, searchableText: String) -> Bool {
        query.isEmpty || searchableText.contains(query)
    }
}
