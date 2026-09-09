import CryptoKit
import Foundation

enum AppUpdaterError: LocalizedError {
    case invalidDownload
    case checksumMismatch
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidDownload: return "更新下载地址无效。"
        case .checksumMismatch: return "更新文件校验失败，已取消替换。"
        case let .installFailed(message): return "更新安装失败：\(message)"
        }
    }
}

struct AppUpdater: Sendable {
    var runner: any CommandRunning = CommandRunner()

    func downloadAndInstall(
        release: AppRelease,
        currentBundleURL: URL = Bundle.main.bundleURL,
        currentPID: Int32 = ProcessInfo.processInfo.processIdentifier
    ) async throws {
        guard release.downloadURL.scheme == "https",
              release.downloadURL.host == "github.com",
              release.downloadURL.pathExtension == "dmg" else { throw AppUpdaterError.invalidDownload }

        let (dmgURL, _) = try await URLSession.shared.download(from: release.downloadURL)
        let checksum = try await downloadChecksum(release.checksumURL)
        if let checksum, !matches(checksum: checksum, file: dmgURL) {
            throw AppUpdaterError.checksumMismatch
        }

        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("launchscope-update-\(UUID().uuidString)", isDirectory: true)
        let script = staging.appendingPathComponent("install.sh")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let scriptBody = Self.script(
            dmg: dmgURL.path,
            staging: staging.path,
            target: currentBundleURL.path,
            pid: currentPID,
            expectedVersion: release.version
        )
        try scriptBody.data(using: .utf8)?.write(to: script, options: .atomic)
        let result = runner.run(executable: "/bin/sh", arguments: [script.path], timeout: 120)
        guard result.exitCode == 0 else {
            throw AppUpdaterError.installFailed(result.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func downloadChecksum(_ url: URL?) async throws -> String? {
        guard let url else { return nil }
        guard url.scheme == "https", url.host == "github.com" else { throw AppUpdaterError.invalidDownload }
        let (data, _) = try await URLSession.shared.data(from: url)
        return String(data: data, encoding: .utf8)?.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
    }

    private func matches(checksum: String, file: URL) -> Bool {
        guard let data = try? Data(contentsOf: file) else { return false }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return digest.caseInsensitiveCompare(checksum) == .orderedSame
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func script(dmg: String, staging: String, target: String, pid: Int32, expectedVersion: String) -> String {
        let qDmg = shellQuote(dmg), qStaging = shellQuote(staging), qTarget = shellQuote(target)
        return """
        set -euo pipefail
        dmg=\(qDmg)
        staging=\(qStaging)
        target=\(qTarget)
        mount="$staging/mount"
        extracted="$staging/LaunchScope.app"
        mkdir -p "$mount"
        hdiutil attach "$dmg" -nobrowse -readonly -mountpoint "$mount" >/dev/null
        trap 'hdiutil detach "$mount" -force >/dev/null 2>&1 || true; rm -rf "$staging"' EXIT
        test -d "$mount/LaunchScope.app"
        ditto "$mount/LaunchScope.app" "$extracted"
        test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$extracted/Contents/Info.plist")" = 'com.nekutai.launchscope'
        test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$extracted/Contents/Info.plist")" = \(shellQuote(expectedVersion))
        codesign --verify --deep --strict "$extracted"
        while kill -0 \(pid) 2>/dev/null; do sleep 1; done
        rm -rf "$target"
        ditto "$extracted" "$target"
        open "$target"
        """
    }
}
