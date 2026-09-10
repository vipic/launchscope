import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

@main
struct LaunchScopeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var dashboardStore = DashboardStore()
    @StateObject private var updateStore = AppUpdateStore()

    init() {
        if CommandLine.arguments.contains("--scan-summary") {
            let report = StartupScanner().scan()
            let thirdPartyCount = report.items.count { !$0.isAppleItem }
            let runningCount = report.items.count { $0.runtime.state == .running }
            let duration = String(format: "%.2f", report.duration)
            print("items=\(report.items.count) third_party=\(thirdPartyCount) running=\(runningCount) issues=\(report.issues.count) duration=\(duration)")
            for issue in report.issues {
                print("issue[\(issue.severity.rawValue)] \(issue.source): \(issue.message)")
            }
            exit(report.items.isEmpty ? 1 : 0)
        }
    }

    var body: some Scene {
        WindowGroup {
            DashboardView(store: dashboardStore, updateStore: updateStore)
        }
        .defaultSize(width: 1320, height: 780)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("筛选") {
                Button("全部项目") { dashboardStore.selectFilter(.all) }
                    .keyboardShortcut("1", modifiers: .command)
                    .help("显示所有扫描到的启动项目")
                Button("第三方与自定义") { dashboardStore.selectFilter(.thirdParty) }
                    .keyboardShortcut("2", modifiers: .command)
                    .help("显示非 Apple 的应用、服务和自定义启动配置")
                Button("需要关注") { dashboardStore.selectFilter(.highRisk) }
                    .keyboardShortcut("3", modifiers: .command)
                    .help("显示建议优先核查的启动项目")
                Button("发现与关联") { dashboardStore.selectFilter(.findings) }
                    .keyboardShortcut("4", modifiers: .command)
                    .help("显示重复、残留和多来源关联等核查线索")
            }
        }

        Settings {
            SettingsView(dashboardStore: dashboardStore, updateStore: updateStore)
        }
    }
}
