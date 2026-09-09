import Foundation

struct BackgroundTaskSnapshot: Codable, Sendable {
    var items: [StartupItem]
    var updatedAt: Date
}

struct BackgroundTaskCache: Sendable {
    var url: URL

    init(url: URL = Self.defaultURL) {
        self.url = url
    }

    func load() throws -> BackgroundTaskSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var snapshot = try decoder.decode(BackgroundTaskSnapshot.self, from: data)
        // 缓存保存的是历史注册信息；每次加载都按当前解析规则核实路径，
        // 不沿用旧版存下的“目标缺失”，也不改变注册记录的更新时间。
        let reparsed = BackgroundTaskScanner.parseRecords(snapshot.items.map(\.configuration))
        let byID = Dictionary(reparsed.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        snapshot.items = snapshot.items.map { original in
            if let normalized = byID[original.id] { return normalized }
            var item = original
            item.targetExists = PathAccessPolicy.targetExistsWithoutPrompt(at: item.executablePath)
            return item
        }
        return snapshot
    }

    @discardableResult
    func save(items: [StartupItem], updatedAt: Date = Date()) throws -> BackgroundTaskSnapshot {
        let snapshot = BackgroundTaskSnapshot(items: items, updatedAt: updatedAt)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return snapshot
    }

    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("LaunchScope", isDirectory: true)
            .appendingPathComponent("background-tasks.json")
    }
}

struct BackgroundTaskProvider: Sendable {
    var scanner: BackgroundTaskScanner = BackgroundTaskScanner()
    var cache: BackgroundTaskCache = BackgroundTaskCache()

    func items(refresh: Bool) -> (items: [StartupItem], issues: [ScanIssue], updatedAt: Date?) {
        if refresh {
            let result = scanner.scan()
            if result.issues.isEmpty {
                do {
                    let snapshot = try cache.save(items: result.items)
                    return (snapshot.items, [], snapshot.updatedAt)
                } catch {
                    return (result.items, [ScanIssue(
                        source: "后台任务缓存",
                        message: "扫描成功，但无法保存缓存：\(error.localizedDescription)",
                        severity: .warning
                    )], Date())
                }
            }
            do {
                let cached = try cache.load()
                return (cached?.items ?? [], result.issues, cached?.updatedAt)
            } catch {
                return ([], result.issues + [ScanIssue(source: "后台任务缓存", message: "更新失败且无法读取历史缓存：\(error.localizedDescription)", severity: .warning)], nil)
            }
        }

        do {
            let snapshot = try cache.load()
            return (snapshot?.items ?? [], [], snapshot?.updatedAt)
        } catch {
            return ([], [ScanIssue(
                source: "后台任务缓存",
                message: "无法读取上次结果：\(error.localizedDescription)",
                severity: .warning
            )], nil)
        }
    }
}
