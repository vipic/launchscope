import Foundation

struct ShellConfigScanner: Sendable {
    var files: [String]

    init(homeDirectory: String = NSHomeDirectory()) {
        files = [
            ".zprofile", ".zlogin", ".zshrc", ".profile", ".bash_profile", ".bashrc",
            ".config/fish/config.fish",
        ].map { URL(fileURLWithPath: homeDirectory).appendingPathComponent($0).path }
    }

    init(files: [String]) { self.files = files }

    func scan() -> (items: [StartupItem], issues: [ScanIssue]) {
        var items: [StartupItem] = []
        var issues: [ScanIssue] = []
        for path in files where FileManager.default.fileExists(atPath: path) {
            do {
                let contents = try String(contentsOfFile: path, encoding: .utf8)
                items.append(contentsOf: Self.parse(contents, path: path))
            } catch {
                issues.append(ScanIssue(source: path, message: error.localizedDescription, severity: .warning))
            }
        }
        return (items, issues)
    }

    static func parse(_ contents: String, path: String) -> [StartupItem] {
        let commands = contents.split(separator: "\n", omittingEmptySubsequences: false).enumerated().compactMap { offset, line -> (Int, String)? in
            let command = line.trimmingCharacters(in: .whitespaces)
            guard !command.isEmpty, !command.hasPrefix("#") else { return nil }
            return (offset + 1, command)
        }
        guard !commands.isEmpty else { return [] }

        let fileName = (path as NSString).lastPathComponent
        let shellIdentifier = fileName.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let isLoginShellFile = [".zprofile", ".zlogin", ".profile", ".bash_profile"].contains(fileName)
        let executionContext = isLoginShellFile ? "登录 Shell" : "交互式 Shell"
        var configuration = Dictionary(uniqueKeysWithValues: commands.map {
            ("第 \($0.0) 行", $0.1)
        })
        configuration["执行场景"] = executionContext
        configuration["有效行数"] = String(commands.count)

        return [StartupItem(
            id: "shell:\(path)",
            label: "shell.\(shellIdentifier)",
            displayName: fileName,
            source: .shellConfiguration,
            sourcePath: path,
            arguments: commands.map(\.1),
            scheduleDescription: executionContext,
            configuration: configuration,
            isEnabled: true,
            isAppleItem: false,
            discoveryNotes: [
                isLoginShellFile
                    ? "该文件会在登录 Shell 启动时读取，但不一定在 macOS 图形界面登录时执行"
                    : "该文件通常在打开交互式终端时读取，不属于严格意义上的系统登录启动项",
            ]
        )]
    }
}
