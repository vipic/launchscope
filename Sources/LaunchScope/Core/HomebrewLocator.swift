import Foundation

enum HomebrewLocator {
    static func executablePath() -> String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        })
    }
}
