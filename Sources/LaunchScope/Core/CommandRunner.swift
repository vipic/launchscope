import Foundation

struct CommandResult: Sendable {
    var standardOutput: String
    var standardError: String
    var exitCode: Int32
    var timedOut: Bool
}

protocol CommandRunning: Sendable {
    func run(executable: String, arguments: [String], timeout: TimeInterval) -> CommandResult
}

struct CommandRunner: CommandRunning {
    func run(executable: String, arguments: [String], timeout: TimeInterval = 5) -> CommandResult {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            return CommandResult(
                standardOutput: "",
                standardError: "命令不存在或不可执行：\(executable)",
                exitCode: 127,
                timedOut: false
            )
        }

        let process = Process()
        let termination = DispatchSemaphore(value: 0)
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("launchscope-command-\(UUID().uuidString)", isDirectory: true)
        let outputURL = temporaryDirectory.appendingPathComponent("stdout")
        let errorURL = temporaryDirectory.appendingPathComponent("stderr")

        do {
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: outputURL.path, contents: nil)
            FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        } catch {
            return CommandResult(
                standardOutput: "",
                standardError: "无法创建命令输出临时目录：\(error.localizedDescription)",
                exitCode: 126,
                timedOut: false
            )
        }
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        guard let outputHandle = try? FileHandle(forWritingTo: outputURL),
              let errorHandle = try? FileHandle(forWritingTo: errorURL) else {
            return CommandResult(
                standardOutput: "",
                standardError: "无法打开命令输出临时文件",
                exitCode: 126,
                timedOut: false
            )
        }

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = outputHandle
        process.standardError = errorHandle
        process.terminationHandler = { _ in termination.signal() }

        do {
            try process.run()
        } catch {
            try? outputHandle.close()
            try? errorHandle.close()
            return CommandResult(
                standardOutput: "",
                standardError: error.localizedDescription,
                exitCode: 126,
                timedOut: false
            )
        }

        let waitResult = termination.wait(timeout: .now() + timeout)
        let timedOut = waitResult == .timedOut
        if timedOut {
            process.terminate()
            if termination.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = termination.wait(timeout: .now() + 1)
            }
        }

        try? outputHandle.close()
        try? errorHandle.close()
        let stdout = (try? Data(contentsOf: outputURL)) ?? Data()
        let stderr = (try? Data(contentsOf: errorURL)) ?? Data()

        return CommandResult(
            standardOutput: String(data: stdout, encoding: .utf8) ?? "",
            standardError: String(data: stderr, encoding: .utf8) ?? "",
            exitCode: timedOut ? 124 : process.terminationStatus,
            timedOut: timedOut
        )
    }
}
