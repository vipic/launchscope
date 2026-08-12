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
let deadline = Date().addingTimeInterval(10)
var discovered: [String: AXUIElement] = [:]
repeat {
    discovered = accessibilityElements(root: root, identifiers: Set(requiredIdentifiers))
    if requiredIdentifiers.allSatisfy({ discovered[$0] != nil }) { break }
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
} while Date() < deadline

let missing = requiredIdentifiers.filter { discovered[$0] == nil }
guard missing.isEmpty else {
    fputs("UI 冒烟未找到控件：\(missing.joined(separator: "、"))\n", stderr)
    exit(1)
}

if let highRisk = discovered["sidebar.highRisk"] {
    let result = AXUIElementPerformAction(highRisk, kAXPressAction as CFString)
    guard result == .success else {
        fputs("无法通过辅助功能执行高风险筛选：\(result.rawValue)\n", stderr)
        exit(1)
    }
}

print("UI 冒烟通过：主导航、风险筛选、刷新与审计时间线控件均可访问。")

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
