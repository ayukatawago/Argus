import ArgusSupport
import Foundation

/// Watches ~/.claude/projects/ for Claude Code agent state changes by polling the session
/// transcript JSONL files Claude Code writes unconditionally — no hook trust required. Mirrors
/// CodexSessionWatcher's design: Claude Code fires no hook on Escape-interrupt or on a stalled/
/// crashed session, so `running`/`done`/interrupted-back-to-`idle` are all inferred here instead.
/// PermissionRequest remains a hook (see WorktreeHookManager/ClaudeSettingsPatcher) because nothing
/// is written to the transcript while a permission dialog is open.
///
/// @unchecked Sendable: all mutable state is @MainActor-protected; the type is passed into a
/// background task only as a strong let reference used solely via MainActor.run.
@MainActor
public final class ClaudeTranscriptWatcher: @unchecked Sendable {
    public var onPayload: ((HookPayload) -> Void)?
    private var pollTask: Task<Void, Never>?

    /// A session whose newest in-file activity timestamp is older than this is treated as abandoned
    /// (crash, `kill -9`, or a normal `/exit` — Claude Code fires no hook we still listen to for
    /// either) and stops contributing to its cwd's resolved state. Above the longest observed
    /// tool_use -> tool_result gap (368s) across real local transcripts, with headroom for a single
    /// slow tool call — 300s previously used here was actually *below* that gap, so a >5-minute
    /// build/test/sleep tripped this and flipped a genuinely busy agent to idle. Safe to size
    /// generously now that `SessionActivityArbiter` picks the most-recently-active file per cwd: a
    /// lingering abandoned session can no longer out-vote a live sibling, it just takes longer to
    /// clear to idle on its own once nothing else is active for that cwd.
    private nonisolated static let activityWindow: TimeInterval = 900

    /// Bytes read from a newly discovered file's head, searched for the first `cwd`/`entrypoint`
    /// line. One local transcript's first `cwd` line starts at byte 6872 (a large leading
    /// `file-history-snapshot` entry pushed it past the previous 4096-byte read, silently dropping
    /// the file from tracking forever), so this is sized with real headroom above that.
    private nonisolated static let headerBytes = 16_384

    /// Bytes read from a newly discovered file's tail to seed its initial state without waiting for
    /// the next append.
    private nonisolated static let tailBytes: UInt64 = 8_192

    /// Cap on the unterminated remainder carried between polls (see `TrackedFile.carry`). A window
    /// this large without a single newline is not a partial line, it's a hung/malformed write; drop
    /// it rather than let `carry` grow unbounded.
    private nonisolated static let maxCarryBytes = 1_048_576

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
    /// here needs no lock or actor (same reasoning as CodexSessionWatcher.PollState).
    private final class PollState: @unchecked Sendable {
        var files: [URL: TrackedFile] = [:]
        // Task-subagent sidechains, tracked with the same TrackedFile machinery as top-level
        // transcripts but never contributing a state of their own — see subagentFiles()/scanOnce.
        var sidechainFiles: [URL: TrackedFile] = [:]
        // cwd -> last state string emitted, used to suppress duplicate emissions.
        var lastEmitted: [String: String] = [:]
    }

    /// One transcript file's tracked read position and last-known contribution to its cwd.
    /// `cwd == nil` marks a file deliberately not tracked (a headless `sdk-cli` run, or a complete
    /// header that never carries a `cwd`) so its header bytes aren't re-read on every 500ms poll.
    private struct TrackedFile {
        var cwd: String?
        var offset: UInt64 = 0
        // Bytes read but not yet resolved into a complete line — see splitAtLastNewline.
        var carry = Data()
        var state: String?
        var lastActivity: Date?
    }

