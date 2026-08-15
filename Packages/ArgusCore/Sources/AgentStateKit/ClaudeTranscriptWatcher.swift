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

    /// A worktree whose transcript hasn't grown in this long is treated as abandoned (crash, kill
    /// -9, or a normal `/exit` — Claude Code fires no hook we still listen to for either) and
    /// cleared to idle. Comfortably above the longest observed tool_use -> tool_result gap (368s)
    /// across real local transcripts, so a genuinely busy agent never trips it.
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
    /// here needs no lock or actor (same reasoning as CodexSessionWatcher.PollState).
    private final class PollState: @unchecked Sendable {
        // Byte offset already consumed, per transcript file.
        var offsets: [URL: UInt64] = [:]
        // Worktree cwd a transcript file is bound to, fixed at first discovery.
        var cwds: [URL: String] = [:]
        // cwd -> last state emitted, used to suppress duplicate emissions.
        var lastEmitted: [String: String] = [:]
    }

    private nonisolated static func scanOnce(
        state: PollState,
        handler: @Sendable (HookPayload) async -> Void
    ) async {
        let now = Date()

        for fileURL in transcriptFiles() {
            guard
                let attrs = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
                let mtime = attrs.contentModificationDate
            else { continue }
            let age = now.timeIntervalSince(mtime)

            guard age < staleTimeout else {
                await clearIfTracked(fileURL, state: state, handler: handler)
                continue
            }

            guard let handle = try? FileHandle(forReadingFrom: fileURL) else { continue }
            defer { try? handle.close() }

            if let cwd = state.cwds[fileURL] {
                await scanKnownFile(fileURL, cwd: cwd, handle: handle, state: state, handler: handler)
            } else {
                await scanNewFile(fileURL, handle: handle, state: state, handler: handler)
            }
        }
    }

    /// A file we were never tracking is just an old, already-finished session — nothing to do.
    /// One we *were* tracking just went quiet (crash, `kill -9`, or a normal `/exit` — no hook
    /// covers either): clear its worktree to idle and stop tracking it.
    private nonisolated static func clearIfTracked(
        _ fileURL: URL,
        state: PollState,
        handler: @Sendable (HookPayload) async -> Void
    ) async {
        guard let cwd = state.cwds[fileURL] else { return }
        await emit(cwd: cwd, sessionState: "idle", state: state, handler: handler)
        state.cwds.removeValue(forKey: fileURL)
        state.offsets.removeValue(forKey: fileURL)
    }

    /// Reads and infers only from newly appended bytes. Combined with
    /// ClaudeTranscriptParser.inferState treating a bare `stop_reason: tool_use` line as
    /// non-decisive (see its doc comment), this is what keeps waitingForApproval race-free: the
    /// hook sets it right after the same tool_use bytes land in the transcript, and this watcher
    /// deliberately stays quiet on those bytes rather than racing the hook to declare "running".
    private nonisolated static func scanKnownFile(
        _ fileURL: URL,
        cwd: String,
        handle: FileHandle,
        state: PollState,
        handler: @Sendable (HookPayload) async -> Void
    ) async {
        guard let size = try? handle.seekToEnd() else { return }
        let prevOffset = state.offsets[fileURL] ?? size
        if size < prevOffset {
            state.offsets[fileURL] = 0  // truncated/rotated
            return
        }
        guard size > prevOffset else { return }
        try? handle.seek(toOffset: prevOffset)
        let newData = handle.readDataToEndOfFile()
        state.offsets[fileURL] = size
        guard
            let newText = String(data: newData, encoding: .utf8),
            let sessionState = ClaudeTranscriptParser.inferState(fromTail: newText)
        else { return }
        await emit(cwd: cwd, sessionState: sessionState, state: state, handler: handler)
    }

    /// Binds a newly discovered file's cwd, seeds initial state from its tail (so an
    /// already-running session isn't briefly invisible), then fast-forwards the offset to EOF so
    /// the next poll only sees genuinely new growth.
    private nonisolated static func scanNewFile(
        _ fileURL: URL,
        handle: FileHandle,
        state: PollState,
        handler: @Sendable (HookPayload) async -> Void
    ) async {
        let headerData = handle.readData(ofLength: 4_096)
        guard
            let headerText = String(data: headerData, encoding: .utf8),
            let discoveredCwd = ClaudeTranscriptParser.extractCwd(from: headerText)
        else { return }
        state.cwds[fileURL] = discoveredCwd

        guard let size = try? handle.seekToEnd() else { return }
        let tailSize = min(size, 8_192)
        try? handle.seek(toOffset: size - tailSize)
        let tailData = handle.readDataToEndOfFile()
        state.offsets[fileURL] = size

        guard
            let tailText = String(data: tailData, encoding: .utf8),
            let seededState = ClaudeTranscriptParser.inferState(fromTail: tailText)
        else { return }
        await emit(cwd: discoveredCwd, sessionState: seededState, state: state, handler: handler)
    }

    private nonisolated static func emit(
        cwd: String,
        sessionState: String,
        state: PollState,
        handler: @Sendable (HookPayload) async -> Void
    ) async {
        guard state.lastEmitted[cwd] != sessionState else { return }
        state.lastEmitted[cwd] = sessionState
        await handler(HookPayload(worktreePath: cwd, state: sessionState, agent: "claude"))
    }

    // MARK: - File helpers

    /// Every `*.jsonl` directly under a `~/.claude/projects/<project>/` directory. Non-recursive,
    /// so subagent sidechains under `<project>/subagents/*.jsonl` are naturally excluded — the
    /// interrupt marker and stop_reason of interest live in the main transcript, not a subagent's.
    private nonisolated static func transcriptFiles() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let projectsBase = home.appendingPathComponent(".claude/projects")
        guard
            let projectDirs = try? FileManager.default.contentsOfDirectory(
                at: projectsBase,
                includingPropertiesForKeys: [.isDirectoryKey]
            )
        else { return [] }

        var results: [URL] = []
        for dir in projectDirs {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
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
}
