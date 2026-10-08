import ArgusSupport
import Foundation
import Testing

@testable import AgentStateKit

/// Collects payloads emitted by one scan, safely from the `@Sendable` handler.
private actor PayloadBox {
    private(set) var payloads: [HookPayload] = []
    func add(_ payload: HookPayload) { payloads.append(payload) }
    func take() -> [String] {
        defer { payloads = [] }
        return payloads.map { "\($0.agent ?? "?"):\($0.worktreePath):\($0.state)" }
    }
}

/// A fresh temp directory removed when the test ends.
private final class TempDir {
    let url: URL
    init(_ name: String) throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }
}

private func iso(_ date: Date) -> String {
    Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(date)
}

private func append(_ text: String, to url: URL) throws {
    if !FileManager.default.fileExists(atPath: url.path) {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
    }
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(text.utf8))
}

private func ageFile(_ url: URL, by seconds: TimeInterval) throws {
    try FileManager.default.setAttributes(
        [.modificationDate: Date().addingTimeInterval(-seconds)], ofItemAtPath: url.path)
}

@Suite("ClaudeTranscriptWatcher scan (temp projects root)")
struct ClaudeWatcherScanTests {
    private func userLine(cwd: String, at date: Date, entrypoint: String = "cli") -> String {
        let head = #"{"type":"user","cwd":"\#(cwd)","entrypoint":"\#(entrypoint)","sessionId":"s","#
        let tail = #""timestamp":"\#(iso(date))","message":{"role":"user","content":"hi"}}"#
        return head + tail + "\n"
    }

    private func doneLine(cwd: String, at date: Date) -> String {
        let head = #"{"type":"assistant","cwd":"\#(cwd)","timestamp":"\#(iso(date))","#
        let tail = #""message":{"role":"assistant","stop_reason":"end_turn","content":[{"type":"text","text":"ok"}]}}"#
        return head + tail
    }

    private func scan(_ state: ClaudeTranscriptWatcher.PollState, root: URL, box: PayloadBox) async {
        await ClaudeTranscriptWatcher.scanOnce(state: state, root: root, now: Date()) { await box.add($0) }
    }

    @Test("a new transcript reads as running, then done once an end_turn line is appended")
    func runningThenDone() async throws {
        let dir = try TempDir("claude-root")
        let file = dir.url.appendingPathComponent("-work-a/s.jsonl")
        try append(userLine(cwd: "/work/a", at: Date()), to: file)
        let (state, box) = (ClaudeTranscriptWatcher.PollState(), PayloadBox())

        await scan(state, root: dir.url, box: box)
        #expect(await box.take() == ["claude:/work/a:running"])

        await scan(state, root: dir.url, box: box)
        #expect(await box.take().isEmpty, "an unchanged transcript must not re-emit")

        try append(doneLine(cwd: "/work/a", at: Date()) + "\n", to: file)
        await scan(state, root: dir.url, box: box)
        #expect(await box.take() == ["claude:/work/a:done"])
    }

    @Test("a line written in two halves is only acted on once complete, and is never re-read")
    func partialLineAcrossPolls() async throws {
        let dir = try TempDir("claude-root")
        let file = dir.url.appendingPathComponent("-work-a/s.jsonl")
        try append(userLine(cwd: "/work/a", at: Date()), to: file)
        let (state, box) = (ClaudeTranscriptWatcher.PollState(), PayloadBox())
        await scan(state, root: dir.url, box: box)
        _ = await box.take()

        let line = doneLine(cwd: "/work/a", at: Date())
        let midpoint = line.index(line.startIndex, offsetBy: line.count / 2)
        try append(String(line[..<midpoint]), to: file)
        await scan(state, root: dir.url, box: box)
        #expect(await box.take().isEmpty)

        try append(String(line[midpoint...]) + "\n", to: file)
        await scan(state, root: dir.url, box: box)
        #expect(await box.take() == ["claude:/work/a:done"])
    }

    @Test("a headless sdk-cli session sharing the cwd never drives the worktree's state")
    func sdkCliIgnored() async throws {
        let dir = try TempDir("claude-root")
        try append(
            userLine(cwd: "/work/a", at: Date(), entrypoint: "sdk-cli"),
            to: dir.url.appendingPathComponent("-work-a/headless.jsonl"))
        let (state, box) = (ClaudeTranscriptWatcher.PollState(), PayloadBox())
        await scan(state, root: dir.url, box: box)
        #expect(await box.take().isEmpty)
    }

    @Test("a transcript untouched for longer than the activity window is skipped")
    func staleSkipped() async throws {
        let dir = try TempDir("claude-root")
        let file = dir.url.appendingPathComponent("-work-a/old.jsonl")
        try append(userLine(cwd: "/work/a", at: Date().addingTimeInterval(-3_600)), to: file)
        try ageFile(file, by: 3_600)
        let (state, box) = (ClaudeTranscriptWatcher.PollState(), PayloadBox())
        await scan(state, root: dir.url, box: box)
        #expect(await box.take().isEmpty)
    }

