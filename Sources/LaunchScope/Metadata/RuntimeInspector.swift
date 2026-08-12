import Foundation

struct RuntimeInspector: Sendable {
    var runner: any CommandRunning = CommandRunner()

    func snapshot(domains: Set<String>) -> [String: [String: RuntimeInfo]] {
        domains.reduce(into: [:]) { result, domain in
            let command = runner.run(
                executable: "/bin/launchctl",
                arguments: ["print", domain],
                timeout: 4
            )
            guard command.exitCode == 0 else {
                result[domain] = [:]
                return
            }
            result[domain] = Self.parseServices(command.standardOutput, domain: domain)
        }
    }

    static func parseServices(_ text: String, domain: String) -> [String: RuntimeInfo] {
        var services: [String: RuntimeInfo] = [:]
        var insideServices = false

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "services = {" {
                insideServices = true
                continue
            }
            if insideServices, trimmed == "}" { break }
            guard insideServices else { continue }

            let parts = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count >= 3, let rawPID = Int32(parts[0]) else { continue }
            let label = parts.last ?? ""
            guard !label.isEmpty else { continue }
            let rawExitCode = Int32(parts[1])
            services[label] = RuntimeInfo(
                state: rawPID > 0 ? .running : .loaded,
                processIdentifier: rawPID > 0 ? rawPID : nil,
                lastExitCode: rawExitCode,
                domain: domain
            )
        }
        return services
    }

    static func capture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range]).trimmingCharacters(in: .whitespaces)
    }
}
