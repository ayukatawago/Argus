import ArgusSupport
import Foundation

/// Watches ~/.codex/sessions/ for Codex agent state changes by polling the JSONL
/// session files that Codex writes unconditionally — no hook trust required.
///
/// @unchecked Sendable: all mutable state is @MainActor-protected; the type is passed
/// into a background task only as a strong let reference used solely via MainActor.run.
@MainActor
public final class CodexSessionWatcher: @unchecked Sendable {
    public var onPayload: ((HookPayload) -> Void)?
    private var pollTask: Task<Void, Never>?

    /// A worktree whose session file hasn't grown in this long is treated as abandoned (crash,
    /// `kill -9`, or a normal exit — Codex fires no hook for either) and cleared to idle. Shares
    /// Claude's 300s rationale (see ClaudeTranscriptWatcher.staleTimeout): comfortably above any
    /// observed tool-call gap, so a genuinely busy agent never trips it.
    private nonisolated static let staleTimeout: TimeInterval = 300

    public init() {}

    public func start() {
        let state = PollState()
        pollTask = PollingTask.repeating(
            order: .actThenSleep,
            interval: { 500_000_000 },
            action: { [weak self] in
                await Self.scanOnce(state: state) { payload in
                    await MainActor.run { self?.onPayload?(payload) }
                }
            }
        )
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Cross-poll mutable state, threaded through scanOnce by PollingTask's action closure rather
    /// than captured `var`s in a loop. Deliberately not actor-isolated: PollingTask calls the
    /// action strictly sequentially — one call finishes before the next starts — so plain mutation
    /// here needs no lock or actor (same reasoning as ClaudeTranscriptWatcher.PollState).
    private final class PollState: @unchecked Sendable {
        var lastMtimes: [URL: Date] = [:]
        // Worktree cwd a tracked session file is bound to, so the stale branch knows what to clear.
        var cwds: [URL: String] = [:]
        // cwd -> last state string we emitted, used to suppress duplicate emissions
        var lastEmitted: [String: String] = [:]
    }

    private nonisolated static func scanOnce(
        state: PollState,
        handler: @Sendable (HookPayload) async -> Void
    ) async {
        let now = Date()

        // `recentSessionFiles()` only looks at today's and yesterday's day-bucketed directories —
        // enough to *discover* newly created sessions. But `codex resume --last` (the default
        // codexCommand) keeps appending to the *original* rollout file indefinitely, which lives
        // in the directory named after the session's creation date, not today's. Without this
        // union, any session resumed more than a day past its creation drops out of the scan
        // forever and its worktree's state silently freezes. Once a file is discovered (present in
        // `state.cwds`), keep polling it here regardless of which day it lives in, until
        // `clearIfTracked` removes it below for genuinely going stale.
        let files = Set(recentSessionFiles()).union(state.cwds.keys)

        for fileURL in files {
            guard
                let attrs = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
                let mtime = attrs.contentModificationDate
            else { continue }

            guard now.timeIntervalSince(mtime) < staleTimeout else {
                state.lastMtimes.removeValue(forKey: fileURL)
                await clearIfTracked(fileURL, state: state, handler: handler)
                continue
            }

            let prevMtime = state.lastMtimes[fileURL]
            state.lastMtimes[fileURL] = mtime

            // Only reparse if the file actually changed
            guard prevMtime.map({ mtime > $0 }) ?? true else { continue }

            guard let parsed = parseSessionFile(at: fileURL) else { continue }
            // Subagent rollouts carry their parent's cwd but track a different unit of work —
            // treating them as peers of the top-level session flaps the indicator on every
            // subagent spawn/finish. Only the top-level ("user") thread drives worktree state.
            guard parsed.threadSource != "subagent" else { continue }
            state.cwds[fileURL] = parsed.cwd

            guard let sessionState = parsed.state else { continue }
            await emit(cwd: parsed.cwd, sessionState: sessionState, state: state, handler: handler)
        }
    }

    /// A file we were never tracking is just an old, already-finished (or subagent) session —
    /// nothing to do. One we *were* tracking just went quiet (crash, `kill -9`, or a normal exit —
    /// no hook covers either): clear its worktree to idle and stop tracking it.
    private nonisolated static func clearIfTracked(
        _ fileURL: URL,
        state: PollState,
        handler: @Sendable (HookPayload) async -> Void
    ) async {
        guard let cwd = state.cwds.removeValue(forKey: fileURL) else { return }
        await emit(cwd: cwd, sessionState: "idle", state: state, handler: handler)
    }

    private nonisolated static func emit(
        cwd: String,
        sessionState: String,
        state: PollState,
        handler: @Sendable (HookPayload) async -> Void
    ) async {
        guard state.lastEmitted[cwd] != sessionState else { return }
        state.lastEmitted[cwd] = sessionState
        await handler(HookPayload(worktreePath: cwd, state: sessionState, agent: "codex"))
    }

    // MARK: - File helpers

    private nonisolated static func recentSessionFiles() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let sessionsBase = home.appendingPathComponent(".codex/sessions")
        let calendar = Calendar.current
        let now = Date()

        var results: [URL] = []
        for dayOffset in 0...1 {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { continue }
            let comps = calendar.dateComponents([.year, .month, .day], from: day)
            guard let year = comps.year, let month = comps.month, let dayVal = comps.day else { continue }
            let dir =
                sessionsBase
                .appendingPathComponent(String(format: "%04d", year))
                .appendingPathComponent(String(format: "%02d", month))
                .appendingPathComponent(String(format: "%02d", dayVal))
            guard
                let files = try? FileManager.default.contentsOfDirectory(
                    at: dir,
                    includingPropertiesForKeys: [.contentModificationDateKey]
                )
            else { continue }
            results.append(contentsOf: files.filter { $0.pathExtension == "jsonl" })
        }
        return results
    }

