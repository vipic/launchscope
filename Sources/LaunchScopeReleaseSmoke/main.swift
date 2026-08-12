import AppKit
import Foundation

let arguments = CommandLine.arguments
guard let bundleIdentifier = argumentValue(after: "--bundle-id"),
      let pidText = argumentValue(after: "--pid"),
      let processIdentifier = pid_t(pidText),
      let application = NSRunningApplication(processIdentifier: processIdentifier) else {
    fputs("用法：LaunchScopeReleaseSmoke --bundle-id <id> --pid <pid>\n", stderr)
    exit(1)
}

guard waitForApplicationLaunch(application, timeout: 20) else {
    fputs("LaunchScope 进程未在时限内完成应用启动。\n", stderr)
    exit(1)
}
guard application.bundleIdentifier == bundleIdentifier else {
    fputs("正式应用 bundle id 不匹配。\n", stderr)
    exit(1)
}
guard application.activationPolicy == .regular else {
    fputs("正式应用未以 Dock 常规应用策略运行。\n", stderr)
    exit(1)
}
guard let icon = application.icon, icon.size.width > 0, icon.size.height > 0 else {
    fputs("正式应用未加载 Dock 图标。\n", stderr)
    exit(1)
}
guard let window = waitForVisibleWindow(processIdentifier: processIdentifier, timeout: 20) else {
    fputs("正式应用首次启动后未出现可见主窗口。\n", stderr)
    exit(1)
}

print(
    "正式应用验收通过：首次启动出现 \(Int(window.width))×\(Int(window.height)) 主窗口，" +
    "Dock 策略为 regular，图标尺寸 \(Int(icon.size.width))×\(Int(icon.size.height))。"
)

private func argumentValue(after option: String) -> String? {
    guard let index = arguments.firstIndex(of: option), arguments.indices.contains(index + 1) else { return nil }
    return arguments[index + 1]
}

private func waitForApplicationLaunch(_ application: NSRunningApplication, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if application.isTerminated { return false }
        if application.isFinishedLaunching { return true }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    } while Date() < deadline
    return false
}

private func waitForVisibleWindow(processIdentifier: pid_t, timeout: TimeInterval) -> CGRect? {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        for window in windows {
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == processIdentifier,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds),
                  rect.width > 0, rect.height > 0 else { continue }
            return rect
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    } while Date() < deadline
    return nil
}
