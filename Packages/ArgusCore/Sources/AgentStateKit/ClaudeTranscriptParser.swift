import ArgusSupport
import Foundation

/// Pure parsing of Claude Code's session transcript JSONL files: extracting the session's working
/// directory and entrypoint, detecting the synthetic user message Claude Code writes when the user
/// presses Escape mid-turn, inferring running/done state from the most recent turn's `stop_reason`,
/// and extracting the newest in-file activity timestamp (the authoritative liveness signal — see
/// `scan(tail:)`). Kept separate from ClaudeTranscriptWatcher so it's testable without touching the
/// filesystem — mirrors CodexSessionParser's split from CodexSessionWatcher.
public enum ClaudeTranscriptParser {
    /// The synthetic user message Claude Code appends when the user presses Escape mid-turn. Two
    /// variants are observed in the wild: "[Request interrupted by user]" and "[Request interrupted
    /// by user for tool use]" — both start with this prefix. The `interruptedMessageId` field some
    /// entries carry is NOT a reliable discriminator (it's absent on the "for tool use" variant), so
    /// the text prefix is the signal matched on.
    static let interruptMarker = "[Request interrupted by user"

    /// Prefixes of the synthetic `user`-type entries Claude Code's CLI writes across the lifecycle
    /// of a local slash command (`/clear`, `/compact`, `/model`, `/exit`, …): the invocation itself
    /// (`<command-name>/clear</command-name>\n  <command-message>clear</command-message>…`), the
    /// caveat wrapper telling the model to ignore the replay (`<local-command-caveat>…`), and the
    /// command's own stdout echoed back for the transcript (`<local-command-stdout>…`). None of
    /// these start an agent turn, so without this check `inferState`'s plain `case "user": return
    /// "running"` misfires on them. `/clear` leaves the pane stuck on `running` because its
    /// `<command-name>` entry is the last line written. `/compact` is worse: it writes all three
    /// wrapper entries, and `<local-command-stdout>` — unmatched before this fix — lands last in
    /// file order (after the `isCompactSummary` entry, which is inserted earlier despite a similar
    /// timestamp), so the pane stayed on `running` even once compaction had fully finished.
    static let localCommandMarkers = ["<command-name>", "<local-command-caveat>", "<local-command-stdout>"]

    /// Extracts the `cwd` recorded on the first transcript line that carries one. Some leading
    /// lines (`{"type":"mode",…}`, `{"type":"permission-mode",…}`) carry only `type`/`sessionId`
    /// and no `cwd`, so this scans forward rather than assuming line 1. Reading from the start
    /// (not the tail) means a `cd` mid-session doesn't re-key the worktree the session is bound to.
    /// Avoids full JSON parsing per line for the common case via `JSONQuotedValue`, matching
    /// CodexSessionParser.extractCwd; escape sequences (an escaped `"` or `\\` in a path) are decoded.
    public static func extractCwd(from headerText: String) -> String? {
        firstQuotedValue(forKey: "cwd", in: headerText)
    }

    /// Extracts `entrypoint` ("cli" for an interactive session, "sdk-cli" for a headless
    /// `claude -p` run) the same way as `extractCwd`. DiffReviewKit's AgentRunner spawns headless
    /// runs with the worktree as cwd, so without this the watcher can't tell a diff-review
    /// Reply/Apply from the interactive agent-pane session sharing the same cwd — both would
    /// otherwise flip the worktree's indicator to done when the headless run finishes.
    public static func extractEntrypoint(from headerText: String) -> String? {
        firstQuotedValue(forKey: "entrypoint", in: headerText)
    }

