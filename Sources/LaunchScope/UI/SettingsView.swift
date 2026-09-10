import SwiftUI

struct SettingsView: View {
    @ObservedObject var dashboardStore: DashboardStore
    @ObservedObject var updateStore: AppUpdateStore
    @AppStorage(PreferenceKeys.showSensitiveValues) private var showSensitiveValues = false
    @AppStorage(PreferenceKeys.automaticallyCheckForUpdates) private var automaticallyCheckForUpdates = true

    var body: some View {
        TabView {
            Form {
                Section("隐私") {
                    Toggle("显示敏感配置值", isOn: $showSensitiveValues)
                        .accessibilityIdentifier("settings.show-sensitive-values")
                    Text("关闭时，疑似令牌、密码和密钥的值会显示为圆点。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("通用", systemImage: "gearshape") }

            Form {
                Section("软件更新") {
                    Toggle("自动检查更新", isOn: $automaticallyCheckForUpdates)
                        .accessibilityIdentifier("settings.automatic-updates")
                    LabeledContent("当前版本", value: versionDescription)
                    if let lastCheckedAt = updateStore.lastCheckedAt {
                        LabeledContent("上次检查") {
                            Text(lastCheckedAt, format: .dateTime.year().month().day().hour().minute())
                        }
                    }
                    updateStatus
                    HStack {
                        Button("检查更新") { updateStore.checkForUpdates() }
                            .disabled(updateStore.state == .checking || isUpdating)
                            .accessibilityIdentifier("settings.check-for-updates")
                        if case let .updateAvailable(release) = updateStore.state {
                            Button("立即更新") { updateStore.installUpdate(release) }
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("settings.install-update")
                        }
                    }
                }
                Section {
                    Text("LaunchScope 会从 GitHub 下载正式 DMG，校验版本、签名和 SHA-256 后自动替换当前应用并重启。整个过程需要你主动点击“立即更新”。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("更新", systemImage: "arrow.triangle.2.circlepath") }

            VStack(spacing: UIConstants.regularSpacing) {
                if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
                   let icon = NSImage(contentsOf: iconURL) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 96, height: 96)
                }
                Text("LaunchScope")
                    .font(.title2.bold())
                Text("macOS 自启动说明书")
                    .foregroundStyle(.secondary)
                Text("版本 \(versionDescription)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link("项目主页", destination: URL(string: "https://github.com/vipic/launchscope")!)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 420)
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch updateStore.state {
        case .idle:
            EmptyView()
        case .checking:
            HStack {
                ProgressView().controlSize(.small)
                Text("正在检查更新…")
            }
        case let .downloading(release, progress):
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("正在下载 LaunchScope \(release.version)…")
                    Spacer()
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: progress)
                Text("当前版本 \(updateStore.currentVersion) → 目标版本 \(release.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case let .installing(release):
            HStack {
                ProgressView().controlSize(.small)
                Text("正在准备安装 LaunchScope \(release.version)…应用即将重新启动。")
            }
        case .upToDate:
            Label("当前已是最新版本", systemImage: "checkmark.circle.fill")
                .foregroundStyle(LaunchScopePalette.healthy)
        case let .updateAvailable(release):
            VStack(alignment: .leading, spacing: 4) {
                Label("发现新版本", systemImage: "arrow.down.circle.fill")
                    .foregroundStyle(LaunchScopePalette.accent)
                Text("当前版本 \(updateStore.currentVersion) → 可更新至 LaunchScope \(release.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(LaunchScopePalette.warning)
        }
    }

    private var isUpdating: Bool {
        switch updateStore.state {
        case .downloading, .installing: true
        default: false
        }
    }

    private var versionDescription: String {
        "\(updateStore.currentVersion)（\(updateStore.currentBuild)）"
    }
}