    /// Bumps a `"running"` observation's `lastActivity` to the newest sidechain activity recorded
    /// for its `cwd`, if that's more recent — pure and filesystem-free (mirrors why
    /// `ClaudeTranscriptParser`/`SessionActivityArbiter` are split out from their watchers) so the
    /// motivating case is testable without touching disk: a live `Task` subagent keeps the
    /// *parent* transcript silent for its whole run, so without this a >15-minute subagent call
    /// ages the parent's "running" observation out of `activityWindow` exactly like a long single
    /// tool call does. Any other state (in particular `"done"`) passes through unchanged — a
    /// sidechain must never keep an already-finished parent observation artificially fresh, which
    /// would resurrect a finished turn's border after the agent has genuinely gone idle.
    nonisolated static func applySidechainLiveness(
        to observation: SessionActivityArbiter.SessionObservation,
        sidechainActivityByCwd: [String: Date]
    ) -> SessionActivityArbiter.SessionObservation {
        guard
            observation.state == "running",
            let sidechainActivity = sidechainActivityByCwd[observation.cwd],
            sidechainActivity > observation.lastActivity
        else { return observation }
        return SessionActivityArbiter.SessionObservation(
            cwd: observation.cwd, state: observation.state, lastActivity: sidechainActivity)
    }

    private nonisolated static func scanOnce(
        state: PollState,
        handler: @Sendable (HookPayload) async -> Void
    ) async {
        let now = Date()

        for fileURL in transcriptFiles() {
            guard isRecentlyTouched(fileURL, now: now) else {
                // Drop it rather than let a discovered-once file linger in `state.files` forever —
                // if it resumes later it's treated as newly discovered and re-seeded from its tail.
                state.files.removeValue(forKey: fileURL)
                continue
            }
            updateTracking(of: fileURL, in: &state.files)
        }

        // Task-subagent sidechains: read and tracked the same way, but only ever consulted for
        // liveness below (sidechainActivityByCwd) — a subagent's own decisive lines never drive
        // the worktree's published state.
        for fileURL in subagentFiles() {
            guard isRecentlyTouched(fileURL, now: now) else {
                state.sidechainFiles.removeValue(forKey: fileURL)
                continue
            }
            updateTracking(of: fileURL, in: &state.sidechainFiles)
        }

        // The newest sidechain activity per cwd — a live Task subagent keeps the *parent*
        // transcript silent for its whole run, so without this a >15-minute subagent call ages
        // the parent's "running" observation out of activityWindow exactly like a long single
        // tool call does (see activityWindow's doc comment). Reduced to a max per cwd since
        // several subagents can be in flight for the same worktree at once.
        var sidechainActivityByCwd: [String: Date] = [:]
        for tracked in state.sidechainFiles.values {
            guard let cwd = tracked.cwd, let lastActivity = tracked.lastActivity else { continue }
            if let existing = sidechainActivityByCwd[cwd], existing >= lastActivity { continue }
            sidechainActivityByCwd[cwd] = lastActivity
        }

        let observations = state.files.values.compactMap { tracked -> SessionActivityArbiter.SessionObservation? in
            guard
                let cwd = tracked.cwd,
                let sessionState = tracked.state,
                let lastActivity = tracked.lastActivity
            else { return nil }
            let observation = SessionActivityArbiter.SessionObservation(
                cwd: cwd, state: sessionState, lastActivity: lastActivity)
            return applySidechainLiveness(to: observation, sidechainActivityByCwd: sidechainActivityByCwd)
        }
        let resolved = SessionActivityArbiter.resolve(observations, now: now, window: activityWindow)
        for emission in SessionActivityArbiter.emissions(resolved: resolved, lastEmitted: state.lastEmitted) {
            state.lastEmitted[emission.cwd] = emission.state
            await handler(HookPayload(worktreePath: emission.cwd, state: emission.state, agent: "claude"))
        }
    }

    /// Cheap negative-only prefilter: a file whose mtime is already older than `activityWindow`
    /// cannot possibly contain activity inside the window, so it's skipped without opening it. The
    /// converse does NOT hold — mtime-fresh is not evidence of real activity, since Claude Code
    /// rewrites transcripts in place without appending (measured: 92 of 140 local transcripts have
    /// an mtime more than 5 minutes ahead of their newest in-file timestamp). That's why a
    /// mtime-fresh file still has its authoritative activity time read from its own content below,
    /// rather than trusted outright.
    private nonisolated static func isRecentlyTouched(_ fileURL: URL, now: Date) -> Bool {
        guard
            let attrs = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
            let mtime = attrs.contentModificationDate
        else { return false }
        return now.timeIntervalSince(mtime) < activityWindow
    }

