import Foundation

struct ResourceObservation: Equatable, Sendable {
    var processIdentifier: Int32
    var cpuPercent: Double
    var residentMemoryBytes: UInt64
    var elapsedSeconds: TimeInterval
}

enum ResourceObservationParser {
    static func parse(_ text: String) -> [Int32: ResourceObservation] {
        Dictionary(uniqueKeysWithValues: text.split(separator: "\n").compactMap { line in
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 4,
                  let pid = Int32(fields[0]),
                  let cpu = Double(fields[1]),
                  let kilobytes = UInt64(fields[2]),
                  let elapsed = parseElapsed(String(fields[3])) else { return nil }
            return (pid, ResourceObservation(
                processIdentifier: pid,
                cpuPercent: max(0, cpu),
                residentMemoryBytes: kilobytes * 1_024,
                elapsedSeconds: elapsed
            ))
        })
    }

    private static func parseElapsed(_ value: String) -> TimeInterval? {
        let dayParts = value.split(separator: "-", maxSplits: 1).map(String.init)
        let days: Int
        let clock: String
        if dayParts.count == 2 {
            guard let parsed = Int(dayParts[0]) else { return nil }
            days = parsed
            clock = dayParts[1]
        } else {
            days = 0
            clock = value
        }
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 || parts.count == 3 else { return nil }
        let hours = parts.count == 3 ? parts[0] : 0
        let minutes = parts.count == 3 ? parts[1] : parts[0]
        let seconds = parts.count == 3 ? parts[2] : parts[1]
        return TimeInterval(days * 86_400 + hours * 3_600 + minutes * 60 + seconds)
    }
}

struct ResourceObserver: Sendable {
    var runner: any CommandRunning = CommandRunner()

    func observe(processIdentifiers: Set<Int32>) -> [Int32: ResourceObservation] {
        guard !processIdentifiers.isEmpty else { return [:] }
        let pidList = processIdentifiers.sorted().map(String.init).joined(separator: ",")
        let result = runner.run(
            executable: "/bin/ps",
            arguments: ["-p", pidList, "-o", "pid=,%cpu=,rss=,etime="],
            timeout: 3
        )
        guard result.exitCode == 0 else { return [:] }
        return ResourceObservationParser.parse(result.standardOutput)
    }
}
