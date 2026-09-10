import CryptoKit
import Foundation

enum AppUpdaterError: LocalizedError, Equatable {
    case invalidDownload
    case downloadTooLarge
    case checksumMismatch
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidDownload: return "更新下载地址或响应无效。"
        case .downloadTooLarge: return "更新文件超过安全大小限制。"
        case .checksumMismatch: return "更新文件校验失败，已取消安装。"
        case let .installFailed(message): return message
        }
    }
}

struct DownloadedAppUpdate: Sendable {
    let release: AppRelease
    let stagingURL: URL
    let dmgURL: URL
}

protocol AppUpdating: Sendable {
    func download(
        release: AppRelease,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> DownloadedAppUpdate

    func prepareAndLaunchInstaller(
        update: DownloadedAppUpdate,
        currentBundleURL: URL,
        currentPID: Int32
    ) async throws
}

struct AppUpdater: AppUpdating, Sendable {
    static let failureReportURL = URL(fileURLWithPath: "/tmp/launchscope_update_error.txt")
    static let logURL = URL(fileURLWithPath: "/tmp/launchscope_update.log")
    private static let maximumDownloadBytes: Int64 = 300 * 1024 * 1024

    var runner: any CommandRunning = CommandRunner()

    func download(
        release: AppRelease,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> DownloadedAppUpdate {
        guard Self.isTrustedGitHubAsset(release.downloadURL, extension: "dmg"),
              let checksumURL = release.checksumURL,
              Self.isTrustedGitHubAsset(checksumURL, extension: "sha256") else {
            throw AppUpdaterError.invalidDownload
        }

        let delegate = UpdateDownloadDelegate(
            expectedSize: release.downloadSize,
            byteLimit: Self.downloadByteLimit(expectedSize: release.downloadSize),
            onProgress: onProgress
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 300
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        let temporaryDMG = try await delegate.download(from: release.downloadURL, using: session)

        do {
            let checksum = try await downloadChecksum(checksumURL)
            guard matches(checksum: checksum, file: temporaryDMG) else {
                throw AppUpdaterError.checksumMismatch
            }

            let staging = FileManager.default.temporaryDirectory
                .appendingPathComponent("launchscope-update-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            let stableDMG = staging.appendingPathComponent("LaunchScope-\(release.version).dmg")
            try FileManager.default.moveItem(at: temporaryDMG, to: stableDMG)
            return DownloadedAppUpdate(release: release, stagingURL: staging, dmgURL: stableDMG)
        } catch {
            try? FileManager.default.removeItem(at: temporaryDMG)
            throw error
        }
    }

    func prepareAndLaunchInstaller(
        update: DownloadedAppUpdate,
        currentBundleURL: URL = Bundle.main.bundleURL,
        currentPID: Int32 = ProcessInfo.processInfo.processIdentifier
    ) async throws {
        let runner = runner
        try await Task.detached {
            try Self.preflight(update: update, currentBundleURL: currentBundleURL, runner: runner)

            let scriptURL = update.stagingURL.appendingPathComponent("install.sh")
            let scriptBody = Self.installScript(
                dmg: update.dmgURL.path,
                staging: update.stagingURL.path,
                target: currentBundleURL.path,
                pid: currentPID,
                expectedVersion: update.release.version
            )
            guard let data = scriptBody.data(using: .utf8) else {
                throw AppUpdaterError.installFailed("无法生成安装脚本。")
            }
            try data.write(to: scriptURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

            let launchCommand = Self.detachedLaunchCommand(scriptURL: scriptURL)
            let result = runner.run(executable: "/bin/sh", arguments: ["-c", launchCommand], timeout: 5)
            guard result.exitCode == 0, !result.timedOut else {
                throw AppUpdaterError.installFailed(Self.commandFailure(result, fallback: "无法启动后台安装程序。"))
            }
        }.value
    }

    static func consumeFailureReport() -> String? {
        guard let data = try? Data(contentsOf: failureReportURL),
              let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty else { return nil }
        try? FileManager.default.removeItem(at: failureReportURL)
        return message
    }

    static func downloadProgress(
        totalBytesWritten: Int64,
        totalBytesExpected: Int64,
        expectedSize: Int
    ) -> Double? {
        let total = totalBytesExpected > 0 ? totalBytesExpected : Int64(expectedSize)
        guard total > 0 else { return nil }
        return min(max(Double(totalBytesWritten) / Double(total), 0), 0.99)
    }

    static func downloadByteLimit(expectedSize: Int) -> Int64 {
        guard expectedSize > 0 else { return maximumDownloadBytes }
        let withSlack = Int64(Double(expectedSize) * 1.10) + 1_048_576
        return min(maximumDownloadBytes, max(Int64(expectedSize), withSlack))
    }

    static func detachedLaunchCommand(scriptURL: URL) -> String {
        "nohup /bin/sh \(shellQuote(scriptURL.path)) >\(shellQuote(logURL.path)) 2>&1 </dev/null &"
    }

    private func downloadChecksum(_ url: URL) async throws -> String {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration)
        let (data, response) = try await session.data(from: url)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              data.count <= 4096,
              let checksum = String(data: data, encoding: .utf8)?
                .split(whereSeparator: { $0.isWhitespace }).first.map(String.init),
              checksum.count == 64,
              checksum.allSatisfy({ $0.isHexDigit }) else {
            throw AppUpdaterError.invalidDownload
        }
        return checksum
    }

    private func matches(checksum: String, file: URL) -> Bool {
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { return false }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return digest.caseInsensitiveCompare(checksum) == .orderedSame
    }

    private static func preflight(
        update: DownloadedAppUpdate,
        currentBundleURL: URL,
        runner: any CommandRunning
    ) throws {
        guard currentBundleURL.pathExtension == "app",
              FileManager.default.fileExists(atPath: currentBundleURL.path),
              FileManager.default.isWritableFile(atPath: currentBundleURL.deletingLastPathComponent().path) else {
            throw AppUpdaterError.installFailed("当前应用所在位置不可写，请先将 LaunchScope 移到“应用程序”文件夹。")
        }

        let mountURL = update.stagingURL.appendingPathComponent("preflight-mount", isDirectory: true)
        try FileManager.default.createDirectory(at: mountURL, withIntermediateDirectories: true)
        let attach = runner.run(
            executable: "/usr/bin/hdiutil",
            arguments: ["attach", update.dmgURL.path, "-nobrowse", "-readonly", "-mountpoint", mountURL.path],
            timeout: 30
        )
        guard attach.exitCode == 0, !attach.timedOut else {
            throw AppUpdaterError.installFailed(commandFailure(attach, fallback: "无法挂载更新磁盘映像。"))
        }

        do {
            try validateCandidate(
                mountURL.appendingPathComponent("LaunchScope.app", isDirectory: true),
                currentBundleURL: currentBundleURL,
                expectedVersion: update.release.version,
                runner: runner
            )
        } catch {
            _ = runner.run(executable: "/usr/bin/hdiutil", arguments: ["detach", mountURL.path, "-force"], timeout: 15)
            throw error
        }

        let detach = runner.run(
            executable: "/usr/bin/hdiutil",
            arguments: ["detach", mountURL.path],
            timeout: 15
        )
        guard detach.exitCode == 0, !detach.timedOut else {
            throw AppUpdaterError.installFailed(commandFailure(detach, fallback: "无法卸载更新预检磁盘映像。"))
        }
    }

    private static func validateCandidate(
        _ candidateURL: URL,
        currentBundleURL: URL,
        expectedVersion: String,
        runner: any CommandRunning
    ) throws {
        guard let bundle = Bundle(url: candidateURL),
              bundle.bundleIdentifier == "com.nekutai.launchscope",
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == expectedVersion else {
            throw AppUpdaterError.installFailed("更新包的应用标识或版本不匹配。")
        }

        let verify = runner.run(
            executable: "/usr/bin/codesign",
            arguments: ["--verify", "--deep", "--strict", candidateURL.path],
            timeout: 30
        )
        guard verify.exitCode == 0, !verify.timedOut else {
            throw AppUpdaterError.installFailed(commandFailure(verify, fallback: "更新包签名校验失败。"))
        }

        let currentRequirement = designatedRequirement(for: currentBundleURL, runner: runner)
        let candidateRequirement = designatedRequirement(for: candidateURL, runner: runner)
        guard let currentRequirement, currentRequirement == candidateRequirement else {
            throw AppUpdaterError.installFailed("更新包签名身份与当前应用不一致。")
        }
    }

    private static func designatedRequirement(
        for url: URL,
        runner: any CommandRunning
    ) -> String? {
        let result = runner.run(
            executable: "/usr/bin/codesign",
            arguments: ["-dr", "-", url.path],
            timeout: 15
        )
        guard result.exitCode == 0, !result.timedOut else { return nil }
        let output = result.standardOutput + "\n" + result.standardError
        return output.components(separatedBy: "designated => ").last?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    private static func isTrustedGitHubAsset(_ url: URL, extension pathExtension: String) -> Bool {
        url.scheme == "https" && url.host == "github.com" && url.pathExtension == pathExtension
    }

    private static func commandFailure(_ result: CommandResult, fallback: String) -> String {
        let message = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? fallback : message
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func installScript(
        dmg: String,
        staging: String,
        target: String,
        pid: Int32,
        expectedVersion: String,
        relaunch: Bool = true
    ) -> String {
        let allowedVersionCharacters = CharacterSet(charactersIn: "0123456789.")
        let safeVersion = AppVersion(expectedVersion) != nil
            && expectedVersion.unicodeScalars.allSatisfy(allowedVersionCharacters.contains)
            ? expectedVersion
            : "0.0.0"
        let relaunchCommand = relaunch
            ? "/usr/bin/open \"$TARGET\" || printf '%s\\n' \"新版本已经安装，但未能自动重新打开。\" > \"$ERROR_FILE\""
            : ":"
        return """
        #!/bin/sh
        set -eu
        DMG=\(shellQuote(dmg))
        STAGING=\(shellQuote(staging))
        TARGET=\(shellQuote(target))
        EXPECTED_VERSION=\(shellQuote(safeVersion))
        CURRENT_PID=\(pid)
        ERROR_FILE=\(shellQuote(failureReportURL.path))
        MOUNT="$STAGING/install-mount"
        BACKUP=""

        cleanup() {
            if mount | grep -Fq "on $MOUNT "; then
                /usr/bin/hdiutil detach "$MOUNT" -force >/dev/null 2>&1 || true
            fi
            rm -rf "$STAGING"
        }
        fail_update() {
            message="$1"
            if [ -n "$BACKUP" ] && [ -d "$BACKUP" ]; then
                rm -rf "$TARGET"
                mv "$BACKUP" "$TARGET" || true
            fi
            printf '%s\\n' "$message" > "$ERROR_FILE"
            /usr/bin/open "$TARGET" >/dev/null 2>&1 || true
            exit 1
        }
        trap cleanup EXIT
        rm -f "$ERROR_FILE"

        attempts=0
        while kill -0 "$CURRENT_PID" 2>/dev/null; do
            sleep 0.5
            attempts=$((attempts + 1))
            [ "$attempts" -lt 60 ] || fail_update "LaunchScope 未能及时退出，更新没有安装。"
        done

        mkdir -p "$MOUNT"
        /usr/bin/hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MOUNT" >/dev/null \
            || fail_update "无法挂载更新磁盘映像。"
        CANDIDATE="$MOUNT/LaunchScope.app"
        [ -d "$CANDIDATE" ] || fail_update "更新磁盘映像中缺少 LaunchScope.app。"
        [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$CANDIDATE/Contents/Info.plist" 2>/dev/null || true)" = "com.nekutai.launchscope" ] \
            || fail_update "更新包的应用标识不匹配。"
        [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$CANDIDATE/Contents/Info.plist" 2>/dev/null || true)" = "$EXPECTED_VERSION" ] \
            || fail_update "更新包版本与预期版本不匹配。"
        /usr/bin/codesign --verify --deep --strict "$CANDIDATE" \
            || fail_update "更新包签名校验失败。"

        CURRENT_REQ=$(/usr/bin/codesign -dr - "$TARGET" 2>&1 | sed -n 's/^.*designated => //p' || true)
        CANDIDATE_REQ=$(/usr/bin/codesign -dr - "$CANDIDATE" 2>&1 | sed -n 's/^.*designated => //p' || true)
        [ -n "$CURRENT_REQ" ] && [ "$CURRENT_REQ" = "$CANDIDATE_REQ" ] \
            || fail_update "更新包签名身份与当前应用不一致。"

        TARGET_PARENT=$(dirname "$TARGET")
        TARGET_NAME=$(basename "$TARGET")
        BACKUP="$TARGET_PARENT/.${TARGET_NAME}.update-backup-$(date +%s)"
        mv "$TARGET" "$BACKUP" || fail_update "无法备份当前应用。"
        /usr/bin/ditto "$CANDIDATE" "$TARGET" || fail_update "无法复制新版本，已恢复原应用。"
        [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$TARGET/Contents/Info.plist" 2>/dev/null || true)" = "$EXPECTED_VERSION" ] \
            || fail_update "安装后的版本不正确，已恢复原应用。"
        /usr/bin/codesign --verify --deep --strict "$TARGET" \
            || fail_update "安装后的签名校验失败，已恢复原应用。"

        rm -rf "$BACKUP"
        BACKUP=""
        /usr/bin/hdiutil detach "$MOUNT" >/dev/null || fail_update "更新已安装，但无法卸载磁盘映像。"
        rm -f "$ERROR_FILE"
        \(relaunchCommand)
        """
    }
}

private final class UpdateDownloadDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let expectedSize: Int
    private let byteLimit: Int64
    private let onProgress: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<URL, Error>?
    private var fileURL: URL?
    private var fileHandle: FileHandle?
    private var expectedBytes: Int64 = 0
    private var writtenBytes: Int64 = 0
    private var lastProgress = 0.0
    private var receivedSuccessfulResponse = false
    private var finished = false

    init(expectedSize: Int, byteLimit: Int64, onProgress: @escaping @Sendable (Double) -> Void) {
        self.expectedSize = expectedSize
        self.byteLimit = byteLimit
        self.onProgress = onProgress
    }

    func download(from remoteURL: URL, using session: URLSession) async throws -> URL {
        let localURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("launchscope-download-\(UUID().uuidString).dmg")
        _ = FileManager.default.createFile(atPath: localURL.path, contents: nil)
        do {
            fileHandle = try FileHandle(forWritingTo: localURL)
        } catch {
            try? FileManager.default.removeItem(at: localURL)
            throw error
        }
        fileURL = localURL
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            session.dataTask(with: remoteURL).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              response.url?.scheme == "https",
              response.expectedContentLength < 0 || response.expectedContentLength <= byteLimit else {
            completionHandler(.cancel)
            finish(with: AppUpdaterError.invalidDownload)
            return
        }
        receivedSuccessfulResponse = true
        expectedBytes = response.expectedContentLength
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard writtenBytes + Int64(data.count) <= byteLimit else {
            dataTask.cancel()
            finish(with: AppUpdaterError.downloadTooLarge)
            return
        }
        do {
            try fileHandle?.write(contentsOf: data)
        } catch {
            dataTask.cancel()
            finish(with: error)
            return
        }
        writtenBytes += Int64(data.count)
        guard let progress = AppUpdater.downloadProgress(
            totalBytesWritten: writtenBytes,
            totalBytesExpected: expectedBytes,
            expectedSize: expectedSize
        ), progress > lastProgress else { return }
        lastProgress = progress
        onProgress(progress)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer { session.finishTasksAndInvalidate() }
        if let error {
            finish(with: error)
        } else if receivedSuccessfulResponse, let fileURL {
            onProgress(1)
            finish(with: fileURL)
        } else {
            finish(with: AppUpdaterError.invalidDownload)
        }
    }

    private func finish(with url: URL) {
        guard !finished else { return }
        finished = true
        closeFile()
        continuation?.resume(returning: url)
        continuation = nil
    }

    private func finish(with error: Error) {
        guard !finished else { return }
        finished = true
        closeFile()
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        continuation?.resume(throwing: error)
        continuation = nil
    }

    private func closeFile() {
        try? fileHandle?.close()
        fileHandle = nil
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
