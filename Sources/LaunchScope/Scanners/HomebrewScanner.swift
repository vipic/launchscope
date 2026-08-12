import Foundation

struct HomebrewServiceRecord: Decodable {
    var name: String
    var status: String
    var user: String?
    var file: String?
    var exitCode: Int32?

    enum CodingKeys: String, CodingKey {
        case name, status, user, file
        case exitCode = "exit_code"
    }
}

struct HomebrewScanner: Sendable {
    var runner: any CommandRunning = CommandRunner()

    func scan() -> (items: [StartupItem], issues: [ScanIssue]) {
        guard let brewPath = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) else { return ([], []) }

        let result = runner.run(executable: brewPath, arguments: ["services", "list", "--json"], timeout: 5)
        if result.timedOut {
            return ([], [ScanIssue(source: "Homebrew", message: "读取服务列表超时", severity: .warning)])
        }
        guard result.exitCode == 0 else {
            return ([], [ScanIssue(
                source: "Homebrew",
                message: result.standardError.trimmingCharacters(in: .whitespacesAndNewlines),
                severity: .warning
            )])
        }
        do {
            return (try Self.parse(Data(result.standardOutput.utf8)), [])
        } catch {
            return ([], [ScanIssue(source: "Homebrew", message: "无法解析服务列表：\(error.localizedDescription)", severity: .warning)])
        }
    }

    static func parse(_ data: Data) throws -> [StartupItem] {
        try JSONDecoder().decode([HomebrewServiceRecord].self, from: data).map { record in
            let state: RuntimeState = record.status == "started" ? .running : .notLoaded
            return StartupItem(
                id: "homebrew:\(record.name)",
                label: "homebrew.mxcl.\(record.name)",
                displayName: record.name,
                source: .homebrewService,
                sourcePath: record.file,
                configuration: [
                    "服务名": record.name,
                    "状态": record.status,
                    "用户": record.user ?? "—",
                    "配置文件": record.file ?? "—",
                ],
                runtime: RuntimeInfo(state: state, lastExitCode: record.exitCode),
                isEnabled: state == .running,
                isAppleItem: false
            )
        }
    }
}
