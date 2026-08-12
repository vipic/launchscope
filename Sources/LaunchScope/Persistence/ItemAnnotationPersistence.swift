import Foundation

protocol ItemAnnotationPersisting: Sendable {
    func load() throws -> [ItemAnnotation]
    func save(_ annotations: [ItemAnnotation]) throws
}

struct ItemAnnotationPersistence: ItemAnnotationPersisting, Sendable {
    var fileURL: URL

    init(fileURL: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.fileURL = fileURL ?? base
            .appendingPathComponent("LaunchScope", isDirectory: true)
            .appendingPathComponent("item-annotations.json")
    }

    func load() throws -> [ItemAnnotation] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ItemAnnotation].self, from: Data(contentsOf: fileURL))
    }

    func save(_ annotations: [ItemAnnotation]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(annotations).write(to: fileURL, options: .atomic)
    }
}
