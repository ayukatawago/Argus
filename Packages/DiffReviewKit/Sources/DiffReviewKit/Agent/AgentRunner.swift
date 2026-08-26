import Foundation

/// A single unit of streamed output from a headless agent run.
public enum AgentEvent: Sendable {
    case text(String)
    case sessionID(String)
    case finished(exitCode: Int32)
    case failed(String)
}

/// A child process wired up with its stdout/stderr pipes, ready for `try process.run()` but not
/// yet started.
private struct SpawnableProcess {
    let process: Process
    let stdoutPipe: Pipe
    let stderrPipe: Pipe
}

/// Spawns a headless run of Claude Code or Codex CLI in a given working directory and streams its
/// output back as `AgentEvent`s.
///
/// Runs via the user's login shell (`$SHELL -l -c '...'`) so PATH entries added by nvm/homebrew/etc.
/// in the user's shell profile are available — this is an independent, non-interactive process; it
/// does not attach to (or share context with) any already-running interactive agent session.
public struct AgentRunner: Sendable {
    public let agent: DiffReviewAgent
    public let workingDirectory: String

    public init(agent: DiffReviewAgent, workingDirectory: String) {
        self.agent = agent
        self.workingDirectory = workingDirectory
    }

    /// Runs the agent non-interactively with the given prompt.
    ///
    /// - Parameters:
    ///   - prompt: the composed instruction (see `PromptComposer`).
    ///   - mode: `.reply` asks the agent not to modify files; `.apply` allows edits.
    ///   - resumingSessionID: when set, continues a prior *headless* session instead of starting a
    ///     new one. Cannot resume a live, interactively-attached session.
    public func run(prompt: String, mode: AgentRunMode, resumingSessionID: String?) -> AsyncStream<AgentEvent> {
        let spawnable = makeProcess(prompt: prompt, mode: mode, resumingSessionID: resumingSessionID)
        let process = spawnable.process
        let stdoutPipe = spawnable.stdoutPipe
        let stderrPipe = spawnable.stderrPipe

        return AsyncStream { continuation in
            let cleanup = PipeCleanup(stdoutPipe: stdoutPipe, stderrPipe: stderrPipe)
            let cancelGate = CancelGate()

            let task = Task {
                // `cancelGate.beginSpawn()` returns false if `onTermination` already fired before
                // this Task got a chance to run at all — in which case the process must never be
                // spawned, but the two pipes opened above still need to be released.
                guard cancelGate.beginSpawn() else {
                    cleanup.release()
                    continuation.finish()
                    return
                }
                do {
                    try process.run()
                } catch {
                    cleanup.release()
                    continuation.yield(.failed(error.localizedDescription))
                    continuation.finish()
                    return
                }
                // Registers the now-live process so a cancellation that raced in between
                // `beginSpawn()` returning true and here is applied now instead of being lost —
                // `onTermination`'s own `process.terminate()` would otherwise silently no-op
                // against a process that hadn't started running yet.
                cancelGate.spawned(process)

                let parser = StreamingOutputParser(kind: agent.kind)
                do {
                    for try await line in stdoutPipe.fileHandleForReading.bytes.lines {
                        for event in parser.consumeLine(line) {
                            continuation.yield(event)
                        }
                    }
                } catch {
                    continuation.yield(.failed(error.localizedDescription))
                }
                let exitCode = await Self.waitForExit(process)
                cleanup.release()
                continuation.yield(.finished(exitCode: exitCode))
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
                // `task.cancel()` alone only stops this Task from reading further output — it never
                // signals the child. Re-sending a comment's Reply/Apply cancels the previous run
                // (see `DiffReviewModel.send`), which without this would orphan the headless
                // `claude`/`codex` subprocess (and its pipes) running in the background forever.
                cancelGate.requestCancel()
            }
        }
    }

    /// Builds the child process and its two pipes, ready to spawn but not yet started. Split out
    /// of `run` so that method reads as the spawn/stream/cleanup state machine it is; this is just
    /// argument assembly.
    ///
    /// The pipes are constructed here — eagerly, before `run`'s `AsyncStream` or its `Task` ever
    /// runs — because `Pipe()` opens both fds immediately, so every one of `run`'s exit paths
    /// (including cancellation before the child is ever spawned) must be able to release them.
    private func makeProcess(prompt: String, mode: AgentRunMode, resumingSessionID: String?) -> SpawnableProcess {
        let process = Process()
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        process.executableURL = URL(fileURLWithPath: shell)
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        process.arguments = [
            "-l", "-c",
            commandLine(prompt: prompt, mode: mode, resumingSessionID: resumingSessionID),
        ]

        var environment = ProcessInfo.processInfo.environment
        for (key, value) in agent.environmentOverrides { environment[key] = value }
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Drained but discarded: nothing surfaces stderr today, but leaving it unread lets a
        // chatty CLI fill the ~64KB pipe buffer and block on write() forever, leaking the process
        // (and both its pipes) for the lifetime of the app.
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        return SpawnableProcess(process: process, stdoutPipe: stdoutPipe, stderrPipe: stderrPipe)
    }

