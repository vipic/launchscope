import Foundation

struct LaunchdLocation: Sendable {
    var path: String
    var source: StartupSource
    var domain: String
}

struct LaunchdScanner: Sendable {
    var locations: [LaunchdLocation]

    init(homeDirectory: String = NSHomeDirectory()) {
        locations = [
            LaunchdLocation(
                path: "\(homeDirectory)/Library/LaunchAgents",
                source: .userLaunchAgent,
                domain: "gui/\(getuid())"
            ),
            LaunchdLocation(path: "/Library/LaunchAgents", source: .globalLaunchAgent, domain: "gui/\(getuid())"),
            LaunchdLocation(path: "/Library/LaunchDaemons", source: .launchDaemon, domain: "system"),
            LaunchdLocation(path: "/System/Library/LaunchAgents", source: .systemLaunchAgent, domain: "gui/\(getuid())"),
            LaunchdLocation(path: "/System/Library/LaunchDaemons", source: .systemLaunchDaemon, domain: "system"),
        ]
    }

    init(locations: [LaunchdLocation]) {
        self.locations = locations
    }

    func scan() -> (items: [StartupItem], issues: [ScanIssue]) {
        var items: [StartupItem] = []
        var issues: [ScanIssue] = []

        for location in locations {
            guard FileManager.default.fileExists(atPath: location.path) else { continue }
            let directoryURL = URL(fileURLWithPath: location.path, isDirectory: true)
            do {
                let files = try FileManager.default.contentsOfDirectory(
                    at: directoryURL,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                ).filter { $0.pathExtension.lowercased() == "plist" }

                for file in files {
                    do {
                        let data = try Data(contentsOf: file)
                        guard let plist = try PropertyListSerialization.propertyList(
                            from: data,
                            options: [],
                            format: nil
                        ) as? [String: Any] else {
                            throw ScanError.invalidPropertyList
                        }
                        items.append(Self.makeItem(plist: plist, file: file, location: location))
                    } catch {
                        issues.append(ScanIssue(
                            source: file.path,
                            message: "无法读取启动配置：\(error.localizedDescription)",
                            severity: .warning
                        ))
                    }
                }
            } catch {
                issues.append(ScanIssue(
                    source: location.path,
                    message: "无法枚举目录：\(error.localizedDescription)",
                    severity: .error
                ))
            }
        }
        return (items, issues)
    }

    static func makeItem(plist: [String: Any], file: URL, location: LaunchdLocation) -> StartupItem {
        let label = plist["Label"] as? String ?? file.deletingPathExtension().lastPathComponent
        let arguments: [String]
        if let values = plist["ProgramArguments"] as? [String] {
            arguments = values
        } else if let value = plist["ProgramArguments"] as? String {
            arguments = [value]
        } else {
            arguments = []
        }
        let rawExecutable = plist["Program"] as? String
            ?? plist["BundleProgram"] as? String
            ?? arguments.first
        let executable = ExecutableResolver.resolve(rawExecutable)
        let environment = (plist["EnvironmentVariables"] as? [String: Any])?.reduce(into: [String: String]()) {
            $0[$1.key] = ConfigurationFormatter.string(from: $1.value)
        } ?? [:]
        let disabled = plist["Disabled"] as? Bool
        let systemLocation = location.source.isAppleSystemLocation
        let appleLabel = label.hasPrefix("com.apple.")

        var notes = rawExecutable == nil ? ["配置中未声明 Program 或 ProgramArguments"] : []
        if let note = PathAccessPolicy.protectedPathNote(for: executable) { notes.append(note) }

        return StartupItem(
            id: "launchd:\(file.path)",
            label: label,
            source: location.source,
            sourcePath: file.path,
            executablePath: executable,
            arguments: arguments,
            workingDirectory: plist["WorkingDirectory"] as? String,
            runAtLoad: plist["RunAtLoad"] as? Bool,
            keepAliveDescription: ConfigurationFormatter.keepAliveDescription(plist["KeepAlive"]),
            scheduleDescription: ConfigurationFormatter.scheduleDescription(plist),
            environment: environment,
            configuration: ConfigurationFormatter.dictionary(from: plist),
            runtime: RuntimeInfo(domain: location.domain),
            targetExists: PathAccessPolicy.targetExistsWithoutPrompt(at: executable),
            isEnabled: disabled.map { !$0 },
            isAppleItem: systemLocation && appleLabel,
            discoveryNotes: notes
        )
    }
}

enum ScanError: LocalizedError {
    case invalidPropertyList

    var errorDescription: String? { "不是有效的属性列表" }
}

enum ExecutableResolver {
    static func resolve(_ rawPath: String?) -> String? {
        guard var rawPath, !rawPath.isEmpty else { return nil }
        rawPath = (rawPath as NSString).expandingTildeInPath
        if rawPath.hasPrefix("/") { return rawPath }

        let searchPaths = [
            "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"
        ]
        for directory in searchPaths {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(rawPath).path
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return rawPath
    }
}
