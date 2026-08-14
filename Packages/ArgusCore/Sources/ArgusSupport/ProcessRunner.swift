import Foundation

/// The outcome of running an external process to completion.
public struct ProcessResult: Sendable, Equatable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String

    public init(exitCode: Int32, standardOutput: String, standardError: String) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    public var succeeded: Bool { exitCode == 0 }
}

/// Runs an external executable to completion and captures its output.
///
/// Replaces the several hand-rolled `Process` wrappers scattered across the app (git, dscl, du,
/// tmux) with a single async entry point.
public enum ProcessRunner {
    /// Runs `executablePath` with `arguments`, waiting for it to exit.
    ///
    /// Never throws: a process that fails to launch (missing binary, bad permissions, ...)
    /// surfaces as exit code `-1` with the launch error's description in `standardError`, matching
    /// the best-effort behavior of the call sites this replaces.
    public static func run(
        _ executablePath: String,
        _ arguments: [String] = [],
        currentDirectory: String? = nil
    ) async -> ProcessResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            if let currentDirectory {
                process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
            }
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            process.terminationHandler = { finished in
                let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(
                    returning: ProcessResult(
                        exitCode: finished.terminationStatus,
                        standardOutput: String(data: outData, encoding: .utf8) ?? "",
                        standardError: String(data: errData, encoding: .utf8) ?? ""
                    )
                )
            }

            do {
                try process.run()
            } catch {
                continuation.resume(
                    returning: ProcessResult(exitCode: -1, standardOutput: "", standardError: "\(error)")
                )
            }
        }
    }
}
