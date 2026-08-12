import AppKit
import ApplicationServices
import Foundation

private let bundleIdentifier = "com.nekutai.launchscope.dev"
private let requiredIdentifiers = [
    "sidebar.thirdParty",
    "sidebar.highRisk",
    "toolbar.refresh",
    "toolbar.audit-timeline",
]

let trustOptions = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
guard AXIsProcessTrustedWithOptions(trustOptions) else {
    fputs("UI 冒烟需要为当前终端或 Codex 授予“系统设置 > 隐私与安全性 > 辅助功能”权限。\n", stderr)
    exit(77)
}

guard let application = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
    fputs("未找到已运行的 LaunchScope Dev.app；请先执行 mise run deploy。\n", stderr)
    exit(1)
}

let root = AXUIElementCreateApplication(application.processIdentifier)
if CommandLine.arguments.contains("--release-acceptance") {
    runReleaseAcceptance(root: root)
} else if CommandLine.arguments.contains("--notification-acceptance") {
    press(waitForIdentifier("toolbar.display-options", root: root, timeout: 10), description: "显示选项")
    verifyNotificationAuthorization(root: root)
} else {
    let discovered = waitForIdentifiers(requiredIdentifiers, root: root, timeout: 10)
    let missing = requiredIdentifiers.filter { discovered[$0] == nil }
    guard missing.isEmpty else {
        fputs("UI 冒烟未找到控件：\(missing.joined(separator: "、"))\n", stderr)
        exit(1)
    }
    press(discovered["sidebar.highRisk"]!, description: "高风险筛选")
    print("UI 冒烟通过：主导航、风险筛选、刷新与审计时间线控件均可访问。")
}

private func runReleaseAcceptance(root: AXUIElement) {
    let acceptanceItems = [
        ("LaunchAgent", "定位 LaunchAgent", "disable", "enable"),
        ("Homebrew", "定位 Homebrew", "stopHomebrew", "startHomebrew"),
        ("Cron", "定位 Cron", "disableCron", "enableCron"),
        ("Shell", "定位 Shell", "disableShellLine", "enableShellLine"),
    ]

    press(waitForIdentifier("sidebar.thirdParty", root: root, timeout: 10), description: "第三方筛选")
    press(waitForIdentifier("toolbar.refresh", root: root, timeout: 10), description: "重新扫描")
    RunLoop.current.run(until: Date().addingTimeInterval(2))
    for (name, locatorTitle, disable, enable) in acceptanceItems {
        press(waitForIdentifier("toolbar.acceptance", root: root, timeout: 10), description: "验收定位菜单")
        press(waitForTitle(locatorTitle, root: root, timeout: 10), description: locatorTitle)
        performControl(action: disable, name: name, root: root)
        performControl(action: enable, name: name, root: root)
        print("UI 验收通过：\(name) 停用、复扫与恢复")
    }

    press(waitForIdentifier("toolbar.recovery", root: root, timeout: 10), description: "恢复中心")
    _ = waitForTitle("恢复中心", root: root, timeout: 10)
    press(waitForTitle("完成", root: root, timeout: 10), description: "关闭恢复中心")

    press(waitForIdentifier("toolbar.export", root: root, timeout: 10), description: "导出审计报告")
    _ = waitForTitle("导出脱敏审计报告", root: root, timeout: 10)
    press(waitForTitle("取消", root: root, timeout: 10), description: "关闭导出面板")

    press(waitForIdentifier("toolbar.display-options", root: root, timeout: 10), description: "显示选项")
    verifyNotificationAuthorization(root: root)

    print("发布 UI 验收通过：四类控制、恢复中心、导出入口与通知设置均可访问。")
}

private func verifyNotificationAuthorization(root: AXUIElement) {
    var toggle = waitForIdentifier("settings.notifications", root: root, timeout: 10)
    if boolAttribute(kAXValueAttribute, of: toggle) != true {
        press(toggle, description: "开启新增项目通知")
        if let allow = waitForSystemTitle(["允许", "Allow"], timeout: 6) {
            press(allow, description: "允许系统通知")
        }
        if !waitForNotificationPreference(enabled: true, timeout: 8) {
            let error = waitForIdentifier("settings.notification-error", root: root, timeout: 10)
            let expected = "系统未授予通知权限，新增项目提醒未开启。"
            guard [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute]
                .contains(where: { stringAttribute($0, of: error) == expected }) else {
                fputs("通知权限拒绝说明与预期不符。\n", stderr)
                exit(1)
            }
            press(waitForIdentifier("settings.notification-error-dismiss", root: root, timeout: 10), description: "关闭通知权限说明")
            print("通知拒绝态验收通过：应用保持提醒关闭并显示系统权限指引。")
            return
        }
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        press(waitForIdentifier("toolbar.display-options", root: root, timeout: 10), description: "重新打开显示选项")
        toggle = waitForIdentifier("settings.notifications", root: root, timeout: 10)
    }
    press(toggle, description: "恢复通知默认关闭")
    guard waitForNotificationPreference(enabled: false, timeout: 8) else {
        fputs("通知验收结束后未恢复默认关闭。\n", stderr)
        exit(1)
    }
    print("通知授权验收通过：系统已授权，应用内提醒已恢复默认关闭。")
}

private func waitForNotificationPreference(enabled: Bool, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        CFPreferencesAppSynchronize(bundleIdentifier as CFString)
        if let value = CFPreferencesCopyAppValue(
            "notify_new_untrusted_items" as CFString,
            bundleIdentifier as CFString
        ) as? NSNumber, value.boolValue == enabled {
            return true
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    } while Date() < deadline
    return false
}