    private struct ParsedSession {
        let cwd: String
        let threadSource: String?
        let state: String?
    }

    /// Reads the session file's header and tail in a single open. cwd appears at ~byte 156 and
    /// thread_source at ~byte 270-618; 2048 bytes is always enough regardless of system-prompt
    /// length. `state` is `nil` when the tail contains no decisive event (empty file, or the file
    /// grew but nothing relevant landed in the last 4096 bytes).
    ///
    /// Deliberately uses `String(decoding:as:)`, not the failable `String(bytes:encoding:)`: a
    /// fixed-size read can cut a UTF-8 codepoint in half, and a nil result previously made the
    /// caller fall back to reporting "running" outright (a real session could be long done).
    /// `String(decoding:as:)` never fails — the split codepoint becomes U+FFFD, corrupting only the
    /// one already-partial line, which the per-line JSON guard in CodexSessionParser.inferState
    /// skips anyway.
    private nonisolated static func parseSessionFile(at url: URL) -> ParsedSession? {
        // swiftlint:disable optional_data_string_conversion
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let headerData = handle.readData(ofLength: 2_048)
        let headerText = String(decoding: headerData, as: UTF8.self)
        guard let cwd = CodexSessionParser.extractCwd(from: headerText) else { return nil }
        let threadSource = CodexSessionParser.extractThreadSource(from: headerText)

        guard
            let size = try? handle.seekToEnd(),
            size > 0
        else { return ParsedSession(cwd: cwd, threadSource: threadSource, state: nil) }

        let tailSize: UInt64 = min(size, 4_096)
        try? handle.seek(toOffset: size - tailSize)
        let tailData = handle.readDataToEndOfFile()
        let tailText = String(decoding: tailData, as: UTF8.self)
        // swiftlint:enable optional_data_string_conversion
        return ParsedSession(cwd: cwd, threadSource: threadSource, state: CodexSessionParser.inferState(from: tailText))
    }
}