    @Test("with two sessions on one cwd, the one with the newest in-file activity wins")
    func newestSessionWins() async throws {
        let dir = try TempDir("claude-root")
        let now = Date()
        try append(
            userLine(cwd: "/work/a", at: now.addingTimeInterval(-120))
                + doneLine(cwd: "/work/a", at: now.addingTimeInterval(-100)) + "\n",
            to: dir.url.appendingPathComponent("-work-a/older.jsonl"))
        try append(
            userLine(cwd: "/work/a", at: now.addingTimeInterval(-5)),
            to: dir.url.appendingPathComponent("-work-a/newer.jsonl"))
        let (state, box) = (ClaudeTranscriptWatcher.PollState(), PayloadBox())
        await scan(state, root: dir.url, box: box)
        #expect(await box.take() == ["claude:/work/a:running"])
    }

    @Test("a missing projects root is harmless")
    func missingRoot() async {
        let (state, box) = (ClaudeTranscriptWatcher.PollState(), PayloadBox())
        await scan(state, root: URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)"), box: box)
        #expect(await box.take().isEmpty)
    }
}

@Suite("CodexSessionWatcher scan (temp sessions root)")
struct CodexWatcherScanTests {
    private func rolloutURL(_ root: URL, name: String = "rollout-1.jsonl") -> URL {
        CodexRolloutLocator.dayDirectories(base: root, days: 1, now: Date(), calendar: .current)[0]
            .appendingPathComponent(name)
    }

    private func meta(cwd: String, source: String = "user") -> String {
        #"{"timestamp":"2026-10-08T01:00:00Z","type":"session_meta","payload":{"id":"x","cwd":"\#(cwd)","thread_source":"\#(source)"}}"#
            + "\n"
    }

    private func event(_ type: String, extra: String = "") -> String {
        #"{"timestamp":"2026-10-08T01:00:01Z","type":"event_msg","payload":{"type":"\#(type)"\#(extra)}}"# + "\n"
    }

    private func scan(_ state: CodexSessionWatcher.PollState, root: URL, box: PayloadBox) async {
        await CodexSessionWatcher.scanOnce(state: state, root: root, now: Date()) { await box.add($0) }
    }

    @Test("task_started reads as running; task_complete then reads as done")
    func runningThenDone() async throws {
        let dir = try TempDir("codex-root")
        let file = rolloutURL(dir.url)
        try append(meta(cwd: "/work/a") + event("task_started"), to: file)
        let (state, box) = (CodexSessionWatcher.PollState(), PayloadBox())

        await scan(state, root: dir.url, box: box)
        #expect(await box.take() == ["codex:/work/a:running"])

        try append(event("task_complete"), to: file)
        await scan(state, root: dir.url, box: box)
        #expect(await box.take() == ["codex:/work/a:done"])
    }

    @Test("a subagent rollout sharing the cwd is ignored")
    func subagentIgnored() async throws {
        let dir = try TempDir("codex-root")
        try append(
            meta(cwd: "/work/a", source: "subagent") + event("task_started"),
            to: rolloutURL(dir.url, name: "rollout-sub.jsonl"))
        let (state, box) = (CodexSessionWatcher.PollState(), PayloadBox())
        await scan(state, root: dir.url, box: box)
        #expect(await box.take().isEmpty)
    }

    @Test("a rollout untouched for longer than the activity window is skipped")
    func staleSkipped() async throws {
        let dir = try TempDir("codex-root")
        let file = rolloutURL(dir.url)
        try append(meta(cwd: "/work/a") + event("task_started"), to: file)
        try ageFile(file, by: 3_600)
        let (state, box) = (CodexSessionWatcher.PollState(), PayloadBox())
        await scan(state, root: dir.url, box: box)
        #expect(await box.take().isEmpty)
    }

    @Test("a task_complete line longer than the initial 4 KB tail window is still found")
    func longCompleteLine() async throws {
        let dir = try TempDir("codex-root")
        let file = rolloutURL(dir.url)
        let longMessage = String(repeating: "x", count: 20_000)
        try append(
            meta(cwd: "/work/a") + event("task_started")
                + event("task_complete", extra: #","last_agent_message":"\#(longMessage)""#),
            to: file)
        let (state, box) = (CodexSessionWatcher.PollState(), PayloadBox())
        await scan(state, root: dir.url, box: box)
        #expect(await box.take() == ["codex:/work/a:done"])
    }

    @Test("turn_aborted maps to idle after running")
    func abortedIsIdle() async throws {
        let dir = try TempDir("codex-root")
        let file = rolloutURL(dir.url)
        try append(meta(cwd: "/work/a") + event("task_started"), to: file)
        let (state, box) = (CodexSessionWatcher.PollState(), PayloadBox())
        await scan(state, root: dir.url, box: box)
        _ = await box.take()
        try append(event("turn_aborted"), to: file)
        await scan(state, root: dir.url, box: box)
        #expect(await box.take() == ["codex:/work/a:idle"])
    }

    @Test("a missing sessions root is harmless")
    func missingRoot() async {
        let (state, box) = (CodexSessionWatcher.PollState(), PayloadBox())
        await scan(state, root: URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)"), box: box)
        #expect(await box.take().isEmpty)
    }
}
