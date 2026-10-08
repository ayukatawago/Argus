import Foundation
import Testing

@testable import DiffReviewKit

/// The number of fds this process currently has open, via `/dev/fd` (each entry there is one live
/// descriptor) — used to assert `AgentRunner` releases every pipe fd it opens rather than leaving
/// it for ARC to reclaim whenever the last retaining closure happens to release it.
private func openFileDescriptorCount() -> Int {
    (try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count) ?? -1
}

/// Drains a run to completion, collecting every event.
private func collectEvents(_ stream: AsyncStream<AgentEvent>) async -> [AgentEvent] {
    var events: [AgentEvent] = []
    for await event in stream {
        events.append(event)
    }
    return events
}

// `.serialized`: the fd-leak tests below count this process's *total* open fds, and one test
// temporarily overrides the process-wide `SHELL` environment variable — both would be corrupted by
// swift-testing's default concurrent execution of sibling tests in this suite.
@Suite("AgentRunner", .serialized)
struct AgentRunnerTests {
    /// `agent.executablePath` overrides only the binary name baked into the command string passed
    /// to `$SHELL -l -c '...'` — pointing it at `/bin/echo` turns a "claude" run into one that
    /// echoes its own (fixed) CLI flags back as a single line of stdout and exits 0, without
    /// needing a real Claude/Codex CLI installed.
    private static let echoAgent = DiffReviewAgent(kind: .claude, executablePath: "/bin/echo")

    @Test("a successful run streams text and finishes with exit code 0")
    func successfulRun() async {
        let runner = AgentRunner(agent: Self.echoAgent, workingDirectory: NSTemporaryDirectory())
        let events = await collectEvents(runner.run(prompt: "hello", mode: .reply, resumingSessionID: nil))
        guard case .finished(let exitCode) = events.last else {
            Issue.record("expected the last event to be .finished, got \(events.last as Any)")
            return
        }
        #expect(exitCode == 0)
        #expect(events.contains { if case .text = $0 { return true } else { return false } })
    }

    @Test("a shell that cannot be launched produces a failed event instead of hanging")
    func launchFailure() async {
        let previousShell = ProcessInfo.processInfo.environment["SHELL"]
        setenv("SHELL", "/no/such/shell", 1)
        defer {
            if let previousShell { setenv("SHELL", previousShell, 1) } else { unsetenv("SHELL") }
        }

        let runner = AgentRunner(agent: Self.echoAgent, workingDirectory: NSTemporaryDirectory())
        let events = await collectEvents(runner.run(prompt: "hello", mode: .reply, resumingSessionID: nil))
        #expect(events.contains { if case .failed = $0 { return true } else { return false } })
    }

    // MARK: - fd leak regressions
    //
    // Mirrors ArgusSupport's ProcessRunnerTests and DiffReviewKit's GitRunnerTests: every pipe fd
    // `run` opens must be closed by the time its stream finishes, on every completion path.

    @Test("repeated successful runs do not leak file descriptors")
    func noLeakOnSuccess() async {
        let runner = AgentRunner(agent: Self.echoAgent, workingDirectory: NSTemporaryDirectory())
        let before = openFileDescriptorCount()
        for _ in 0..<50 {
            _ = await collectEvents(runner.run(prompt: "hello", mode: .reply, resumingSessionID: nil))
        }
        let after = openFileDescriptorCount()
        #expect(after - before <= 5, "fd count grew from \(before) to \(after) over 50 successful runs")
    }

    @Test("repeated launch failures do not leak file descriptors")
    func noLeakOnLaunchFailure() async {
        let previousShell = ProcessInfo.processInfo.environment["SHELL"]
        setenv("SHELL", "/no/such/shell", 1)
        defer {
            if let previousShell { setenv("SHELL", previousShell, 1) } else { unsetenv("SHELL") }
        }

        let runner = AgentRunner(agent: Self.echoAgent, workingDirectory: NSTemporaryDirectory())
        let before = openFileDescriptorCount()
        for _ in 0..<50 {
            _ = await collectEvents(runner.run(prompt: "hello", mode: .reply, resumingSessionID: nil))
        }
        let after = openFileDescriptorCount()
        #expect(after - before <= 5, "fd count grew from \(before) to \(after) over 50 launch failures")
    }

