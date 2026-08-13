import SwiftUI

struct SettingsView: View {
    @ObservedObject var dashboardStore: DashboardStore
    @ObservedObject var updateStore: AppUpdateStore
    @AppStorage(PreferenceKeys.hideAppleItems) private var hideAppleItems = true
    @AppStorage(PreferenceKeys.hideTrustedItems) private var hideTrustedItems = false
    @AppStorage(PreferenceKeys.groupByOwner) private var groupByOwner = true
    @AppStorage(PreferenceKeys.showSensitiveValues) private var showSensitiveValues = false
    @AppStorage(PreferenceKeys.automaticallyCheckForUpdates) private var automaticallyCheckForUpdates = true

    var body: some View {
        TabView {
            Form {
                Section("列表") {
                    Toggle("按所属应用归组", isOn: $groupByOwner)
                        .accessibilityIdentifier("settings.group-by-owner")
                    Toggle("隐藏 Apple 项目", isOn: $hideAppleItems)
                        .accessibilityIdentifier("settings.hide-apple-items")
                    Toggle("隐藏已信任项目", isOn: $hideTrustedItems)
                        .accessibilityIdentifier("settings.hide-trusted-items")
                }
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
                Section("新增项目提醒") {
                    Toggle("提醒新增的第三方未信任项目", isOn: Binding(
                        get: { dashboardStore.notificationsEnabled },
                        set: { dashboardStore.setNotificationsEnabled($0) }
                    ))
                    .accessibilityIdentifier("settings.notifications")
                    Text("只有在你主动开启并授予系统通知权限后才会发送；相同变化不会重复提醒。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let error = dashboardStore.notificationError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(LaunchScopePalette.warning)
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("通知", systemImage: "bell") }

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
                            .disabled(updateStore.state == .checking)
                            .accessibilityIdentifier("settings.check-for-updates")
                        if case let .updateAvailable(release) = updateStore.state {
                            Link("打开下载页", destination: release.pageURL)
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("settings.open-update-page")
                        }
                    }
                }
                Section {
                    Text("LaunchScope 只检查 GitHub 上的最新正式版本，不会静默下载或替换应用。下载后请核对 DMG 附带的 SHA-256 文件。")
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
                Text("macOS 启动项审计面板")
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
        case .upToDate:
            Label("当前已是最新版本", systemImage: "checkmark.circle.fill")
                .foregroundStyle(LaunchScopePalette.healthy)
        case let .updateAvailable(release):
            Label("发现新版本 \(release.version)：\(release.title)", systemImage: "arrow.down.circle.fill")
                .foregroundStyle(LaunchScopePalette.accent)
        case let .failed(message):
            Label("检查失败：\(message)", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(LaunchScopePalette.warning)
        }
    }

    private var versionDescription: String {
        "\(updateStore.currentVersion)（\(updateStore.currentBuild)）"
    }
}
