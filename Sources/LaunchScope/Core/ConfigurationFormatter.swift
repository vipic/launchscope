import Foundation

enum ConfigurationFormatter {
    static func string(from value: Any) -> String {
        if let value = value as? String { return value }
        if let value = value as? Bool { return value ? "true" : "false" }
        if let value = value as? NSNumber { return value.stringValue }
        if let date = value as? Date { return ISO8601DateFormatter().string(from: date) }
        if PropertyListSerialization.propertyList(value, isValidFor: .xml),
           let data = try? PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0),
           var text = String(data: data, encoding: .utf8) {
            text = text.replacingOccurrences(of: "\n", with: " ")
            return text
        }
        return String(describing: value)
    }

    static func dictionary(from plist: [String: Any]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: plist.map { ($0.key, string(from: $0.value)) })
    }

    static func keepAliveDescription(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let bool = value as? Bool { return bool ? "始终保持运行" : "否" }
        if let dictionary = value as? [String: Any] {
            return dictionary.keys.sorted().map { key in
                "\(key): \(string(from: dictionary[key] as Any))"
            }.joined(separator: " · ")
        }
        return string(from: value)
    }

    static func scheduleDescription(_ plist: [String: Any]) -> String? {
        var parts: [String] = []
        if let interval = plist["StartInterval"] as? NSNumber {
            parts.append("每 \(interval.intValue) 秒")
        }
        if let calendar = plist["StartCalendarInterval"] {
            parts.append("日历计划：\(string(from: calendar))")
        }
        if let paths = plist["WatchPaths"] as? [String], !paths.isEmpty {
            parts.append("监视路径：\(paths.joined(separator: ", "))")
        }
        if let paths = plist["QueueDirectories"] as? [String], !paths.isEmpty {
            parts.append("队列目录：\(paths.joined(separator: ", "))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
