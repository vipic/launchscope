import Foundation
import AppKit

@MainActor
final class AppUpdateStore: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case downloading(AppRelease, Double)
        case installing(AppRelease)
        case upToDate
        case updateAvailable(AppRelease)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastCheckedAt: Date?

    let currentVersion: String
    let currentBuild: String

    private let checker: any AppUpdateChecking
    private let updater: any AppUpdating
    private let defaults: UserDefaults
    private let now: () -> Date
    private let terminate: @MainActor () -> Void
    private let automaticCheckInterval: TimeInterval = 24 * 60 * 60

    init(
        checker: any AppUpdateChecking = GitHubAppUpdateChecker(),
        updater: any AppUpdating = AppUpdater(),
        bundle: Bundle = .main,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        currentVersion: String? = nil,
        currentBuild: String? = nil,
        previousUpdateFailure: String? = AppUpdater.consumeFailureReport(),
        terminate: @escaping @MainActor () -> Void = { NSApp.terminate(nil) }
    ) {
        self.checker = checker
        self.updater = updater
        self.defaults = defaults
        self.now = now
        self.terminate = terminate
        self.currentVersion = currentVersion
            ?? bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.0.0"
        self.currentBuild = currentBuild
            ?? bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "—"
        lastCheckedAt = defaults.object(forKey: PreferenceKeys.lastUpdateCheckAt) as? Date
        if let previousUpdateFailure {
            state = .failed("上次自动更新未能完成：\(previousUpdateFailure)")
        }
    }

    func checkAutomaticallyIfNeeded() {
        let enabled = defaults.object(forKey: PreferenceKeys.automaticallyCheckForUpdates) as? Bool ?? true
        guard enabled,
              lastCheckedAt.map({ now().timeIntervalSince($0) >= automaticCheckInterval }) ?? true else { return }
        checkForUpdates(isAutomatic: true)
    }

    func checkForUpdates(isAutomatic: Bool = false) {
        switch state {
        case .checking, .downloading, .installing: return
        default: break
        }
        state = .checking
        Task {
            do {
                let release = try await checker.latestRelease()
                let checkedAt = now()
                lastCheckedAt = checkedAt
                defaults.set(checkedAt, forKey: PreferenceKeys.lastUpdateCheckAt)
                guard let installed = AppVersion(currentVersion) else {
                    throw AppUpdateError.unsupportedCurrentVersion(currentVersion)
                }
                guard let latest = AppVersion(release.version) else {
                    throw AppUpdateError.invalidRelease
                }
                state = installed < latest ? .updateAvailable(release) : .upToDate
            } catch {
                state = isAutomatic ? .idle : .failed("检查更新失败：\(error.localizedDescription)")
            }
        }
    }

    func installUpdate(_ release: AppRelease) {
        guard case .updateAvailable = state else { return }
        state = .downloading(release, 0)
        Task {
            var downloaded: DownloadedAppUpdate?
            do {
                let update = try await updater.download(release: release) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self, case .downloading(let activeRelease, _) = self.state,
                              activeRelease == release else { return }
                        self.state = .downloading(release, progress)
                    }
                }
                downloaded = update
                state = .installing(release)
                try await updater.prepareAndLaunchInstaller(
                    update: update,
                    currentBundleURL: Bundle.main.bundleURL,
                    currentPID: ProcessInfo.processInfo.processIdentifier
                )
                terminate()
            } catch {
                if let downloaded {
                    try? FileManager.default.removeItem(at: downloaded.stagingURL)
                }
                state = .failed("安装 LaunchScope \(release.version) 失败：\(error.localizedDescription)")
            }
        }
    }
}
