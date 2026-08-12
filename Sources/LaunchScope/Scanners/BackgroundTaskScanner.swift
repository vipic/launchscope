import Foundation

struct BackgroundTaskScanner: Sendable {
    var runner: any CommandRunning = CommandRunner()

    func scan() -> (items: [StartupItem], issues: [ScanIssue]) {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/sfltool") else { return ([], []) }
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

        let namesByIdentifier = records.reduce(into: [String: String]()) { result, record in
            guard let identifier = clean(record["Identifier"]),
                  let name = clean(record["Name"]) else { return }
            result[identifier] = name
        }

        return records.compactMap { record in
            let label = clean(record["Identifier"]) ?? clean(record["Name"]) ?? clean(record["UUID"])
            guard let label else { return nil }
            let executable = Self.filePath(clean(record["Executable Path"]) ?? clean(record["URL"]))
            let disposition = record["Disposition"]?.lowercased() ?? ""
            let enabled = disposition.contains("enabled") && !disposition.contains("disabled")
            let type = record["Type"]?.lowercased() ?? ""
            let source: StartupSource = type.contains("login") ? .loginItem : .backgroundTask
            let itemName = clean(record["Name"])
            let parentIdentifier = clean(record["Parent Identifier"])
            let parentName = parentIdentifier.flatMap { namesByIdentifier[$0] }
            let ownerName = parentName ?? itemName
            var notes: [String] = []
            if let note = PathAccessPolicy.protectedPathNote(for: executable) { notes.append(note) }
            return StartupItem(
                id: "btm:\(record["UUID"] ?? label):\(executable ?? "")",
                label: label,
                displayName: itemName ?? parentName ?? label,
                source: source,
                sourcePath: Self.filePath(clean(record["URL"])),
                executablePath: executable,
                configuration: record,
                attribution: AppAttribution(
                    displayName: ownerName,
                    bundleIdentifier: clean(record["Bundle Identifier"]) ?? parentIdentifier,
                    source: "Background Task Management"
                ),
                targetExists: PathAccessPolicy.targetExistsWithoutPrompt(at: executable),
                isEnabled: enabled,
                isAppleItem: label.hasPrefix("com.apple."),
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
        return rawValue
    }
}
