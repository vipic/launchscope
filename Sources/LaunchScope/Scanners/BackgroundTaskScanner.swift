import Foundation

struct BackgroundTaskScanner: Sendable {
    var runner: any CommandRunning = CommandRunner()

    func scan() -> (items: [StartupItem], issues: [ScanIssue]) {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/sfltool") else {
            return ([], [ScanIssue(source: "后台任务管理", message: "系统未提供可执行的 sfltool，无法读取后台项目", severity: .warning)])
        }
        // sfltool 在直接作为 Process 子进程启动时，部分 macOS 26 机器会等待后台代理。
        // 使用不加载任何用户启动文件的 zsh 保留稳定性，同时避免执行 .zprofile/.zshrc。
        let result = runner.run(
            executable: "/bin/zsh",
            arguments: ["-f", "-c", "/usr/bin/sfltool dumpbtm"],
            timeout: 8
        )
        if result.timedOut {
            return ([], [ScanIssue(
                source: "后台任务管理",
                message: "sfltool 在 8 秒内没有返回；已跳过现代后台任务，其他来源不受影响",
                severity: .warning
            )])
        }
        guard result.exitCode == 0 else {
            let error = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            return ([], [ScanIssue(source: "后台任务管理", message: error.isEmpty ? "sfltool 执行失败" : error, severity: .warning)])
        }
        return (Self.parse(result.standardOutput), [])
    }

    static func parse(_ text: String) -> [StartupItem] {
        var records: [[String: String]] = []
        var current: [String: String] = [:]

        func finishRecord() {
            if !current.isEmpty { records.append(current) }
            current = [:]
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                finishRecord()
                continue
            }
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            if key.hasPrefix("#"), !current.isEmpty { finishRecord() }
            current[key] = value
        }
        finishRecord()

        return parseRecords(records)
    }

    static func parseRecords(_ records: [[String: String]]) -> [StartupItem] {

        let namesByIdentifier = records.reduce(into: [String: String]()) { result, record in
            guard let identifier = clean(record["Identifier"]),
                  let name = clean(record["Name"]) else { return }
            result[identifier] = name
        }

        let recordsByIdentifier = records.reduce(into: [String: [String: String]]()) { result, record in
            if let identifier = clean(record["Identifier"]) { result[identifier] = record }
        }
        func resolvedURL(_ record: [String: String], visited: Set<String> = []) -> String? {
            guard let raw = Self.filePath(clean(record["URL"])) else { return nil }
            if raw.hasPrefix("/") { return raw }
            guard let parent = clean(record["Parent Identifier"]), !visited.contains(parent),
                  let parentRecord = recordsByIdentifier[parent],
                  let base = resolvedURL(parentRecord, visited: visited.union([parent])) else { return nil }
            return Self.resolveRelativePath(raw, base: base)
        }

        return records.compactMap { record in
            let label = clean(record["Identifier"]) ?? clean(record["Name"]) ?? clean(record["UUID"])
            guard let label else { return nil }
            let sourcePath = resolvedURL(record)
            let rawExecutable = Self.filePath(clean(record["Executable Path"]))
            let executable = rawExecutable.map { raw in
                raw.hasPrefix("/") ? raw : sourcePath.flatMap { Self.resolveRelativePath(raw, base: $0) }
            } ?? sourcePath
            let disposition = record["Disposition"]?.lowercased() ?? ""
            let enabled: Bool? = if disposition.contains("disabled") {
                false
            } else if disposition.contains("enabled") {
                true
            } else {
                nil
            }
            let type = record["Type"]?.lowercased() ?? ""
            let source: StartupSource = type.contains("login") ? .loginItem : .backgroundTask
            let itemName = clean(record["Name"])
            let parentIdentifier = clean(record["Parent Identifier"])
            let parentName = parentIdentifier.flatMap { namesByIdentifier[$0] }
            let ownerName = parentName ?? itemName
            var notes: [String] = []
            if executable == nil { notes.append("后台记录未提供可解析的绝对执行路径；目标存在性与签名保持未知。") }
            if let note = PathAccessPolicy.protectedPathNote(for: executable) { notes.append(note) }
            return StartupItem(
                // 保留原始来源位置作为稳定键，路径解析修复不应把旧项目变成新增项目。
                id: "btm:\(record["UUID"] ?? label):\(Self.legacyLocation(record) ?? "")",
                label: label,
                displayName: itemName ?? parentName ?? label,
                source: source,
                sourcePath: sourcePath,
                executablePath: executable,
                configuration: record,
                attribution: AppAttribution(
                    displayName: ownerName,
                    bundleIdentifier: clean(record["Bundle Identifier"]) ?? parentIdentifier,
                    bundlePath: parentIdentifier.flatMap { recordsByIdentifier[$0] }.flatMap { resolvedURL($0) },
                    source: "Background Task Management"
                ),
                targetExists: PathAccessPolicy.targetExistsWithoutPrompt(at: executable),
                isEnabled: enabled,
                isAppleItem: false,
                discoveryNotes: notes
            )
        }
    }

    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed != "(null)",
              trimmed != "null",
              trimmed != "<null>" else { return nil }
        return trimmed
    }

    private static func filePath(_ rawValue: String?) -> String? {
        guard let rawValue, !rawValue.isEmpty else { return nil }
        if rawValue.hasPrefix("file://"), let url = URL(string: rawValue) { return url.path }
        if rawValue.hasPrefix("/") { return rawValue }
        guard !rawValue.contains("://") else { return nil }
        return rawValue.removingPercentEncoding
    }

    private static func resolveRelativePath(_ path: String, base: String) -> String? {
        let root = URL(fileURLWithPath: base).standardizedFileURL.path
        let resolved = URL(fileURLWithPath: root).appendingPathComponent(path).standardizedFileURL.path
        guard resolved.hasPrefix(root + "/") else { return nil }
        return resolved
    }

    private static func legacyLocation(_ record: [String: String]) -> String? {
        guard let raw = clean(record["Executable Path"]) ?? clean(record["URL"]) else { return nil }
        if raw.hasPrefix("file://") { return URL(string: raw)?.path }
        return raw
    }
}
