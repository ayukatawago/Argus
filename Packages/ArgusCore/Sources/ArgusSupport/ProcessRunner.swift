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

            // Captures only `completer` (never `process` directly) so nothing outlives the run:
            // `completer` drops its own reference to `process` once it finishes.
            process.terminationHandler = { finished in
                completer.finish(exitCode: finished.terminationStatus)
            }

            if let timeout {
                // Captures only `completer`, which resolves the process itself — avoids a cycle
                // through `process.terminationHandler` retaining a block that captures `process`.
                let workItem = DispatchWorkItem {
                    completer.finishTimedOut()
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

/// Owns the continuation, the process, and the buffered output for one `run` call. Completion can
/// be signaled from three independent, concurrently-executing sources — `terminationHandler`, the
/// timeout's `DispatchWorkItem`, and the synchronous launch-failure `catch` — so every mutation and
/// the resume-once guard are behind a single lock.
///
/// Also owns fd release: nothing else in `ProcessRunner.run` keeps a strong reference to the pipes
/// once this class exists, so when a run finishes here, the pipes' read ends are drained and
/// explicitly closed rather than left for ARC to reclaim whenever the last retaining closure (e.g.
/// `Process.terminationHandler`, which `Process` itself retains) happens to release them.
private final class Completer: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ProcessResult, Never>?
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stdoutData = Data()
    private var stderrData = Data()
    private var timeoutWorkItem: DispatchWorkItem?
    private var didRelease = false

    init(
        continuation: CheckedContinuation<ProcessResult, Never>, process: Process, stdoutPipe: Pipe, stderrPipe: Pipe
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
        complete(exitCode: exitCode, launchError: nil)
    }

    func finishTimedOut() {
        lock.lock()
        let target = process
        lock.unlock()
        if target?.isRunning == true { target?.terminate() }
        complete(exitCode: -1, launchError: nil)
    }

    func finishLaunchFailure(_ error: Error) {
        complete(exitCode: -1, launchError: error)
    }

    /// Resolves the continuation exactly once, regardless of which of the three sources calls in
    /// first. Draining and closing the pipes happens here too, unconditionally, so a caller can
    /// never observe a resolved run that still holds its fds open.
    private func complete(exitCode: Int32, launchError: Error?) {
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

        // Tear down the readability handlers before doing a final bounded, non-blocking drain —
        // otherwise the handler and this drain can both be reading the same fd concurrently,
        // interleaving or splitting output.
        stdout?.fileHandleForReading.readabilityHandler = nil
        stderr?.fileHandleForReading.readabilityHandler = nil
        if let stdout { appendStdout(Self.drainNonBlocking(stdout.fileHandleForReading)) }
        if let stderr { appendStderr(Self.drainNonBlocking(stderr.fileHandleForReading)) }
        releasePipes(stdout, stderr)

        lock.lock()
        let out = stdoutData
        let err = stderrData
        lock.unlock()

        let standardError: String
        if let launchError {
            standardError = "\(launchError)"
        } else {
            standardError = String(data: err, encoding: .utf8) ?? ""
        }
        pendingContinuation.resume(
            returning: ProcessResult(
                exitCode: exitCode,
                standardOutput: String(data: out, encoding: .utf8) ?? "",
                standardError: standardError
            )
        )
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
    /// `stdoutPipe`/`stderrPipe` becoming nil) because `finish`/`finishTimedOut`/`finishLaunchFailure`
    /// can race to call `complete`, and double-closing a fd once its number has been reused by an
    /// unrelated open elsewhere in the process is a real correctness hazard, not just a warning.
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
