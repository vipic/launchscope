import Foundation

@MainActor
final class DashboardStore: ObservableObject {
    private let historyPersistence: any ControlHistoryPersisting
    private let snapshotPersistence: any ScanSnapshotPersisting
    private let annotationPersistence: any ItemAnnotationPersisting
    private let notificationLedgerPersistence: any NotificationLedgerPersisting
    private let notifier: any NewItemNotifying
    private var previousSnapshot: ScanSnapshot?
    private var notificationLedger = NotificationLedger()
    private var newSnapshotKeys: Set<String> = []
    private var searchableTextByID: [String: String] = [:]
    private var riskAssessmentByID: [String: RiskAssessment] = [:]
    @Published private(set) var items: [StartupItem] = []
    @Published private(set) var issues: [ScanIssue] = []
    @Published private(set) var findings: [StartupFinding] = []
    @Published private(set) var isScanning = false
    @Published private(set) var scannedAt: Date?
    @Published private(set) var scanDuration: TimeInterval?
    @Published private(set) var backgroundTasksUpdatedAt: Date?
    @Published private(set) var isRefreshingBackgroundTasks = false
    @Published private(set) var controllingItemID: String?
    @Published var controlResult: StartupItemControlResult?
    @Published private(set) var controlHistory: [ControlHistoryEntry] = []
    @Published private(set) var historyPersistenceError: String?
    @Published private(set) var scanChanges: [ScanChange] = []
    @Published private(set) var snapshotHistory: [ScanSnapshot] = []
    @Published private(set) var comparisonScannedAt: Date?
    @Published private(set) var snapshotPersistenceError: String?
    @Published private(set) var annotations: [String: ItemAnnotation] = [:]
    @Published private(set) var annotationPersistenceError: String?
    @Published private(set) var notificationsEnabled: Bool
    @Published private(set) var notificationError: String?
    @Published private(set) var resourceObservations: [Int32: ResourceObservation] = [:]
    @Published private(set) var resourcesObservedAt: Date?
    @Published private(set) var isObservingResources = false
    @Published var selectedItemID: String?
    @Published var selectedFilter: DashboardFilter = .thirdParty
    @Published var searchText = ""

