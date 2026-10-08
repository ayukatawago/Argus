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
    /// `kill -9`, or a normal exit — Codex fires no hook for either) and stops contributing to its
    /// cwd's resolved state. Shares Claude's rationale for sizing (see
    /// ClaudeTranscriptWatcher.activityWindow) — comfortably above any observed tool-call gap.
    /// Unlike Claude's transcripts, mtime IS trustworthy here as a positive signal too: measured
    /// zero mtime/content skew across every local rollout — Codex appends, it never rewrites a
    /// rollout file in place — so this stays keyed on mtime rather than needing an in-file
    /// timestamp read.
    private nonisolated static let activityWindow: TimeInterval = 900

    /// `<year>/<month>/<day>/` rollout tree. Injectable so the scan can run against a temp directory.
    private let sessionsRoot: URL

    public init(sessionsRoot: URL = CodexSessionWatcher.defaultSessionsRoot) {
        self.sessionsRoot = sessionsRoot
    }

    public nonisolated static var defaultSessionsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
    }

    public func start() {
        let state = PollState()
        let root = sessionsRoot
        pollTask = PollingTask.repeating(
            order: .actThenSleep,
            interval: { 500_000_000 },
            action: { [weak self] in
                await Self.scanOnce(state: state, root: root, now: Date()) { payload in
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
    final class PollState: @unchecked Sendable {
        var lastMtimes: [URL: Date] = [:]
        // Worktree cwd a tracked session file is bound to, and its last-known parsed contribution —
        // kept even once a file goes stale so a resumed-elsewhere sibling can still be told apart
        // from "nothing is active for this cwd" until this record itself is dropped.
        var cwds: [URL: String] = [:]
        var lastObservation: [URL: SessionActivityArbiter.SessionObservation] = [:]
        // cwd -> last state string emitted, used to suppress duplicate emissions.
        var lastEmitted: [String: String] = [:]
    }

    nonisolated static func scanOnce(
        state: PollState,
        root: URL,
        now: Date,
        handler: @Sendable (HookPayload) async -> Void
    ) async {
        // `recentSessionFiles()` only looks at today's and yesterday's day-bucketed directories —
        // enough to *discover* newly created sessions. But `codex resume` (the default
        // codexCommand) keeps appending to the *original* rollout file indefinitely, which lives
        // in the directory named after the session's creation date, not today's. Without this
        // union, any session resumed more than a day past its creation drops out of the scan
        // forever and its worktree's state silently freezes. Once a file is discovered (present in
        // `state.cwds`), keep polling it here regardless of which day it lives in, until it falls
        // out of `activityWindow` below.
        let files = Set(recentSessionFiles(under: root, now: now)).union(state.cwds.keys)

        for fileURL in files {
            guard
                let attrs = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
                let mtime = attrs.contentModificationDate
            else { continue }

            guard now.timeIntervalSince(mtime) < activityWindow else {
                state.lastMtimes.removeValue(forKey: fileURL)
                state.cwds.removeValue(forKey: fileURL)
                state.lastObservation.removeValue(forKey: fileURL)
                continue
            }

            let prevMtime = state.lastMtimes[fileURL]
            state.lastMtimes[fileURL] = mtime

            // Only reparse if the file actually changed.
            if prevMtime.map({ mtime > $0 }) ?? true {
                if let parsed = parseSessionFile(at: fileURL), parsed.threadSource != "subagent" {
                    // Subagent rollouts carry their parent's cwd but track a different unit of
                    // work — treating them as peers of the top-level session flaps the indicator on
                    // every subagent spawn/finish. Only the top-level ("user") thread drives
                    // worktree state.
                    state.cwds[fileURL] = parsed.cwd
                    // The file grew (mtime advanced) even when nothing decisive landed in the last
                    // 4096-byte tail — carry the previously-known state forward but still refresh
                    // `lastActivity` to the new mtime, or a genuinely active session with a quiet
                    // tail window would otherwise age out of `activityWindow` on its own growth.
                    if let effectiveState = parsed.state ?? state.lastObservation[fileURL]?.state {
                        state.lastObservation[fileURL] = SessionActivityArbiter.SessionObservation(
                            cwd: parsed.cwd, state: effectiveState, lastActivity: mtime
                        )
                    }
                }
            }
        }

        let observations = Array(state.lastObservation.values)
        let resolved = SessionActivityArbiter.resolve(observations, now: now, window: activityWindow)
        for emission in SessionActivityArbiter.emissions(resolved: resolved, lastEmitted: state.lastEmitted) {
            state.lastEmitted[emission.cwd] = emission.state
            await handler(HookPayload(worktreePath: emission.cwd, state: emission.state, agent: "codex"))
        }
    }

    // MARK: - File helpers

    private nonisolated static func recentSessionFiles(under root: URL, now: Date) -> [URL] {
        // Today and yesterday only — enough to *discover* new sessions; older, already-discovered
        // ones keep being polled through `PollState.cwds` (see `scanOnce`).
        CodexRolloutLocator.dayDirectories(base: root, days: 2, now: now, calendar: .current).flatMap { dir in
            let files = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey])
            return (files ?? []).filter { $0.pathExtension == "jsonl" }
        }
    }

    private nonisolated static let initialTailBytes: UInt64 = 4_096
    private nonisolated static let maxTailBytes: UInt64 = 262_144

    private struct ParsedSession {
        let cwd: String
        let threadSource: String?
        let state: String?
    }

    /// Reads the session file's header and tail in a single open. cwd appears at ~byte 156 and
    /// thread_source at ~byte 270-618; 2048 bytes is always enough regardless of system-prompt
    /// length. `state` is `nil` when the tail contains no decisive event (empty file, or the file
    /// grew but nothing relevant landed in the last 256 KB).
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

        // Grow the tail window until a decisive line shows up or the whole file has been read: a
        // `task_complete` line carrying a long `last_agent_message` can exceed any fixed window,
        // which would otherwise leave the state stuck on "running" until the staleness cutoff.
        var tailSize = min(size, Self.initialTailBytes)
        var state: String?
        while true {
            try? handle.seek(toOffset: size - tailSize)
            let tailText = String(decoding: handle.readDataToEndOfFile(), as: UTF8.self)
            state = CodexSessionParser.inferState(from: tailText)
            if state != nil || tailSize >= min(size, Self.maxTailBytes) { break }
            tailSize = min(size, tailSize * 2, Self.maxTailBytes)
        }
        // swiftlint:enable optional_data_string_conversion
        return ParsedSession(cwd: cwd, threadSource: threadSource, state: state)
    }
}
