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
    ///
    /// Output is drained via `readabilityHandler` as the child produces it, rather than only after
    /// it exits — a child that writes more than the 64KB pipe buffer before finishing would
    /// otherwise deadlock (it blocks on the full pipe, `terminationHandler` never fires, the
    /// continuation never resumes).
    ///
    /// `timeout`, if provided, terminates the child and resolves with exit code `-1` if it hasn't
    /// exited by then, so a wedged child (lock contention, a stalled network filesystem) can't hang
    /// the caller forever. `nil` (the default) waits indefinitely, matching prior behavior.
    public static func run(
        _ executablePath: String,
        _ arguments: [String] = [],
        currentDirectory: String? = nil,
        timeout: TimeInterval? = nil
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

            let completer = Completer(continuation: continuation, stdoutPipe: stdoutPipe, stderrPipe: stderrPipe)

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if !chunk.isEmpty { completer.appendStdout(chunk) }
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if !chunk.isEmpty { completer.appendStderr(chunk) }
            }

            process.terminationHandler = { finished in
                // Catches any bytes written between the last readabilityHandler firing and exit.
                completer.appendStdout(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
                completer.appendStderr(stderrPipe.fileHandleForReading.readDataToEndOfFile())
                completer.finish(exitCode: finished.terminationStatus)
            }

            if let timeout {
                let workItem = DispatchWorkItem {
                    if process.isRunning { process.terminate() }
                    completer.finish(exitCode: -1)
                }
                completer.setTimeoutWorkItem(workItem)
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: workItem)
            }

            do {
                try process.run()
            } catch {
                completer.finishLaunchFailure(error)
            }
        }
    }
}

/// Owns the continuation and buffered output for one `run` call. Completion can be signaled from
/// three independent, concurrently-executing sources — `terminationHandler`, the timeout's
/// `DispatchWorkItem`, and the synchronous launch-failure `catch` — so every mutation and the
/// resume-once guard are behind a single lock.
private final class Completer: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ProcessResult, Never>?
    private let stdoutPipe: Pipe
    private let stderrPipe: Pipe
    private var stdoutData = Data()
    private var stderrData = Data()
    private var timeoutWorkItem: DispatchWorkItem?

    init(continuation: CheckedContinuation<ProcessResult, Never>, stdoutPipe: Pipe, stderrPipe: Pipe) {
        self.continuation = continuation
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
        lock.lock()
        guard let pendingContinuation = continuation else {
            lock.unlock()
            return
        }
        continuation = nil
        let out = stdoutData
        let err = stderrData
        let workItem = timeoutWorkItem
        lock.unlock()

        workItem?.cancel()
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        pendingContinuation.resume(
            returning: ProcessResult(
                exitCode: exitCode,
                standardOutput: String(data: out, encoding: .utf8) ?? "",
                standardError: String(data: err, encoding: .utf8) ?? ""
            )
        )
    }

    func finishLaunchFailure(_ error: Error) {
        lock.lock()
        guard let pendingContinuation = continuation else {
            lock.unlock()
            return
        }
        continuation = nil
        let workItem = timeoutWorkItem
        lock.unlock()

        workItem?.cancel()
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        pendingContinuation.resume(
            returning: ProcessResult(exitCode: -1, standardOutput: "", standardError: "\(error)")
        )
    }
}