    init(
        historyPersistence: any ControlHistoryPersisting = ControlHistoryPersistence(),
        snapshotPersistence: any ScanSnapshotPersisting = ScanSnapshotPersistence(),
        annotationPersistence: any ItemAnnotationPersisting = ItemAnnotationPersistence(),
        notificationLedgerPersistence: any NotificationLedgerPersisting = NotificationLedgerPersistence(),
        notifier: (any NewItemNotifying)? = nil
    ) {
        self.historyPersistence = historyPersistence
        self.snapshotPersistence = snapshotPersistence
        self.annotationPersistence = annotationPersistence
        self.notificationLedgerPersistence = notificationLedgerPersistence
        self.notifier = notifier ?? NewItemNotificationService()
        notificationsEnabled = UserDefaults.standard.bool(forKey: PreferenceKeys.notifyNewUntrustedItems)
        do {
            controlHistory = Array(try historyPersistence.load().prefix(100))
        } catch {
            historyPersistenceError = "无法读取操作历史：\(error.localizedDescription)"
        }
        do {
            snapshotHistory = try snapshotPersistence.loadHistory()
            previousSnapshot = snapshotHistory.last
        } catch {
            snapshotPersistenceError = "无法读取上次扫描快照：\(error.localizedDescription)"
        }
        do {
            for annotation in try annotationPersistence.load() {
                annotations[annotation.itemKey] = annotation
            }
        } catch {
            annotationPersistenceError = "无法读取备注与信任名单：\(error.localizedDescription)"
        }
        do {
            notificationLedger = try notificationLedgerPersistence.load()
        } catch {
            notificationError = "无法读取提醒去重记录：\(error.localizedDescription)"
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

    func observeResources() {
        guard !isObservingResources else { return }
        let pids = Set(items.compactMap(\.runtime.processIdentifier))
        guard !pids.isEmpty else {
            resourceObservations = [:]
            resourcesObservedAt = Date()
            return
        }
        isObservingResources = true
        Task {
            let observations = await Task.detached(priority: .utility) {
                ResourceObserver().observe(processIdentifiers: pids)
            }.value
            resourceObservations = observations
            resourcesObservedAt = Date()
            isObservingResources = false
        }
    }

    func resourceObservation(for item: StartupItem) -> ResourceObservation? {
        item.runtime.processIdentifier.flatMap { resourceObservations[$0] }
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
        updateSnapshot(with: report)
        items = report.items
        issues = report.issues
        findings = StartupConflictDetector.detect(report.items)
        newSnapshotKeys = Set(scanChanges.compactMap { change in
            change.kind == .added ? change.after?.key : nil
        })
        searchableTextByID = Dictionary(uniqueKeysWithValues: report.items.map { ($0.id, $0.searchableText) })
        riskAssessmentByID = Dictionary(uniqueKeysWithValues: report.items.map { item in
            let isNew = newSnapshotKeys.contains(ScanSnapshotItem(item: item).key)
            return (item.id, RiskAssessment.assess(item, isNew: isNew))
        })
        scannedAt = report.scannedAt
        scanDuration = report.duration
        backgroundTasksUpdatedAt = report.backgroundTasksUpdatedAt
        isScanning = false
        isRefreshingBackgroundTasks = false
        scheduleNewItemNotificationIfNeeded()

        let visibleIDs = Set(filteredItems(hideAppleItems: false, hideTrustedItems: false).map(\.id))
        if let selectedItemID, !visibleIDs.contains(selectedItemID) {
            self.selectedItemID = nil
        }
        if self.selectedItemID == nil {
            self.selectedItemID = filteredItems(hideAppleItems: false, hideTrustedItems: false).first?.id
        }
    }

    private func updateSnapshot(with report: ScanReport) {
        let current = ScanSnapshot(report: report)
        if let previousSnapshot {
            scanChanges = ScanSnapshotDiff.compare(previous: previousSnapshot, current: current)
            comparisonScannedAt = previousSnapshot.scannedAt
        } else {
            scanChanges = []
            comparisonScannedAt = nil
        }
        previousSnapshot = current
        snapshotHistory.append(current)
        snapshotHistory = Array(snapshotHistory.sorted { $0.scannedAt < $1.scannedAt }.suffix(30))

        do {
            try snapshotPersistence.saveHistory(snapshotHistory)
            snapshotPersistenceError = nil
        } catch {
            snapshotPersistenceError = "无法保存扫描快照：\(error.localizedDescription)"
        }
    }

    func filteredItems(hideAppleItems: Bool, hideTrustedItems: Bool) -> [StartupItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return items.filter { item in
            if hideAppleItems, item.isAppleItem { return false }
            if hideTrustedItems, isTrusted(item) { return false }
            let filterMatches: Bool
            switch selectedFilter {
            case .all: filterMatches = true
            case .thirdParty: filterMatches = !item.isAppleItem
            case .apple: filterMatches = item.isAppleItem
            case .running: filterMatches = item.runtime.state == .running
            case .missingTarget: filterMatches = item.targetExists == false
            case .disabled: filterMatches = item.isEnabled == false || item.runtime.state == .disabled
            case .untrusted: filterMatches = !item.isAppleItem && !isTrusted(item)
            case .highRisk: filterMatches = riskAssessment(for: item).level.requiresAttention
            case .findings: filterMatches = false
            case .issues: filterMatches = false
            case .source(let source): filterMatches = item.source == source
            }
            return filterMatches && (query.isEmpty || searchableTextByID[item.id, default: item.searchableText].contains(query))
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
        case .untrusted: items.count { !$0.isAppleItem && !isTrusted($0) }
        case .highRisk: items.count { riskAssessment(for: $0).level.requiresAttention }
        case .findings: findings.count
        case .issues: issues.count
        case .source(let source): items.count { $0.source == source }
        }
    }

    var selectedItem: StartupItem? {
        guard let selectedItemID else { return nil }
        return items.first { $0.id == selectedItemID }
    }

    var recoveryCandidates: [RecoveryCandidate] {
        items.compactMap { item in
            guard let action = availableControlAction(for: item), action.isRecoveryAction else { return nil }
            return RecoveryCandidate(item: item, action: action)
        }
    }

    var recoverableHistory: [ControlHistoryEntry] {
        controlHistory.filter(canUndo)
    }

    func annotation(for item: StartupItem) -> ItemAnnotation? { annotations[item.privacySafeKey] }

    func isTrusted(_ item: StartupItem) -> Bool { annotation(for: item)?.isTrusted == true }

    func selectAcceptanceItem(source: StartupSource, label: String) {
        selectedFilter = .thirdParty
        searchText = ""
        selectedItemID = items.first { $0.source == source && $0.label == label }?.id
    }

    func isNew(_ item: StartupItem) -> Bool {
        let key = ScanSnapshotItem(item: item).key
        return newSnapshotKeys.contains(key)
    }

    func riskAssessment(for item: StartupItem) -> RiskAssessment {
        riskAssessmentByID[item.id] ?? RiskAssessment.assess(item, isNew: isNew(item))
    }

    var auditTimeline: [AuditTimelineEvent] {
        AuditTimeline.build(snapshots: snapshotHistory, controlHistory: controlHistory)
    }

    func saveAnnotation(for item: StartupItem, note: String, tags: [String], isTrusted: Bool) {
        let cleanNote = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2_000))
        let cleanTags = Array(Set(tags.map {
            String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        }.filter { !$0.isEmpty })).sorted().prefix(20)
        let key = item.privacySafeKey
        if cleanNote.isEmpty && cleanTags.isEmpty && !isTrusted {
            annotations.removeValue(forKey: key)
        } else {
            annotations[key] = ItemAnnotation(
                itemKey: key, note: cleanNote, tags: Array(cleanTags), isTrusted: isTrusted, updatedAt: Date()
            )
        }
        do {
            try annotationPersistence.save(annotations.values.sorted { $0.itemKey < $1.itemKey })
            annotationPersistenceError = nil
        } catch {
            annotationPersistenceError = "无法保存备注与信任名单：\(error.localizedDescription)"
        }
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        if !enabled {
            notificationsEnabled = false
            UserDefaults.standard.set(false, forKey: PreferenceKeys.notifyNewUntrustedItems)
            return
        }
        Task {
            do {
                let granted = try await notifier.requestAuthorization()
                notificationsEnabled = granted
                UserDefaults.standard.set(granted, forKey: PreferenceKeys.notifyNewUntrustedItems)
                notificationError = granted ? nil : "系统未授予通知权限，新增项目提醒未开启。"
            } catch {
                notificationsEnabled = false
                notificationError = "无法开启通知：\(error.localizedDescription)"
            }
        }
    }

    func dismissNotificationError() {
        notificationError = nil
    }

    private func scheduleNewItemNotificationIfNeeded() {
        guard notificationsEnabled else { return }
        let eligible = scanChanges.compactMap { change -> (String, ScanSnapshotItem)? in
            guard change.kind == .added, let item = change.after, !item.isAppleItem else { return nil }
            let trusted = items.first { ScanSnapshotItem(item: $0).key == item.key }.map(isTrusted) ?? false
            return trusted ? nil : (change.id, item)
        }
        let activeIDs = Set(eligible.map(\.0))
        let newItems = eligible.filter { !notificationLedger.activeChangeIDs.contains($0.0) }.map(\.1)
        Task {
            do {
                if !newItems.isEmpty { try await notifier.notify(newItems: newItems) }
                notificationLedger.activeChangeIDs = activeIDs
                try notificationLedgerPersistence.save(notificationLedger)
                notificationError = nil
            } catch {
                notificationError = "新增项目提醒失败：\(error.localizedDescription)"
            }
        }
    }
}
