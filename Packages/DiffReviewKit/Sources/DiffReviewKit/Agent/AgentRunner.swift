import Foundation

/// A single unit of streamed output from a headless agent run.
public enum AgentEvent: Sendable {
    case text(String)
    case sessionID(String)
    case finished(exitCode: Int32)
    case failed(String)
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
        AsyncStream { continuation in
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

            // Drained but discarded: nothing surfaces stderr today, but leaving it unread lets
            // a chatty CLI fill the ~64KB pipe buffer and block on write() forever, leaking the
            // process (and both its pipes) for the lifetime of the app.
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                _ = handle.availableData
            }

            let task = Task {
                do {
                    try process.run()
                } catch {
                    continuation.yield(.failed(error.localizedDescription))
                    continuation.finish()
                    return
                }

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
                process.waitUntilExit()
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                continuation.yield(.finished(exitCode: process.terminationStatus))
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
                // `task.cancel()` alone only stops this Task from reading further output — it never
                // signals the child. Re-sending a comment's Reply/Apply cancels the previous run
                // (see `DiffReviewModel.send`), which without this would orphan the headless
                // `claude`/`codex` subprocess (and its pipes) running in the background forever.
                if process.isRunning { process.terminate() }
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
