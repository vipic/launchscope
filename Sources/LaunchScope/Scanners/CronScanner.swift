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
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
            let parts = trimmed.split(maxSplits: 5, whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count >= 6 else { return nil }
            let schedule = parts.prefix(5).joined(separator: " ")
            let command = parts[5]
            return StartupItem(
                id: "cron:\(offset):\(trimmed)",
                label: "cron.\(offset + 1)",
                displayName: command,
                source: .cron,
                sourcePath: "当前用户 crontab",
                executablePath: Self.commandExecutable(command),
                arguments: [command],
                scheduleDescription: schedule,
                configuration: ["表达式": schedule, "命令": command],
                targetExists: PathAccessPolicy.targetExistsWithoutPrompt(at: Self.commandExecutable(command)),
                isEnabled: true,
                isAppleItem: false
            )
        }
    }

    private static func commandExecutable(_ command: String) -> String? {
        command.split(whereSeparator: \.isWhitespace).first.map(String.init).flatMap(ExecutableResolver.resolve)
    }
}
