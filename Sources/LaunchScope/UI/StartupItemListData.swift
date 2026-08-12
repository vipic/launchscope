import Foundation

struct StartupItemGroup: Identifiable {
    var name: String
    var items: [StartupItem]
    var id: String { name }
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
