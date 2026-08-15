import Foundation

/// Pure parsing of Claude Code's session transcript JSONL files: extracting the session's working
/// directory, detecting the synthetic user message Claude Code writes when the user presses Escape
/// mid-turn, and inferring running/done state from the most recent turn's `stop_reason`. Kept
/// separate from ClaudeTranscriptWatcher so it's testable without touching the filesystem — mirrors
/// CodexSessionParser's split from CodexSessionWatcher.
public enum ClaudeTranscriptParser {
    /// The synthetic user message Claude Code appends when the user presses Escape mid-turn. Two
    /// variants are observed in the wild: "[Request interrupted by user]" and "[Request interrupted
    /// by user for tool use]" — both start with this prefix. The `interruptedMessageId` field some
    /// entries carry is NOT a reliable discriminator (it's absent on the "for tool use" variant), so
    /// the text prefix is the signal matched on.
    static let interruptMarker = "[Request interrupted by user"

    /// Prefix of the synthetic `user`-type entry Claude Code's CLI writes for every local slash
    /// command (`/clear`, `/compact`, `/model`, `/exit`, …) — content looks like
    /// `<command-name>/clear</command-name>\n  <command-message>clear</command-message>…`. These
    /// never start an agent turn, so without this check `inferState`'s plain `case "user": return
    /// "running"` misfires on them — most visibly on `/clear`, which leaves the pane stuck showing
    /// `running` (or whatever state preceded it) until the 5-minute stale timeout, since no
    /// decisive entry ever follows to correct it.
    static let localCommandMarker = "<command-name>"

    /// Extracts the `cwd` recorded on the first transcript line that carries one. Some leading
    /// lines (`{"type":"mode",…}`, `{"type":"permission-mode",…}`) carry only `type`/`sessionId`
    /// and no `cwd`, so this scans forward rather than assuming line 1. Reading from the start
    /// (not the tail) means a `cd` mid-session doesn't re-key the worktree the session is bound to.
    /// Avoids full JSON parsing per line for the common case via a quote-delimited scan, matching
    /// CodexSessionParser.extractCwd — macOS paths cannot contain `"` so this is safe.
    public static func extractCwd(from headerText: String) -> String? {
        for line in headerText.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let keyRange = line.range(of: #""cwd":""#) else { continue }
            let afterKey = line[keyRange.upperBound...]
            guard let endQuote = afterKey.firstIndex(of: "\"") else { continue }
            let value = String(afterKey[..<endQuote])
            if !value.isEmpty { return value }
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

    /// True if `line` is the synthetic user entry Claude Code's CLI writes for a local slash
    /// command. Requires a decoded `type == "user"` entry whose text content starts with the
    /// marker, mirroring `isInterrupt`'s decode-then-check shape so a tool result or assistant
    /// text that merely quotes `<command-name>` can't misfire.
    public static func isLocalCommand(line: String) -> Bool {
        guard line.contains(localCommandMarker) else { return false }
        guard
            let data = line.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            obj["type"] as? String == "user"
        else { return false }
        return firstText(in: obj["message"] as? [String: Any])?.hasPrefix(localCommandMarker) == true
    }

    /// Scans tail lines in reverse and returns the first decisive state, or `nil` if nothing in
    /// the given text is decisive.
    /// - interrupt marker -> "idle"
    /// - local slash command entry -> "idle"
    /// - assistant entry whose `stop_reason` is `end_turn`/`stop_sequence` -> "done"
    /// - any other (non-interrupt, non-command) user entry -> "running"
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
    public static func inferState(fromTail tailText: String) -> String? {
        let lines = tailText.split(separator: "\n", omittingEmptySubsequences: true)
        for line in lines.reversed() {
            let lineStr = String(line)
            if isInterrupt(line: lineStr) { return "idle" }
            if isLocalCommand(line: lineStr) { return "idle" }

            guard
                let data = lineStr.data(using: .utf8),
                let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let type = obj["type"] as? String
            else { continue }

            switch type {
            case "assistant":
                let message = obj["message"] as? [String: Any]
                switch message?["stop_reason"] as? String {
                case "end_turn", "stop_sequence": return "done"
                default: continue
                }

            case "user":
                return "running"

            default:
                continue
            }
        }
        return nil
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
