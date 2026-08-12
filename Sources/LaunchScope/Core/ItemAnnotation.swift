import Foundation

struct ItemAnnotation: Codable, Equatable, Sendable {
    var itemKey: String
    var note: String
    var tags: [String]
    var isTrusted: Bool
    var updatedAt: Date
}

extension StartupItem {
    /// A stable key that deliberately omits paths, arguments and configuration values.
    var privacySafeKey: String { "\(source.rawValue):\(label)" }
}
