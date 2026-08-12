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
        let fileName = (path as NSString).lastPathComponent
        let shellIdentifier = fileName.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let isLoginShellFile = [".zprofile", ".zlogin", ".profile", ".bash_profile"].contains(fileName)
        let executionContext = isLoginShellFile ? "登录 Shell" : "交互式 Shell"
        let activeLines = contents.components(separatedBy: "\n").map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty && !$0.hasPrefix("#") }
        let structurallySimple = activeLines.allSatisfy(Self.isSimpleStandaloneCommand)
        return contents.split(separator: "\n", omittingEmptySubsequences: false).enumerated().compactMap { offset, line in
            let rawLine = String(line)
            let restored = ManagedTextLine.originalLine(from: rawLine)
            let original = restored ?? rawLine
            let command = original.trimmingCharacters(in: .whitespaces)
            guard !command.isEmpty, restored != nil || !command.hasPrefix("#") else { return nil }
            let lineNumber = offset + 1
            return StartupItem(
                id: "shell:\(path):\(lineNumber):\(command)",
                label: "shell.\(shellIdentifier).\(lineNumber)",
                displayName: command,
                source: .shellConfiguration,
                sourcePath: path,
                arguments: [command],
                scheduleDescription: executionContext,
                configuration: [
                    "配置文件": fileName, "行号": String(lineNumber), "原始行": original,
                    "执行场景": executionContext, "可安全单行修改": structurallySimple ? "是" : "否",
                ],
                isEnabled: restored == nil,
                isAppleItem: false,
                discoveryNotes: [isLoginShellFile
                    ? "该命令会在登录 Shell 启动时读取，但不一定在 macOS 图形界面登录时执行"
                    : "该命令通常在打开交互式终端时读取，不属于严格意义上的系统登录启动项"],
                controlMetadata: ["line": String(lineNumber), "original": original, "fingerprint": ManagedTextLine.fingerprint(contents)]
            )
        }
    }

    private static func isSimpleStandaloneCommand(_ line: String) -> Bool {
        if line.hasSuffix("\\") || line.contains("<<") { return false }
        let first = line.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        let structural = ["if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done", "case", "esac", "function", "{", "}"]
        return !structural.contains(first) && !line.hasSuffix("{")
    }
}
