import Foundation

@MainActor
final class DashboardStore: ObservableObject {
    private let historyPersistence: any ControlHistoryPersisting
    @Published private(set) var items: [StartupItem] = []
    @Published private(set) var issues: [ScanIssue] = []
    @Published private(set) var isScanning = false
    @Published private(set) var scannedAt: Date?
    @Published private(set) var scanDuration: TimeInterval?
    @Published private(set) var backgroundTasksUpdatedAt: Date?
    @Published private(set) var isRefreshingBackgroundTasks = false
    @Published private(set) var controllingItemID: String?
    @Published var controlResult: StartupItemControlResult?
    @Published private(set) var controlHistory: [ControlHistoryEntry] = []
    @Published private(set) var historyPersistenceError: String?
    @Published var selectedItemID: String?
    @Published var selectedFilter: DashboardFilter = .thirdParty
    @Published var searchText = ""

    init(historyPersistence: any ControlHistoryPersisting = ControlHistoryPersistence()) {
        self.historyPersistence = historyPersistence
        do {
            controlHistory = Array(try historyPersistence.load().prefix(100))
        } catch {
            historyPersistenceError = "无法读取操作历史：\(error.localizedDescription)"
        }
    }

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
            apply(report)
        }
    }

    func availableControlAction(for item: StartupItem) -> StartupItemControlAction? {
        StartupItemController().availableAction(for: item)
    }

    func performControl(
        _ action: StartupItemControlAction,
        on item: StartupItem,
        reversesEntryID: UUID? = nil
    ) {
        guard controllingItemID == nil,
              availableControlAction(for: item) == action else { return }

        controllingItemID = item.id
        isScanning = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                StartupItemController().perform(action, on: item)
            }.value
            let report = await Task.detached(priority: .userInitiated) {
                StartupScanner().scan(refreshBackgroundTasks: false)
            }.value
            let afterItem = report.items.first { $0.id == item.id }
            apply(report)
            controllingItemID = nil
            controlResult = recordControl(
                action: action,
                item: item,
                afterItem: afterItem,
                result: result,
                reversesEntryID: reversesEntryID
            )
        }
    }

    func canUndo(_ entry: ControlHistoryEntry) -> Bool {
        guard controllingItemID == nil,
              let item = items.first(where: { $0.controlHistoryKey == entry.itemID }) else { return false }
        return ControlHistoryPolicy.canUndo(
            entry,
            in: controlHistory,
            currentAction: availableControlAction(for: item)
        )
    }

    func undo(_ entry: ControlHistoryEntry) {
        guard canUndo(entry),
              let action = entry.inverseAction,
              let item = items.first(where: { $0.controlHistoryKey == entry.itemID }) else {
            controlResult = StartupItemControlResult(
                outcome: .failure,
                title: "无法撤销",
                message: "项目状态已变化或项目已不存在，请重新扫描后检查。"
            )
            return
        }
        performControl(action, on: item, reversesEntryID: entry.id)
    }

    private func recordControl(
        action: StartupItemControlAction,
        item: StartupItem,
        afterItem: StartupItem?,
        result: StartupItemControlResult,
        reversesEntryID: UUID?
    ) -> StartupItemControlResult {
        var displayedResult = result
        let entry = ControlHistoryEntry(
            item: item,
            afterItem: afterItem,
            action: action,
            result: result,
            reversesEntryID: reversesEntryID
        )

        if result.outcome != .failure, let reversesEntryID,
           let index = controlHistory.firstIndex(where: { $0.id == reversesEntryID }) {
            controlHistory[index].reversedAt = entry.timestamp
            controlHistory[index].reversedByEntryID = entry.id
        }
        controlHistory.insert(entry, at: 0)
        if controlHistory.count > 100 {
            controlHistory.removeLast(controlHistory.count - 100)
        }

        do {
            try historyPersistence.save(controlHistory)
            historyPersistenceError = nil
        } catch {
            historyPersistenceError = "无法保存操作历史：\(error.localizedDescription)"
            displayedResult.message += "\n\n操作已执行，但历史记录保存失败。"
        }
        return displayedResult
    }

    private func apply(_ report: ScanReport) {
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
