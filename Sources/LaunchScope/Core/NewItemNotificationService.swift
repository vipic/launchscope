import Foundation
import UserNotifications

@MainActor
protocol NewItemNotifying {
    func requestAuthorization() async throws -> Bool
    func notify(newItems: [ScanSnapshotItem]) async throws
}

@MainActor
struct NewItemNotificationService: NewItemNotifying {
    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    func notify(newItems: [ScanSnapshotItem]) async throws {
        guard !newItems.isEmpty else { return }
        let content = UNMutableNotificationContent()
        content.title = "发现新的启动项目"
        if newItems.count == 1, let item = newItems.first {
            content.body = "\(item.displayName) 是新的第三方项目，尚未加入信任名单。"
        } else {
            content.body = "发现 \(newItems.count) 个新的第三方项目，均尚未加入信任名单。"
        }
        content.sound = .default
        let request = UNNotificationRequest(identifier: "launchscope.new-untrusted-items", content: content, trigger: nil)
        try await UNUserNotificationCenter.current().add(request)
    }
}
