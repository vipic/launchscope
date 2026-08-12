import Foundation

@MainActor
final class DashboardStore: ObservableObject {
    @Published private(set) var items: [StartupItem] = []
    @Published private(set) var issues: [ScanIssue] = []
    @Published private(set) var isScanning = false
    @Published private(set) var scannedAt: Date?
    @Published private(set) var scanDuration: TimeInterval?
    @Published private(set) var backgroundTasksUpdatedAt: Date?
    @Published private(set) var isRefreshingBackgroundTasks = false
    @Published var selectedItemID: String?
    @Published var selectedFilter: DashboardFilter = .thirdParty
    @Published var searchText = ""

    /// SwiftUI may restart a view task when a window or scene becomes active again.
    /// Automatic discovery must run only once per application process because
    /// `sfltool dumpbtm` can display a system authorization prompt.
    func refreshIfNeeded() {
        guard scannedAt == nil else { return }
        refresh()
    }

    func refresh() {
        performScan(refreshBackgroundTasks: false)
    }

    func refreshBackgroundTasks() {
        performScan(refreshBackgroundTasks: true)
    }

    private func performScan(refreshBackgroundTasks: Bool) {
        guard !isScanning else { return }
        isScanning = true
        isRefreshingBackgroundTasks = refreshBackgroundTasks
        Task {
            let report = await Task.detached(priority: .userInitiated) {
                StartupScanner().scan(refreshBackgroundTasks: refreshBackgroundTasks)
            }.value
            items = report.items
            issues = report.issues
            scannedAt = report.scannedAt
            scanDuration = report.duration
            backgroundTasksUpdatedAt = report.backgroundTasksUpdatedAt
            isScanning = false
            isRefreshingBackgroundTasks = false

            let visibleIDs = Set(filteredItems(hideAppleItems: false).map(\.id))
            if let selectedItemID, !visibleIDs.contains(selectedItemID) {
                self.selectedItemID = nil
            }
            if self.selectedItemID == nil {
                self.selectedItemID = filteredItems(hideAppleItems: false).first?.id
            }
        }
    }

    func filteredItems(hideAppleItems: Bool) -> [StartupItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return items.filter { item in
            if hideAppleItems, item.isAppleItem { return false }
            let filterMatches: Bool
            switch selectedFilter {
            case .all: filterMatches = true
            case .thirdParty: filterMatches = !item.isAppleItem
            case .apple: filterMatches = item.isAppleItem
            case .running: filterMatches = item.runtime.state == .running
            case .missingTarget: filterMatches = item.targetExists == false
            case .disabled: filterMatches = item.isEnabled == false || item.runtime.state == .disabled
            case .issues: filterMatches = false
            case .source(let source): filterMatches = item.source == source
            }
            return filterMatches && (query.isEmpty || item.searchableText.contains(query))
        }
    }

    func count(for filter: DashboardFilter) -> Int {
        switch filter {
        case .all: items.count
        case .thirdParty: items.count { !$0.isAppleItem }
        case .apple: items.count { $0.isAppleItem }
        case .running: items.count { $0.runtime.state == .running }
        case .missingTarget: items.count { $0.targetExists == false }
        case .disabled: items.count { $0.isEnabled == false || $0.runtime.state == .disabled }
        case .issues: issues.count
        case .source(let source): items.count { $0.source == source }
        }
    }

    var selectedItem: StartupItem? {
        guard let selectedItemID else { return nil }
        return items.first { $0.id == selectedItemID }
    }
}