    /// Awaits process exit without blocking a thread — `Process.waitUntilExit()` would otherwise
    /// pin a Swift concurrency cooperative-pool thread for as long as the child runs, and forever
    /// if it ignores `SIGTERM`.
    private static func waitForExit(_ process: Process) async -> Int32 {
        if !process.isRunning {
            return process.terminationStatus
        }
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { finishedProcess in
                continuation.resume(returning: finishedProcess.terminationStatus)
            }
        }
    }

    // MARK: - Command construction

    private func commandLine(prompt: String, mode: AgentRunMode, resumingSessionID: String?) -> String {
        switch agent.kind {
        case .claude: claudeCommandLine(prompt: prompt, mode: mode, resumingSessionID: resumingSessionID)
        case .codex: codexCommandLine(prompt: prompt, mode: mode, resumingSessionID: resumingSessionID)
        }
    }

    private func claudeCommandLine(prompt: String, mode: AgentRunMode, resumingSessionID: String?) -> String {
        var args = [
            agent.executablePath ?? "claude",
            "-p", shellEscape(prompt),
            "--output-format", "stream-json",
            "--verbose",
        ]
        if let resumingSessionID {
            args += ["--resume", shellEscape(resumingSessionID)]
        }
        if mode == .apply {
            args += ["--permission-mode", "acceptEdits"]
        }
        return args.joined(separator: " ")
    }

    // Codex CLI flags for non-interactive resume/auto-approval are less stable than Claude's;
    // adjust these if the installed Codex CLI version renames them.
    private func codexCommandLine(prompt: String, mode: AgentRunMode, resumingSessionID: String?) -> String {
        var args = [agent.executablePath ?? "codex", "exec"]
        if let resumingSessionID {
            args += ["resume", shellEscape(resumingSessionID)]
        }
        args += [shellEscape(prompt), "--json"]
        switch mode {
        case .reply:
            args += ["--sandbox", "read-only"]

        case .apply:
            args += ["--sandbox", "workspace-write", "--ask-for-approval", "never"]
        }
        return args.joined(separator: " ")
    }

    private func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// Closes both pipes' handles exactly once, from whichever of `run`'s exit paths reaches it first
/// (never-spawned-because-cancelled, launch failure, or normal completion). Guarded by a lock
/// rather than relying on the pipes going out of scope — none of `ProcessRunner`'s or `GitRunner`'s
/// object-graph cleanup applies here since these pipes are captured directly by the `Task` closure,
/// which otherwise lives as long as the `AsyncStream` continuation does.
private final class PipeCleanup: @unchecked Sendable {
    private let lock = NSLock()
    private var didRelease = false
    private let stdoutPipe: Pipe
    private let stderrPipe: Pipe

    init(stdoutPipe: Pipe, stderrPipe: Pipe) {
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
    }

    func release() {
        lock.lock()
        guard !didRelease else {
            lock.unlock()
            return
        }
        didRelease = true
        lock.unlock()

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        try? stdoutPipe.fileHandleForReading.close()
        try? stdoutPipe.fileHandleForWriting.close()
        try? stderrPipe.fileHandleForReading.close()
        try? stderrPipe.fileHandleForWriting.close()
    }
}

/// Closes the race between `continuation.onTermination` requesting cancellation and `run`'s `Task`
/// spawning the child: `Process.terminate()` is a no-op against a process that hasn't started
/// running yet, so a cancellation arriving in the narrow window between the pre-spawn check and the
/// process actually starting would otherwise be silently lost, orphaning the child.
private final class CancelGate: @unchecked Sendable {
    private enum State {
        case notStarted
        case spawned(Process)
        case cancelled
    }

    private let lock = NSLock()
    private var state: State = .notStarted

    /// Called immediately before `process.run()`. Returns `false` if cancellation already arrived,
    /// in which case the caller must not spawn the process at all.
    func beginSpawn() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if case .cancelled = state { return false }
        return true
    }

    /// Called immediately after a successful `process.run()`. If a cancellation raced in between
    /// `beginSpawn()` returning `true` and this call, it's applied now instead of being lost.
    func spawned(_ process: Process) {
        lock.lock()
        if case .cancelled = state {
            lock.unlock()
            if process.isRunning { process.terminate() }
            return
        }
        state = .spawned(process)
        lock.unlock()
    }

    func requestCancel() {
        lock.lock()
        let previous = state
        state = .cancelled
        lock.unlock()
        if case .spawned(let process) = previous, process.isRunning {
            process.terminate()
        }
    }
}

/// Best-effort parsing of each agent's streamed stdout into `AgentEvent`s. Both CLIs' line-delimited
/// JSON schemas are treated leniently — unrecognized shapes fall back to raw text rather than
/// dropping output, since the exact schema (especially Codex's) may vary across CLI versions.
private struct StreamingOutputParser {
    let kind: DiffReviewAgent.Kind

    func consumeLine(_ line: String) -> [AgentEvent] {
        guard !line.isEmpty else { return [] }
        switch kind {
        case .claude: return parseClaudeLine(line)
        case .codex: return parseCodexLine(line)
        }
    }

    // MARK: - Claude `--output-format stream-json`

    private func parseClaudeLine(_ line: String) -> [AgentEvent] {
        guard let object = jsonObject(from: line) else { return [.text(line)] }

        var events: [AgentEvent] = []
        if let sessionID = object["session_id"] as? String {
            events.append(.sessionID(sessionID))
        }

        switch object["type"] as? String {
        case "assistant":
            if let message = object["message"] as? [String: Any],
                let content = message["content"] as? [[String: Any]]
            {
                for block in content where block["type"] as? String == "text" {
                    if let text = block["text"] as? String {
                        events.append(.text(text))
                    }
                }
            }

        case "result":
            if let text = object["result"] as? String {
                events.append(.text(text))
            }

        default:
            break
        }

        return events
    }

    // MARK: - Codex `exec --json`

    private func parseCodexLine(_ line: String) -> [AgentEvent] {
        guard let object = jsonObject(from: line) else { return [.text(line)] }

        var events: [AgentEvent] = []
        if let sessionID = (object["session_id"] ?? object["conversation_id"]) as? String {
            events.append(.sessionID(sessionID))
        }
        if let text = (object["text"] ?? object["message"] ?? object["content"]) as? String {
            events.append(.text(text))
        }
        return events
    }

    private func jsonObject(from line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