    @Test("cancelling a run mid-stream terminates the child and does not leak file descriptors")
    func noLeakOnCancellation() async throws {
        // A slow "shell": ignores the `-l -c '<command>'` arguments $SHELL is normally invoked
        // with and just sleeps, so the run can be cancelled while its child is still alive.
        let scriptPath = NSTemporaryDirectory() + "agent-runner-slow-shell-\(UUID().uuidString).sh"
        try "#!/bin/sh\nsleep 5\n".write(toFile: scriptPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)
        defer { try? FileManager.default.removeItem(atPath: scriptPath) }

        let previousShell = ProcessInfo.processInfo.environment["SHELL"]
        setenv("SHELL", scriptPath, 1)
        defer {
            if let previousShell { setenv("SHELL", previousShell, 1) } else { unsetenv("SHELL") }
        }

        let runner = AgentRunner(agent: Self.echoAgent, workingDirectory: NSTemporaryDirectory())
        let before = openFileDescriptorCount()
        for _ in 0..<10 {
            let stream = runner.run(prompt: "hello", mode: .reply, resumingSessionID: nil)
            // Cancelling the consuming Task while it's suspended in `for await` is what makes
            // `AsyncStream` invoke `onTermination` — mirrors `DiffReviewModel.send` cancelling an
            // in-flight run's Task when a comment's Reply/Apply is re-sent.
            let consumer = Task {
                for await _ in stream {}
            }
            // Give the runner's own Task a moment to actually spawn the slow shell before
            // cancelling — exercises "cancel after spawn", the more common real-world case.
            try await Task.sleep(nanoseconds: 20_000_000)
            consumer.cancel()
            _ = await consumer.value
        }
        // Cleanup after cancellation runs asynchronously inside the runner's own Task (terminate →
        // EOF → waitForExit → release); give it a beat to settle before asserting.
        try await Task.sleep(nanoseconds: 300_000_000)
        let after = openFileDescriptorCount()
        #expect(after - before <= 10, "fd count grew from \(before) to \(after) over 10 cancelled runs")
    }

    // MARK: - exit status, stderr and descendant cleanup

    private func writeScript(_ body: String) throws -> String {
        let path = NSTemporaryDirectory() + "agent-runner-script-\(UUID().uuidString).sh"
        try "#!/bin/sh\n\(body)\n".write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    @Test("a non-zero exit is surfaced as a failure carrying the CLI's stderr")
    func nonZeroExitFails() async throws {
        let script = try writeScript("echo boom >&2\nexit 3")
        defer { try? FileManager.default.removeItem(atPath: script) }
        let agent = DiffReviewAgent(kind: .claude, executablePath: script)
        let runner = AgentRunner(agent: agent, workingDirectory: NSTemporaryDirectory())
        let events = await collectEvents(runner.run(prompt: "hi", mode: .reply, resumingSessionID: nil))
        let failure = events.compactMap { event -> String? in
            if case .failed(let message) = event { message } else { nil }
        }.first
        #expect(failure?.contains("code 3") == true)
        #expect(failure?.contains("boom") == true)
    }

    @Test("a child that exits immediately never loses the exit status (terminationHandler set before run)")
    func fastExitIsNotLost() async {
        let runner = AgentRunner(
            agent: DiffReviewAgent(kind: .claude, executablePath: "/usr/bin/true"),
            workingDirectory: NSTemporaryDirectory()
        )
        for _ in 0..<30 {
            let events = await collectEvents(runner.run(prompt: "x", mode: .reply, resumingSessionID: nil))
            guard case .finished(let code) = events.last else {
                Issue.record("run did not finish: \(events)")
                return
            }
            #expect(code == 0)
        }
    }

    @Test("cancelling a run also terminates the child's descendants")
    func cancelKillsDescendants() async throws {
        let pidFile = NSTemporaryDirectory() + "agent-runner-pid-\(UUID().uuidString)"
        let script = try writeScript("sleep 60 &\necho $! > \(pidFile)\nwait")
        defer {
            try? FileManager.default.removeItem(atPath: script)
            try? FileManager.default.removeItem(atPath: pidFile)
        }
        let previousShell = ProcessInfo.processInfo.environment["SHELL"]
        setenv("SHELL", script, 1)
        defer {
            if let previousShell { setenv("SHELL", previousShell, 1) } else { unsetenv("SHELL") }
        }

        let runner = AgentRunner(agent: Self.echoAgent, workingDirectory: NSTemporaryDirectory())
        let stream = runner.run(prompt: "hello", mode: .reply, resumingSessionID: nil)
        let consumer = Task { for await _ in stream {} }

        var grandchild: pid_t?
        for _ in 0..<100 where grandchild == nil {
            try await Task.sleep(nanoseconds: 50_000_000)
            grandchild = (try? String(contentsOfFile: pidFile, encoding: .utf8))
                .flatMap { pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        let pid = try #require(grandchild)
        #expect(kill(pid, 0) == 0, "grandchild should be alive before cancel")

        consumer.cancel()
        _ = await consumer.value
        var dead = false
        for _ in 0..<100 where !dead {
            try await Task.sleep(nanoseconds: 50_000_000)
            dead = kill(pid, 0) != 0
        }
        #expect(dead, "grandchild \(pid) survived cancellation")
        if !dead { kill(pid, SIGKILL) }
    }
}
