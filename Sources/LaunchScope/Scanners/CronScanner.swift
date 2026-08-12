import Foundation

struct CronScanner: Sendable {
    var runner: any CommandRunning = CommandRunner()

    func scan() -> (items: [StartupItem], issues: [ScanIssue]) {
        let result = runner.run(executable: "/usr/bin/crontab", arguments: ["-l"], timeout: 3)
        if result.exitCode != 0 {
            let message = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            if message.localizedCaseInsensitiveContains("no crontab") || message.isEmpty {
                return ([], [])
            }
            return ([], [ScanIssue(source: "crontab", message: message, severity: .warning)])
        }
        return (Self.parse(result.standardOutput), [])
    }

    static func parse(_ text: String) -> [StartupItem] {
        text.split(separator: "\n", omittingEmptySubsequences: false).enumerated().compactMap { offset, line in
            let rawLine = String(line)
            let restored = ManagedTextLine.originalLine(from: rawLine)
            let candidate = restored ?? rawLine
            let trimmed = candidate.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, restored != nil || !trimmed.hasPrefix("#") else { return nil }
            let parts = trimmed.split(maxSplits: 5, whereSeparator: \.isWhitespace).map(String.init)
            let schedule: String
            let command: String
            if parts.first?.hasPrefix("@") == true, parts.count >= 2 {
                schedule = parts[0]
                command = parts.dropFirst().joined(separator: " ")
            } else {
                guard parts.count >= 6 else { return nil }
                schedule = parts.prefix(5).joined(separator: " ")
                command = parts[5]
            }
            return StartupItem(
                id: "cron:\(offset):\(trimmed)",
                label: "cron.\(offset + 1)",
                displayName: command,
                source: .cron,
                sourcePath: "当前用户 crontab",
                executablePath: Self.commandExecutable(command),
                arguments: [command],
                scheduleDescription: schedule,
                configuration: ["表达式": schedule, "命令": command, "行号": String(offset + 1)],
                targetExists: PathAccessPolicy.targetExistsWithoutPrompt(at: Self.commandExecutable(command)),
                isEnabled: restored == nil,
                isAppleItem: false,
                controlMetadata: ["line": String(offset + 1), "original": candidate, "fingerprint": ManagedTextLine.fingerprint(text)]
            )
        }
    }

    private static func commandExecutable(_ command: String) -> String? {
        command.split(whereSeparator: \.isWhitespace).first.map(String.init).flatMap(ExecutableResolver.resolve)
    }
}
