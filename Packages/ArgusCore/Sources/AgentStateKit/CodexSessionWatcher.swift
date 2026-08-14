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

    /// Cross-poll mutable state (last-seen mtimes / last-emitted state per cwd), threaded through
    /// scanOnce by PollingTask's action closure rather than captured `var`s in a loop. Deliberately
    /// not actor-isolated: PollingTask calls the action strictly sequentially — one call finishes
    /// before the next starts — so plain mutation here needs no lock or actor.
    private final class PollState: @unchecked Sendable {
        var lastMtimes: [URL: Date] = [:]
        // cwd -> last state string we emitted, used to suppress duplicate emissions
        var lastEmitted: [String: String] = [:]
    }

    private nonisolated static func scanOnce(
        state: PollState,
        handler: @Sendable (HookPayload) async -> Void
    ) async {
        let sessionFiles = recentSessionFiles()
        let now = Date()

        for fileURL in sessionFiles {
            guard
                let attrs = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
                let mtime = attrs.contentModificationDate
            else { continue }

            // Skip files older than 120 seconds
            guard now.timeIntervalSince(mtime) < 120 else {
                state.lastMtimes.removeValue(forKey: fileURL)
                continue
            }

            let prevMtime = state.lastMtimes[fileURL]
            state.lastMtimes[fileURL] = mtime

            // Only reparse if the file actually changed
            guard prevMtime.map({ mtime > $0 }) ?? true else { continue }

            guard let (cwd, sessionState) = parseSessionFile(at: fileURL) else { continue }

            if state.lastEmitted[cwd] != sessionState {
                state.lastEmitted[cwd] = sessionState
                let payload = HookPayload(worktreePath: cwd, state: sessionState, agent: "codex")
                await handler(payload)
            }
        }

        // Clean up cache entries for cwds whose files are no longer recent
        let activeCwds = Set(
            sessionFiles.compactMap { url -> String? in
                guard
                    let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                    let mtime = attrs.contentModificationDate,
                    now.timeIntervalSince(mtime) < 120
                else { return nil }
                return parseCwd(at: url)
            })
        state.lastEmitted = state.lastEmitted.filter { activeCwds.contains($0.key) }
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

    /// Returns the `cwd` from the first `session_meta` line of the file, without reading the whole file.
    private nonisolated static func parseCwd(at url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        // cwd appears at ~byte 156; 512 bytes is always enough regardless of system-prompt length
        let data = handle.readData(ofLength: 512)
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return extractCwd(from: text)
    }

    /// Reads the session file and returns `(cwd, state)` by parsing the header and tail.
    private nonisolated static func parseSessionFile(at url: URL) -> (cwd: String, state: String)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        // cwd appears at ~byte 156; 512 bytes is always enough regardless of system-prompt length
        let headerData = handle.readData(ofLength: 512)
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
        guard let cwd = extractCwd(from: headerText) else { return nil }

        // Seek to tail to find the last relevant event_msg entries
        guard
            let size = try? handle.seekToEnd(),
            size > 0
        else { return (cwd, "running") }

        let tailSize: UInt64 = min(size, 4_096)
        try? handle.seek(toOffset: size - tailSize)
        let tailData = handle.readDataToEndOfFile()
        guard let tailText = String(data: tailData, encoding: .utf8) else { return (cwd, "running") }

        let state = inferState(from: tailText)
        return (cwd, state)
    }

    /// Extracts the `cwd` value by searching for `"cwd":"<path>"` in raw bytes.
    /// Avoids full JSON parsing — the session_meta first line is ~22 KB due to the embedded
    /// system prompt, so parsing it as JSON from a fixed-size header read would fail.
    /// macOS paths cannot contain `"` so a simple quote-delimited scan is safe.
    private nonisolated static func extractCwd(from header: String) -> String? {
        guard let keyRange = header.range(of: #""cwd":""#) else { return nil }
        let afterKey = header[keyRange.upperBound...]
        guard let endQuote = afterKey.firstIndex(of: "\"") else { return nil }
        let value = String(afterKey[..<endQuote])
        return value.isEmpty ? nil : value
    }

    /// Scans the last lines of the tail text for `event_msg` entries and returns
    /// `"done"` / `"running"` based on the most recent `task_complete` or `task_started`.
    private nonisolated static func inferState(from tailText: String) -> String {
        let lines = tailText.split(separator: "\n", omittingEmptySubsequences: true)
        for line in lines.reversed() {
            guard
                let data = line.data(using: .utf8),
                let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                obj["type"] as? String == "event_msg",
                let payload = obj["payload"] as? [String: Any],
                let eventType = payload["type"] as? String
            else { continue }

            switch eventType {
            case "task_complete", "turn_aborted":
                return "done"

            case "task_started":
                return "running"

            default:
                continue
            }
        }
        return "running"
    }
}