private func waitForSystemTitle(_ titles: Set<String>, timeout: TimeInterval) -> AXUIElement? {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        for application in NSWorkspace.shared.runningApplications where !application.isTerminated {
            let candidateRoot = AXUIElementCreateApplication(application.processIdentifier)
            for title in titles {
                if let element = accessibilityElement(root: candidateRoot, title: title) { return element }
            }
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    } while Date() < deadline
    return nil
}

private func boolAttribute(_ name: String, of element: AXUIElement) -> Bool? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    if let number = value as? NSNumber { return number.boolValue }
    if let string = value as? String {
        if ["1", "true", "yes"].contains(string.lowercased()) { return true }
        if ["0", "false", "no"].contains(string.lowercased()) { return false }
    }
    return nil
}

private func performControl(action: String, name: String, root: AXUIElement) {
    press(waitForControl(action: action, root: root, timeout: 25), description: "\(name) \(action)")
    press(waitForIdentifier("confirmation.control", root: root, timeout: 10), description: "\(name) 二次确认")
    let dismissal = waitForTitle("好", root: root, timeout: 35)
    let resultTexts = nearbyText(of: dismissal)
    print("\(name) 操作结果：\(resultTexts.joined(separator: " · "))")
    press(dismissal, description: "\(name) 操作结果")
}

private func nearbyText(of element: AXUIElement) -> [String] {
    var container = element
    for _ in 0..<1 {
        var parent: CFTypeRef?
        guard AXUIElementCopyAttributeValue(container, kAXParentAttribute as CFString, &parent) == .success,
              let parent else { break }
        container = parent as! AXUIElement
    }
    var values: [String] = []
    var queue: [(AXUIElement, Int)] = [(container, 0)]
    var index = 0
    while index < queue.count {
        let (current, depth) = queue[index]
        index += 1
        for attribute in [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute] {
            if let value = stringAttribute(attribute, of: current), !value.isEmpty, !values.contains(value) {
                values.append(value)
            }
        }
        guard depth < 5 else { continue }
        var childrenValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(current, kAXChildrenAttribute as CFString, &childrenValue) == .success,
           let children = childrenValue as? [AXUIElement] {
            queue.append(contentsOf: children.map { ($0, depth + 1) })
        }
    }
    return values
}

private func waitForControl(action: String, root: AXUIElement, timeout: TimeInterval) -> AXUIElement {
    let titles = [
        "disable": "停用",
        "enable": "恢复启用",
        "stopHomebrew": "停止服务",
        "startHomebrew": "启动服务",
        "disableCron": "安全停用",
        "enableCron": "恢复启用",
        "disableShellLine": "安全停用",
        "enableShellLine": "恢复启用",
    ]
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if let element = accessibilityElements(root: root, identifiers: ["control.\(action)"])["control.\(action)"] {
            return element
        }
        if let title = titles[action], let element = accessibilityElement(root: root, title: title) {
            return element
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    } while Date() < deadline
    fputs("UI 验收未找到控制动作：\(action)\n", stderr)
    exit(1)
}

private func press(_ element: AXUIElement, description: String) {
    let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
    guard result == .success else {
        fputs("无法执行 \(description)：\(result.rawValue)\n", stderr)
        exit(1)
    }
    RunLoop.current.run(until: Date().addingTimeInterval(0.15))
}

private func waitForIdentifiers(
    _ identifiers: [String], root: AXUIElement, timeout: TimeInterval
) -> [String: AXUIElement] {
    let deadline = Date().addingTimeInterval(timeout)
    var discovered: [String: AXUIElement] = [:]
    repeat {
        discovered = accessibilityElements(root: root, identifiers: Set(identifiers))
        if identifiers.allSatisfy({ discovered[$0] != nil }) { return discovered }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    } while Date() < deadline
    return discovered
}

private func waitForIdentifier(
    _ identifier: String, root: AXUIElement, timeout: TimeInterval
) -> AXUIElement {
    if let element = waitForIdentifiers([identifier], root: root, timeout: timeout)[identifier] { return element }
    fputs("UI 验收未找到控件：\(identifier)\n", stderr)
    exit(1)
}

private func waitForTitle(_ title: String, root: AXUIElement, timeout: TimeInterval) -> AXUIElement {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if let element = accessibilityElement(root: root, title: title) { return element }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    } while Date() < deadline
    fputs("UI 验收未找到标题：\(title)\n", stderr)
    exit(1)
}

private func accessibilityElements(
    root: AXUIElement,
    identifiers: Set<String>
) -> [String: AXUIElement] {
    var found: [String: AXUIElement] = [:]
    var queue: [(AXUIElement, Int)] = [(root, 0)]
    var index = 0
    while index < queue.count, found.count < identifiers.count {
        let (element, depth) = queue[index]
        index += 1
        if let identifier = stringAttribute(kAXIdentifierAttribute, of: element), identifiers.contains(identifier) {
            found[identifier] = element
        }
        guard depth < 14 else { continue }
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
           let children = value as? [AXUIElement] {
            queue.append(contentsOf: children.map { ($0, depth + 1) })
        }
    }
    return found
}

private func stringAttribute(_ name: String, of element: AXUIElement) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value as? String
}

private func accessibilityElement(root: AXUIElement, title: String) -> AXUIElement? {
    var queue: [(AXUIElement, Int)] = [(root, 0)]
    var index = 0
    while index < queue.count {
        let (element, depth) = queue[index]
        index += 1
        let matches = [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute]
            .contains { stringAttribute($0, of: element) == title }
        if matches { return element }
        guard depth < 14 else { continue }
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
           let children = value as? [AXUIElement] {
            queue.append(contentsOf: children.map { ($0, depth + 1) })
        }
    }
    return nil
}
