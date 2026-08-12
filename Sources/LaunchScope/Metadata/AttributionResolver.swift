import AppKit
import Foundation

struct AttributionRecord: Sendable {
    var displayName: String?
    var bundleIdentifiers: [String]
    var teamIdentifier: String?
}

struct AttributionResolver: Sendable {
    private let records: [String: AttributionRecord]

    init(attributionsPath: String = "/System/Library/PrivateFrameworks/BackgroundTaskManagement.framework/Versions/A/Resources/attributions.plist") {
        records = Self.loadRecords(path: attributionsPath)
    }

    func resolve(item: StartupItem) -> AppAttribution? {
        if let existing = item.attribution,
           existing.displayName != nil || existing.bundleIdentifier != nil || existing.bundlePath != nil {
            return existing
        }

        if let record = records[item.label] {
            let bundleIdentifier = record.bundleIdentifiers.first
            let bundleURL = bundleIdentifier.flatMap {
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
            }
            return AppAttribution(
                displayName: record.displayName,
                bundleIdentifier: bundleIdentifier,
                bundlePath: bundleURL?.path,
                iconPath: bundleURL?.path,
                source: "Apple 归因表"
            )
        }

        if let executable = item.executablePath,
           PathAccessPolicy.canProbeMetadata(at: executable),
           let appURL = Self.enclosingAppURL(path: executable),
           let bundle = Bundle(url: appURL) {
            return AppAttribution(
                displayName: (bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String)
                    ?? (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
                    ?? (bundle.infoDictionary?["CFBundleName"] as? String)
                    ?? appURL.deletingPathExtension().lastPathComponent,
                bundleIdentifier: bundle.bundleIdentifier,
                bundlePath: appURL.path,
                iconPath: appURL.path,
                source: "可执行文件所属 App Bundle"
            )
        }

        if let identifier = item.signature.identifier,
           let bundleURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier),
           let bundle = Bundle(url: bundleURL) {
            return AppAttribution(
                displayName: (bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String)
                    ?? (bundle.infoDictionary?["CFBundleName"] as? String),
                bundleIdentifier: identifier,
                bundlePath: bundleURL.path,
                iconPath: bundleURL.path,
                source: "代码签名标识"
            )
        }
        return nil
    }

    static func loadRecords(path: String) -> [String: AttributionRecord] {
        guard let data = FileManager.default.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = plist as? [String: [String: Any]] else { return [:] }

        return dictionary.reduce(into: [:]) { result, pair in
            result[pair.key] = AttributionRecord(
                displayName: pair.value["Attribution"] as? String,
                bundleIdentifiers: pair.value["AssociatedBundleIdentifiers"] as? [String] ?? [],
                teamIdentifier: pair.value["TeamIdentifier"] as? String
            )
        }
    }

    static func enclosingAppURL(path: String) -> URL? {
        var url = URL(fileURLWithPath: path).standardizedFileURL
        var outermostApp: URL?
        while url.path != "/" {
            if url.pathExtension.lowercased() == "app" { outermostApp = url }
            url.deleteLastPathComponent()
        }
        return outermostApp
    }
}