    private static func firstQuotedValue(forKey key: String, in text: String) -> String? {
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if let value = JSONQuotedValue.first(forKey: key, in: line) { return value }
        }
        return nil
    }

    /// True if `line` is the synthetic user entry Claude Code writes on Escape-interrupt. Requires
    /// a decoded `type == "user"` entry with a text block starting with the marker — a cheap
    /// substring prefilter alone would misfire on assistant text or tool output that merely quotes
    /// the marker (e.g. a transcript that echoes another transcript's contents back).
    public static func isInterrupt(line: String) -> Bool {
        guard line.contains(interruptMarker) else { return false }
        guard
            let data = line.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            obj["type"] as? String == "user"
        else { return false }
        return firstText(in: obj["message"] as? [String: Any])?.hasPrefix(interruptMarker) == true
    }

    /// True if `line` is one of the synthetic entries Claude Code's CLI writes across a local slash
    /// command's lifecycle. Requires a decoded entry whose text content starts with one of
    /// `localCommandMarkers`, mirroring `isInterrupt`'s decode-then-check shape so a tool result or
    /// assistant text that merely quotes one of the tags can't misfire.
    ///
    /// Two on-disk shapes exist for this: older/still-current-for-`<command-name>` transcripts
    /// write it as `type: "user"` with the marker as the message text; current Claude Code (2.1.x)
    /// writes the trailing `<local-command-stdout>` echo — the entry that actually decides
    /// `/clear`/`/compact`'s tail — as `type: "system", subtype: "local_command"` with the marker
    /// in `content` instead. Matching only the `user` shape leaves `/clear` and `/compact` stuck on
    /// `running` on current CLIs, since their decisive last line no longer round-trips through it.
    public static func isLocalCommand(line: String) -> Bool {
        guard localCommandMarkers.contains(where: { line.contains($0) }) else { return false }
        guard
            let data = line.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let text = localCommandText(in: obj)
        else { return false }
        return localCommandMarkers.contains { text.hasPrefix($0) }
    }

    private static func localCommandText(in obj: [String: Any]) -> String? {
        switch obj["type"] as? String {
        case "user": return firstText(in: obj["message"] as? [String: Any])
        case "system" where obj["subtype"] as? String == "local_command": return obj["content"] as? String
        default: return nil
        }
    }

    /// True if `line` is the `isCompactSummary` entry `/compact` seeds the new context with — the
    /// prior conversation's summary, replayed as a `user`-role message so the model can read it.
    /// It carries no `<command-name>`-style text marker (its content is the freeform summary), so
    /// it needs its own field-based check; without it, a poll window that ends right after this
    /// entry (before the trailing `<local-command-stdout>` line lands) would still misfire the
    /// generic `case "user": return "running"` branch.
    public static func isCompactSummary(line: String) -> Bool {
        guard line.contains("\"isCompactSummary\"") else { return false }
        guard
            let data = line.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            obj["type"] as? String == "user"
        else { return false }
        return obj["isCompactSummary"] as? Bool == true
    }

    /// The result of one `scan(tail:)` call: the newest decisive state found in the window (`nil`
    /// when nothing in it is decisive), and the newest entry `timestamp` found in it (`nil` when
    /// the window has none). The two are independent: a session mid-tool-call keeps writing fresh
    /// `tool_result`/`attachment` entries whose timestamps are newer than its last *decisive* line.
    public struct TranscriptScan: Equatable, Sendable {
        public let state: String?
        public let lastActivity: Date?
    }

    /// Scans tail lines in reverse for the first decisive state and, independently, the newest
    /// in-file `timestamp` in the window — the caller's authoritative "is this session live" signal.
    /// A transcript's file-system mtime is NOT that signal: Claude Code rewrites transcripts in
    /// place without appending (measured: 92 of 140 local transcripts have an mtime more than 5
    /// minutes ahead of their newest in-file timestamp, some by 40+ days), so a stale-content file
    /// whose mtime was merely touched would otherwise look freshly active and re-surface its last
    /// `stop_reason` as if the agent had just finished.
    ///
    /// `lastActivity` must be the max timestamp over the window, not the last line's: 46 of 140
    /// local transcripts end in untimestamped bookkeeping lines (`mode`, `last-prompt`, `ai-title`,
    /// `file-history-snapshot`, …) appended after the conversational entry that actually carries
    /// one. Bogus/future timestamps are not filtered here — this stays pure/time-free; the caller
    /// (`SessionActivityArbiter`) rejects those against `now`.
    ///
    /// Decisive-state rules:
    /// - interrupt marker -> "idle"
    /// - local slash command entry (invocation, caveat, stdout, or compact summary) -> "idle"
    /// - assistant entry whose `stop_reason` is `end_turn`/`stop_sequence` -> "done"
    /// - any other (non-interrupt, non-command, non-isMeta) user entry -> "running"
    ///
    /// An assistant entry whose `stop_reason` is `tool_use` (or unset — a message still being
    /// generated) is deliberately NOT decisive and is skipped rather than mapped to "running".
    /// Verified against real transcripts: every content block of one assistant message — thinking,
    /// text, tool_use — is written with the SAME final `stop_reason` already attached, all at once,
    /// once the whole message resolves. So a freshly-written `stop_reason: tool_use` line means
    /// Claude has just decided to call a tool — precisely the instant a permission check may or may
    /// not happen — and is indistinguishable from "already executing, no approval needed" purely
    /// from the transcript. Mapping it to "running" would race the PermissionRequest hook and could
    /// silently overwrite `waitingForApproval` back to `running` while the dialog is still open.
    /// The next unambiguous signal — a `tool_result` (a `user`-type entry either way) once the tool
    /// actually runs — correctly re-asserts "running" once the ambiguity resolves.
    ///
    /// An `isMeta: true` user entry (skill-loading notices, image placeholders — routinely written
    /// mid-turn) is likewise not decisive; without this check a skill notice landing as the newest
    /// line in a poll window would misreport "running" for a turn that may already be done.
    public static func scan(tail tailText: String) -> TranscriptScan {
        var state: String?
        var newestActivity: Date?
        for line in tailText.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
            let lineStr = String(line)
            if state == nil { state = decisiveState(ofLine: lineStr) }
            // Compare parsed instants, not strings: `…:00Z` sorts after `…:00.500Z` lexically, and
            // two offsets for the same moment never compare equal as text.
            if let activity = timestampField(in: lineStr).flatMap(parseTimestamp),
                newestActivity.map({ activity > $0 }) ?? true
            {
                newestActivity = activity
            }
        }
        return TranscriptScan(state: state, lastActivity: newestActivity)
    }

    /// Convenience for callers that only need the state half of `scan(tail:)`.
    public static func inferState(fromTail tailText: String) -> String? {
        scan(tail: tailText).state
    }

    private static func decisiveState(ofLine lineStr: String) -> String? {
        if isInterrupt(line: lineStr) { return "idle" }
        if isLocalCommand(line: lineStr) { return "idle" }
        if isCompactSummary(line: lineStr) { return "idle" }

        guard
            let data = lineStr.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = obj["type"] as? String
        else { return nil }

        switch type {
        case "assistant":
            let message = obj["message"] as? [String: Any]
            switch message?["stop_reason"] as? String {
            case "end_turn", "stop_sequence": return "done"
            default: return nil
            }

        case "user":
            guard obj["isMeta"] as? Bool != true else { return nil }
            return "running"

        default:
            return nil
        }
    }

    /// Splits `data` at its last newline into the complete-lines prefix and the unterminated
    /// remainder the caller must carry into the next read window. A poll window's byte boundary is
    /// not a line boundary, so without this a decisive line straddling two windows is missed in
    /// both — the trailing fragment fails to decode as JSON and the leading fragment of the next
    /// window does too. Cutting at `\n` also makes `String(decoding:as:)` lossless on the complete
    /// half: a newline byte can never occur inside a multi-byte UTF-8 sequence, so this cut cannot
    /// split a codepoint.
    public static func splitAtLastNewline(_ data: Data) -> (complete: Data, remainder: Data) {
        guard let newlineIndex = data.lastIndex(of: 0x0A) else { return (Data(), data) }
        let completeEnd = data.index(after: newlineIndex)
        return (Data(data[data.startIndex..<completeEnd]), Data(data[completeEnd...]))
    }

    /// The entry's own top-level `timestamp`. A single occurrence of the key is taken as-is (the
    /// common case — one cheap scan). Two or more means a nested object (a `tool_use` input, a
    /// `toolUseResult`) carries a `timestamp` key too, and which one the scan hits first depends on
    /// field order, so that line is decoded properly and its top-level value read instead.
    private static func timestampField(in line: String) -> String? {
        switch JSONQuotedValue.occurrences(ofKey: "timestamp", in: line) {
        case 0:
            return nil

        case 1:
            return JSONQuotedValue.first(forKey: "timestamp", in: line)

        default:
            guard
                let data = line.data(using: .utf8),
                let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            return obj["timestamp"] as? String
        }
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        ISO8601Timestamp.parse(value)
    }

    private static func firstText(in message: [String: Any]?) -> String? {
        guard let content = message?["content"] else { return nil }
        if let text = content as? String { return text }
        guard let blocks = content as? [[String: Any]] else { return nil }
        for block in blocks {
            if let text = block["text"] as? String { return text }
        }
        return nil
    }
}
