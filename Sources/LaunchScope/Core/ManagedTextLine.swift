import Foundation
import CryptoKit

enum ManagedTextLine {
    static let marker = "# LaunchScope disabled:v1:"

    static func fingerprint(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func disabledLine(from original: String) -> String {
        marker + Data(original.utf8).base64EncodedString()
    }

    static func originalLine(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(marker),
              let data = Data(base64Encoded: String(trimmed.dropFirst(marker.count))),
              let original = String(data: data, encoding: .utf8) else { return nil }
        return original
    }

    static func replacingLine(
        in text: String,
        lineNumber: Int,
        expectedOriginal: String,
        enable: Bool
    ) throws -> String {
        var lines = text.components(separatedBy: "\n")
        guard lineNumber > 0, lineNumber <= lines.count else { throw ManagedTextLineError.lineChanged }
        let index = lineNumber - 1
        let expected = enable ? disabledLine(from: expectedOriginal) : expectedOriginal
        guard lines[index] == expected else { throw ManagedTextLineError.lineChanged }
        lines[index] = enable ? expectedOriginal : disabledLine(from: expectedOriginal)
        return lines.joined(separator: "\n")
    }
}

enum ManagedTextLineError: LocalizedError {
    case lineChanged
    case invalidEncoding
    case unsafeFile

    var errorDescription: String? {
        switch self {
        case .lineChanged: "目标行已发生变化，已停止操作；请重新扫描后再试。"
        case .invalidEncoding: "配置不是有效的 UTF-8 文本，无法安全修改。"
        case .unsafeFile: "配置文件不是当前用户拥有的普通文件，或路径不在允许范围内。"
        }
    }
}
