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

        // Homebrew 的状态记录适合控制服务，launchd plist 则包含完整命令、
        // 环境变量和启动条件。合并两者，避免用户在重复条目间来回切换。
        let launchdByLabel = Dictionary(grouping: launchd.items, by: \.label)
            .compactMapValues { matches in
                matches.first { $0.source == .userLaunchAgent } ?? matches.first
            }
        items = items.map { original in
            guard original.source == .homebrewService,
                  let launchdItem = launchdByLabel[original.label] else { return original }
            var item = original
            item.executablePath = launchdItem.executablePath
            item.arguments = launchdItem.arguments
            item.workingDirectory = launchdItem.workingDirectory
            item.runAtLoad = launchdItem.runAtLoad
            item.keepAliveDescription = launchdItem.keepAliveDescription
            item.scheduleDescription = launchdItem.scheduleDescription
            item.environment = launchdItem.environment
            item.sourceCreatedAt = launchdItem.sourceCreatedAt
            item.sourceModifiedAt = launchdItem.sourceModifiedAt
            item.targetExists = launchdItem.targetExists
            return item
        }

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
