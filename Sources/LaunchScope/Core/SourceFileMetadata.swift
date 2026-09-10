import Foundation

struct SourceFileMetadata: Sendable {
    var createdAt: Date?
    var modifiedAt: Date?

    static func read(path: String?) -> SourceFileMetadata {
        guard let path, path.hasPrefix("/"),
              let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
            return SourceFileMetadata()
        }
        return SourceFileMetadata(
            createdAt: attributes[.creationDate] as? Date,
            modifiedAt: attributes[.modificationDate] as? Date
        )
    }
}
