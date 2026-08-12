import Foundation

struct StartupScanner: Sendable {
    var backgroundTaskProvider = BackgroundTaskProvider()

    func scan(refreshBackgroundTasks: Bool = false) -> ScanReport {
        let startedAt = Date()
        var items: [StartupItem] = []
        var issues: [ScanIssue] = []

        let launchd = LaunchdScanner().scan()
        items += launchd.items
        issues += launchd.issues

        // `sfltool dumpbtm` requests administrator authorization on every process
        // invocation. Normal scans use the last successful snapshot; only an
        // explicit user action requests a live refresh.
        let background = backgroundTaskProvider.items(refresh: refreshBackgroundTasks)
        items += background.items
        issues += background.issues

        let homebrew = HomebrewScanner().scan()
        items += homebrew.items
        issues += homebrew.issues

        let cron = CronScanner().scan()
        items += cron.items
        issues += cron.issues

        let shell = ShellConfigScanner().scan()
        items += shell.items
        issues += shell.issues

        let signatureInspector = CodeSignatureInspector()
        let runtimeInspector = RuntimeInspector()
        let attributionResolver = AttributionResolver()
        let runtimeSnapshot = runtimeInspector.snapshot(
            domains: Set(items.compactMap { $0.runtime.domain })
        )
        let disabledSnapshot = runtimeInspector.disabledServices(
            domains: Set(items.compactMap { $0.runtime.domain })
        )

        items = items.map { original in
            var item = original
            item.signature = signatureInspector.inspect(path: item.executablePath)
            if let domain = item.runtime.domain,
               let disabled = disabledSnapshot[domain]?[item.label] {
                item.isEnabled = !disabled
            }
            if let domain = item.runtime.domain,
               let runtime = runtimeSnapshot[domain]?[item.label] {
                item.runtime = runtime
            } else if item.runtime.domain != nil {
                item.runtime.state = item.isEnabled == false ? .disabled : .notLoaded
            }
            item.attribution = attributionResolver.resolve(item: item)
            if item.signature.kind == .apple { item.isAppleItem = true }
            return item
        }

        let uniqueItems = Dictionary(grouping: items, by: \.id).compactMap { $0.value.first }
            .sorted {
                let lhsSystem = $0.isAppleItem ? 1 : 0
                let rhsSystem = $1.isAppleItem ? 1 : 0
                if lhsSystem != rhsSystem { return lhsSystem < rhsSystem }
                let groupOrder = $0.groupName.localizedStandardCompare($1.groupName)
                if groupOrder != .orderedSame { return groupOrder == .orderedAscending }
                return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }

        return ScanReport(
            items: uniqueItems,
            issues: issues,
            scannedAt: Date(),
            duration: Date().timeIntervalSince(startedAt),
            backgroundTasksUpdatedAt: background.updatedAt
        )
    }
}
