import Foundation

/// Executes `git` as a subprocess against a specific repository or worktree path.
///
/// Instance-based (bound to one repo path) and asynchronous so it composes cleanly with
/// `async`/`await` call sites, unlike the ad hoc `Process` invocations used elsewhere for git.
///
/// `DiffReviewKit` doesn't import any other module (see `CLAUDE.md`), so this duplicates rather
/// than reuses `ArgusSupport.ProcessRunner`'s fd-handling discipline: drain via `readabilityHandler`
/// while the process runs (a real `git diff` easily exceeds the ~64KB pipe buffer, and reading only
/// after termination would deadlock), then explicitly close both pipes' handles exactly once, on
/// every completion path, instead of leaving fd reclamation to ARC.
public struct GitRunner: Sendable {
    public struct Result: Sendable {
        public let standardOutput: String
        public let standardError: String
        public let exitCode: Int32
        /// True when the run was killed for exceeding its `timeout` (`exitCode` is then -1).
        public let timedOut: Bool

        public var succeeded: Bool { exitCode == 0 && !timedOut }

        public init(standardOutput: String, standardError: String, exitCode: Int32, timedOut: Bool = false) {
            self.standardOutput = standardOutput
            self.standardError = standardError
            self.exitCode = exitCode
            self.timedOut = timedOut
        }
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
    ///
    /// - Parameter timeout: terminates a wedged `git` (lock contention, a stalled network
    ///   filesystem) after this many seconds instead of hanging the caller and its two fds
    ///   forever. Defaults to 10s, generous for any git subcommand this type is asked to run.
    @discardableResult
    public func run(_ arguments: [String], timeout: TimeInterval = 10) async throws -> Result {
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

        return try await withCheckedThrowingContinuation { continuation in
            let completer = Completer(
                continuation: continuation, process: process, stdoutPipe: stdoutPipe, stderrPipe: stderrPipe)

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if !chunk.isEmpty { completer.appendStdout(chunk) }
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if !chunk.isEmpty { completer.appendStderr(chunk) }
            }

            process.terminationHandler = { finished in
                completer.finish(exitCode: finished.terminationStatus)
            }

            let workItem = DispatchWorkItem { completer.finishTimedOut() }
            completer.setTimeoutWorkItem(workItem)
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: workItem)

            do {
                try process.run()
            } catch {
                completer.finishLaunchFailure(error)
            }
        }
    }
}

/// Owns the continuation, the process, and the buffered output for one `run` call — mirrors
/// `ArgusSupport.ProcessRunner`'s `Completer` (see that file for the full rationale). Completion
/// can be signaled from three independent, concurrently-executing sources — `terminationHandler`,
/// the timeout's `DispatchWorkItem`, and the synchronous launch-failure `catch` — so every mutation
/// and the resume-once guard are behind a single lock, and pipe release happens exactly once no
/// matter which source wins.
private final class Completer: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<GitRunner.Result, Error>?
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stdoutData = Data()
    private var stderrData = Data()
    private var timeoutWorkItem: DispatchWorkItem?
    private var didRelease = false

    init(
        continuation: CheckedContinuation<GitRunner.Result, Error>, process: Process, stdoutPipe: Pipe, stderrPipe: Pipe
    ) {
        self.continuation = continuation
        self.process = process
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
    }

    func appendStdout(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        stdoutData.append(chunk)
        lock.unlock()
    }

    func appendStderr(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        stderrData.append(chunk)
        lock.unlock()
    }

    func setTimeoutWorkItem(_ item: DispatchWorkItem) {
        lock.lock()
        timeoutWorkItem = item
        lock.unlock()
    }

    func finish(exitCode: Int32) {
        complete { GitRunner.Result(standardOutput: $0, standardError: $1, exitCode: exitCode) }
    }

    func finishTimedOut() {
        lock.lock()
        let target = process
        lock.unlock()
        if target?.isRunning == true { target?.terminate() }
        complete { GitRunner.Result(standardOutput: $0, standardError: $1, exitCode: -1, timedOut: true) }
    }

    func finishLaunchFailure(_ error: Error) {
        complete { _, _ in throw GitRunner.GitError.launchFailed(error.localizedDescription) }
    }

    /// Resolves the continuation exactly once. Draining and closing the pipes happens here too,
    /// unconditionally, so a caller can never observe a resolved run that still holds its fds open.
    private func complete(_ makeResult: (String, String) throws -> GitRunner.Result) {
        lock.lock()
        guard let pendingContinuation = continuation else {
            lock.unlock()
            return
        }
        continuation = nil
        process = nil
        let workItem = timeoutWorkItem
        let stdout = stdoutPipe
        let stderr = stderrPipe
        lock.unlock()

        workItem?.cancel()

        // Tear down the readability handlers before the final bounded, non-blocking drain — the
        // handler and this drain must never read the same fd concurrently.
        stdout?.fileHandleForReading.readabilityHandler = nil
        stderr?.fileHandleForReading.readabilityHandler = nil
        if let stdout { appendStdout(Self.drainNonBlocking(stdout.fileHandleForReading)) }
        if let stderr { appendStderr(Self.drainNonBlocking(stderr.fileHandleForReading)) }
        releasePipes(stdout, stderr)

        lock.lock()
        let out = String(decoding: stdoutData, as: UTF8.self)
        let err = String(decoding: stderrData, as: UTF8.self)
        lock.unlock()

        do {
            pendingContinuation.resume(returning: try makeResult(out, err))
        } catch {
            pendingContinuation.resume(throwing: error)
        }
    }

    /// Reads whatever is immediately available without blocking, then stops — used only for the
    /// final catch-up drain after the child has already exited (or after a launch failure, when
    /// nothing was ever written). A grandchild that inherited the write end and kept it open past
    /// the parent's exit must never be able to hang this on an EOF that will never arrive.
    private static func drainNonBlocking(_ handle: FileHandle) -> Data {
        let descriptor = handle.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL)
        guard flags != -1 else { return Data() }
        _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)

        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 16384)
        while true {
            let bytesRead = buffer.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
            if bytesRead > 0 {
                result.append(buffer, count: bytesRead)
            } else {
                break  // 0 == EOF; -1 == EAGAIN (nothing available) or a real error — either way, stop.
            }
        }
        return result
    }

    /// Closes both pipes' handles exactly once. Guarded by `didRelease` (rather than relying on
    /// `stdoutPipe`/`stderrPipe` becoming nil) because the three `finish*` entry points race to
    /// call `complete`, and double-closing a fd once its number has been reused elsewhere in the
    /// process is a real correctness hazard, not just a warning.
    private func releasePipes(_ stdout: Pipe?, _ stderr: Pipe?) {
        lock.lock()
        guard !didRelease else {
            lock.unlock()
            return
        }
        didRelease = true
        stdoutPipe = nil
        stderrPipe = nil
        lock.unlock()

        try? stdout?.fileHandleForReading.close()
        try? stdout?.fileHandleForWriting.close()
        try? stderr?.fileHandleForReading.close()
        try? stderr?.fileHandleForWriting.close()
    }
}

extension GitRunner.GitError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "Couldn't find git. Make sure the Xcode Command Line Tools are installed."

        case .launchFailed(let message):
            if message.localizedCaseInsensitiveContains("bad file descriptor")
                || message.localizedCaseInsensitiveContains("too many open files")
            {
                return "Couldn't run git — Argus has run out of file descriptors. Restarting Argus will clear this."
            }
            return "Couldn't run git: \(message)"
        }
    }
}
