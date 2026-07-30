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

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["-C", repositoryPath] + arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw GitError.launchFailed(error.localizedDescription)
        }

        // Drain both pipes concurrently while the process is still running. A pipe's kernel
        // buffer is only ~64KB — a real `git diff` easily exceeds that, and reading only after
        // termination deadlocks: git blocks on write() waiting for buffer space that never frees
        // because nothing is reading it, so it never terminates.
        async let stdoutData = Self.readToEnd(stdoutPipe)
        async let stderrData = Self.readToEnd(stderrPipe)
        let (outData, errData) = await (stdoutData, stderrData)

        process.waitUntilExit()

        return Result(
            standardOutput: String(data: outData, encoding: .utf8) ?? "",
            standardError: String(data: errData, encoding: .utf8) ?? "",
            exitCode: process.terminationStatus
        )
    }

    private static func readToEnd(_ pipe: Pipe) async -> Data {
        await Task.detached {
            pipe.fileHandleForReading.readDataToEndOfFile()
        }.value
    }
}
