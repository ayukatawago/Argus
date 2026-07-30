import Foundation

/// Executes `git` as a subprocess against a specific repository or worktree path.
///
/// Instance-based (bound to one repo path) and asynchronous so it composes cleanly with
/// `async`/`await` call sites, unlike the ad hoc `Process` invocations used elsewhere for git.
public struct GitRunner: Sendable {
    public struct Result: Sendable {
        public let standardOutput: String
        public let standardError: String
        public let exitCode: Int32

        public var succeeded: Bool { exitCode == 0 }
    }

    public enum GitError: Error, Sendable {
        case executableNotFound
        case launchFailed(String)
    }

    /// Absolute path to the repository or worktree the runner operates on.
    public let repositoryPath: String

    /// Path to the `git` executable. Defaults to the standard Xcode Command Line Tools location.
    public var executablePath: String

    public init(repositoryPath: String, executablePath: String = "/usr/bin/git") {
        self.repositoryPath = repositoryPath
        self.executablePath = executablePath
    }

    /// Runs `git -C <repositoryPath> <arguments>` and returns the captured output.
    ///
    /// Non-zero exit codes are reported via `Result.succeeded`/`exitCode`, not thrown — many git
    /// subcommands use exit code 1 to mean "no match" rather than "error" (e.g. `--no-index`).
    @discardableResult
    public func run(_ arguments: [String]) async throws -> Result {
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw GitError.executableNotFound
        }
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = ["-C", repositoryPath] + arguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            process.terminationHandler = { finished in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(
                    returning: Result(
                        standardOutput: String(data: stdoutData, encoding: .utf8) ?? "",
                        standardError: String(data: stderrData, encoding: .utf8) ?? "",
                        exitCode: finished.terminationStatus
                    )
                )
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: GitError.launchFailed(error.localizedDescription))
            }
        }
    }
}
