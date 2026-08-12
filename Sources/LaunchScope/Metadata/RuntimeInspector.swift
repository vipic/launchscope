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

    func disabledServices(domains: Set<String>) -> [String: [String: Bool]] {
        domains.reduce(into: [:]) { result, domain in
            let command = runner.run(
                executable: "/bin/launchctl",
                arguments: ["print-disabled", domain],
                timeout: 4
            )
            guard command.exitCode == 0 else {
                result[domain] = [:]
                return
            }
            result[domain] = Self.parseDisabledServices(command.standardOutput)
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

    static func parseDisabledServices(_ text: String) -> [String: Bool] {
        var services: [String: Bool] = [:]
        let pattern = #"^\s*\"([^\"]+)\"\s*=>\s*(enabled|disabled)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            return services
        }
        let range = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, range: range) {
            guard let labelRange = Range(match.range(at: 1), in: text),
                  let stateRange = Range(match.range(at: 2), in: text) else { continue }
            services[String(text[labelRange])] = text[stateRange] == "disabled"
        }
        return services
    }
}
