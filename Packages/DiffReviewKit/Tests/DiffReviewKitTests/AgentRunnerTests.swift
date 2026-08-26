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
}
