import Foundation

/// 启动扫描的隐私边界。
///
/// LaunchScope 可以展示由 launchd/BTM 提供的路径字符串，但后台扫描不得为了
/// `fileExists`、Bundle 元数据或签名检查而主动读取用户的受保护内容目录。
enum PathAccessPolicy {
    static func canProbeMetadata(at path: String, homeDirectory: String = NSHomeDirectory()) -> Bool {
        let standardizedPath = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            .standardizedFileURL.path
        let home = URL(fileURLWithPath: homeDirectory).standardizedFileURL.path
        let protectedRoots = [
            "Documents",
            "Desktop",
            "Downloads",
            "Pictures",
            "Movies",
            "Music",
            "Library/Mobile Documents",
            "Library/CloudStorage",
            "Library/Mail",
            "Library/Messages",
            "Library/Safari",
        ].map { URL(fileURLWithPath: home).appendingPathComponent($0).standardizedFileURL.path }

        return !protectedRoots.contains { root in
            standardizedPath == root || standardizedPath.hasPrefix(root + "/")
        }
    }

    static func targetExistsWithoutPrompt(at path: String?) -> Bool? {
        guard let path, canProbeMetadata(at: path) else { return nil }
        return FileManager.default.fileExists(atPath: path)
    }

    static func protectedPathNote(for path: String?) -> String? {
        guard let path, !canProbeMetadata(at: path) else { return nil }
        return "执行目标位于 macOS 受保护目录；为避免启动时弹出隐私授权，LaunchScope 只展示路径，不主动读取文件、图标或签名"
    }
}
