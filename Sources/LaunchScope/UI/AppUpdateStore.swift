import Foundation

@MainActor
final class AppUpdateStore: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case updateAvailable(AppRelease)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastCheckedAt: Date?

    let currentVersion: String
    let currentBuild: String

    private let checker: any AppUpdateChecking
    private let defaults: UserDefaults
    private let now: () -> Date
    private let automaticCheckInterval: TimeInterval = 24 * 60 * 60

    init(
        checker: any AppUpdateChecking = GitHubAppUpdateChecker(),
        bundle: Bundle = .main,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        currentVersion: String? = nil,
        currentBuild: String? = nil
    ) {
        self.checker = checker
        self.defaults = defaults
        self.now = now
        self.currentVersion = currentVersion
            ?? bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.0.0"
        self.currentBuild = currentBuild
            ?? bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "—"
        lastCheckedAt = defaults.object(forKey: PreferenceKeys.lastUpdateCheckAt) as? Date
    }

    func checkAutomaticallyIfNeeded() {
        let enabled = defaults.object(forKey: PreferenceKeys.automaticallyCheckForUpdates) as? Bool ?? true
        guard enabled,
              lastCheckedAt.map({ now().timeIntervalSince($0) >= automaticCheckInterval }) ?? true else { return }
        checkForUpdates(isAutomatic: true)
    }

    func checkForUpdates(isAutomatic: Bool = false) {
        guard state != .checking else { return }
        state = .checking
        let checkedAt = now()
        lastCheckedAt = checkedAt
        defaults.set(checkedAt, forKey: PreferenceKeys.lastUpdateCheckAt)
        Task {
            do {
                let release = try await checker.latestRelease()
                guard let installed = AppVersion(currentVersion) else {
                    throw AppUpdateError.unsupportedCurrentVersion(currentVersion)
                }
                guard let latest = AppVersion(release.version) else {
                    throw AppUpdateError.invalidRelease
                }
                state = installed < latest ? .updateAvailable(release) : .upToDate
            } catch {
                state = isAutomatic ? .idle : .failed(error.localizedDescription)
            }
        }
    }
}