    /// Shared by both `state.files` (top-level transcripts) and `state.sidechainFiles` (Task
    /// subagents) — the two are read and tracked identically, only `scanOnce` treats their results
    /// differently (one drives state, the other only bumps liveness).
    private nonisolated static func updateTracking(of fileURL: URL, in files: inout [URL: TrackedFile]) {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return }
        defer { try? handle.close() }

        guard var tracked = files[fileURL] else {
            guard let bound = bind(fileURL, handle: handle) else { return }
            files[fileURL] = bound
            return
        }
        guard tracked.cwd != nil else { return }  // sdk-cli / no-cwd file: never re-read its growth
        consumeGrowth(handle: handle, into: &tracked)
        files[fileURL] = tracked
    }

    /// Binds a newly discovered file: reads its header for cwd/entrypoint, seeds initial state from
    /// its tail (so an already-running session isn't briefly invisible), and fast-forwards the
    /// offset to EOF so the next poll only sees genuinely new growth. Returns `nil` (retry next
    /// poll) only while the file is still shorter than `headerBytes` and has no cwd yet — it may
    /// still be mid-write; once a file this short has a complete header with no cwd, or once any
    /// file reaches `headerBytes`, the absence is trusted and it's bound as untracked.
    private nonisolated static func bind(_ fileURL: URL, handle: FileHandle) -> TrackedFile? {
        // A fixed-size header read can cut a UTF-8 codepoint in half; `String(decoding:as:)` never
        // fails, corrupting at worst the one partial trailing line, which extractCwd/
        // extractEntrypoint's ASCII quote scan simply won't match rather than mis-parsing (mirrors
        // CodexSessionWatcher.parseSessionFile).
        let headerData = handle.readData(ofLength: headerBytes)
        // swiftlint:disable:next optional_data_string_conversion
        let headerText = String(decoding: headerData, as: UTF8.self)

        guard let discoveredCwd = ClaudeTranscriptParser.extractCwd(from: headerText) else {
            guard headerData.count >= headerBytes else { return nil }
            return TrackedFile(cwd: nil)
        }
        if ClaudeTranscriptParser.extractEntrypoint(from: headerText) == "sdk-cli" {
            // Headless `claude -p` run (DiffReviewKit's AgentRunner). Shares the worktree's cwd
            // with the interactive agent-pane session, so without this exclusion the row lights
            // green after every diff-review Reply/Apply.
            return TrackedFile(cwd: nil)
        }

        guard let size = try? handle.seekToEnd() else { return TrackedFile(cwd: discoveredCwd) }
        let start = size > tailBytes ? size - tailBytes : 0
        try? handle.seek(toOffset: start)
        var tail = handle.readDataToEndOfFile()
        // A byte-offset tail seek lands mid-line by construction (unless it happens to hit byte 0);
        // drop the leading partial line rather than risk mis-parsing it.
        if start > 0 { tail = ClaudeTranscriptParser.splitAtLastNewline(tail).remainder }

        var tracked = TrackedFile(cwd: discoveredCwd, offset: size)
        applyScan(of: tail, to: &tracked)
        return tracked
    }

    /// Reads and infers only from newly appended bytes, carrying any trailing unterminated line
    /// into the next poll instead of losing it. Combined with `ClaudeTranscriptParser.scan`
    /// treating a bare `stop_reason: tool_use` line as non-decisive, this is what keeps
    /// waitingForApproval race-free: the hook sets it right after the same tool_use bytes land in
    /// the transcript, and this watcher deliberately stays quiet on those bytes rather than racing
    /// the hook to declare "running".
    private nonisolated static func consumeGrowth(handle: FileHandle, into tracked: inout TrackedFile) {
        guard let size = try? handle.seekToEnd() else { return }
        if size < tracked.offset {
            tracked.offset = 0  // truncated/rotated
            tracked.carry = Data()
        }
        guard size > tracked.offset else { return }
        try? handle.seek(toOffset: tracked.offset)
        let combined = tracked.carry + handle.readDataToEndOfFile()
        // Safe to advance all the way to EOF: any bytes not resolved into a complete line below are
        // retained in `carry`, not discarded.
        tracked.offset = size
        applyScan(of: combined, to: &tracked)
    }

    private nonisolated static func applyScan(of data: Data, to tracked: inout TrackedFile) {
        let (complete, remainder) = ClaudeTranscriptParser.splitAtLastNewline(data)
        tracked.carry = remainder.count <= maxCarryBytes ? remainder : Data()
        // `complete` is cut at `\n`, and a newline byte can never occur inside a multi-byte UTF-8
        // sequence, so this decode is exact.
        // swiftlint:disable:next optional_data_string_conversion
        let scan = ClaudeTranscriptParser.scan(tail: String(decoding: complete, as: UTF8.self))
        if let newState = scan.state { tracked.state = newState }
        if let stamp = scan.lastActivity, stamp > (tracked.lastActivity ?? .distantPast) {
            tracked.lastActivity = stamp
        }
    }

    // MARK: - File helpers

    /// Every `<project>/` directory directly under `~/.claude/projects/`, shared by
    /// `transcriptFiles()` and `subagentFiles()`.
    private nonisolated static func projectDirs() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let projectsBase = home.appendingPathComponent(".claude/projects")
        guard
            let dirs = try? FileManager.default.contentsOfDirectory(
                at: projectsBase,
                includingPropertiesForKeys: [.isDirectoryKey]
            )
        else { return [] }
        return dirs.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
    }

    /// Every `*.jsonl` directly under a `~/.claude/projects/<project>/` directory. Non-recursive,
    /// so subagent sidechains — written to `<project>/<sessionId>/subagents/agent-*.jsonl`, one
    /// directory deeper than a top-level transcript — are naturally excluded here: `<sessionId>/`
    /// has no `.jsonl` extension itself, so it's dropped before ever being listed. `subagentFiles()`
    /// below is the sibling that looks one level deeper, for liveness only — see `scanOnce`.
    private nonisolated static func transcriptFiles() -> [URL] {
        projectDirs().flatMap { dir -> [URL] in
            guard
                let files = try? FileManager.default.contentsOfDirectory(
                    at: dir,
                    includingPropertiesForKeys: [.contentModificationDateKey]
                )
            else { return [] }
            return files.filter { $0.pathExtension == "jsonl" }
        }
    }

    /// Every `*.jsonl` under `<project>/<sessionId>/subagents/` — one `Task` tool subagent's own
    /// transcript, sharing its parent's `cwd` (verified: subagent files carry the same per-line
    /// `cwd`/`timestamp` fields as a top-level transcript) but tracking a different unit of work.
    /// Consulted only for liveness (`sidechainActivityByCwd` in `scanOnce`) — never a state source
    /// of its own, so a subagent's own start/finish never itself flips the worktree's indicator.
    private nonisolated static func subagentFiles() -> [URL] {
        projectDirs().flatMap { projectDir -> [URL] in
            guard
                let sessionDirs = try? FileManager.default.contentsOfDirectory(
                    at: projectDir,
                    includingPropertiesForKeys: [.isDirectoryKey]
                )
            else { return [] }
            return sessionDirs.flatMap { sessionDir -> [URL] in
                guard
                    (try? sessionDir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                else { return [] }
                let subagentsDir = sessionDir.appendingPathComponent("subagents")
                guard
                    let files = try? FileManager.default.contentsOfDirectory(
                        at: subagentsDir,
                        includingPropertiesForKeys: [.contentModificationDateKey]
                    )
                else { return [] }
                return files.filter { $0.pathExtension == "jsonl" }
            }
        }
    }
}
