import Foundation

struct AppVersion: Comparable, Equatable, Sendable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ value: String) {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingPrefix("v")
            .split(separator: "-", maxSplits: 1)
            .first?
            .split(separator: ".") ?? []
        guard normalized.count == 3,
              let major = Int(normalized[0]),
              let minor = Int(normalized[1]),
              let patch = Int(normalized[2]),
              major >= 0, minor >= 0, patch >= 0 else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

struct AppRelease: Equatable, Sendable {
    let version: String
    let title: String
    let pageURL: URL
}

enum AppUpdateError: LocalizedError, Equatable {
    case invalidResponse
    case invalidRelease
    case unsupportedCurrentVersion(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "更新服务返回了无效响应。"
        case .invalidRelease:
            return "最新发布信息不完整。"
        case let .unsupportedCurrentVersion(version):
            return "无法识别当前版本：\(version)"
        }
    }
}

protocol AppUpdateChecking: Sendable {
    func latestRelease() async throws -> AppRelease
}

struct GitHubAppUpdateChecker: AppUpdateChecking {
    static let releasesURL = URL(string: "https://github.com/vipic/launchscope/releases")!
    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/vipic/launchscope/releases/latest")!

    func latestRelease() async throws -> AppRelease {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.timeoutInterval = 10
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("LaunchScope", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            throw AppUpdateError.invalidResponse
        }
        return try Self.decodeRelease(from: data)
    }

    static func decodeRelease(from data: Data) throws -> AppRelease {
        struct Payload: Decodable {
            let tagName: String
            let name: String?
            let htmlURL: URL

            enum CodingKeys: String, CodingKey {
                case tagName = "tag_name"
                case name
                case htmlURL = "html_url"
            }
        }

        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw AppUpdateError.invalidRelease
        }
        guard AppVersion(payload.tagName) != nil,
              payload.htmlURL.scheme == "https",
              payload.htmlURL.host == "github.com",
              payload.htmlURL.path.hasPrefix("/vipic/launchscope/releases/") else {
            throw AppUpdateError.invalidRelease
        }
        let version = String(payload.tagName.trimmingPrefix("v"))
        return AppRelease(
            version: version,
            title: payload.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "LaunchScope \(version)",
            pageURL: payload.htmlURL
        )
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
