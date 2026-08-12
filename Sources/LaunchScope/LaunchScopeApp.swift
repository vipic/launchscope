import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct LaunchScopeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var dashboardStore = DashboardStore()

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
            DashboardView(store: dashboardStore)
        }
        .defaultSize(width: 1320, height: 780)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
