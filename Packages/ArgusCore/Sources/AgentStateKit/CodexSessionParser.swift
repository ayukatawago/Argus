import Foundation

/// Pure parsing of Codex CLI session JSONL files: extracting the session's working directory and
/// thread source, and inferring its current running/done/waitingForApproval state from its most
/// recent event. Moved out of CodexSessionWatcher so it's testable without touching the filesystem.
public enum CodexSessionParser {
    /// Extracts the `cwd` value by searching for `"cwd":"<path>"` in raw text.
    /// Avoids full JSON parsing — the session_meta first line is ~22 KB due to the embedded
    /// system prompt, so parsing it as JSON from a fixed-size header read would fail.
    /// macOS paths cannot contain `"` so a simple quote-delimited scan is safe.
    public static func extractCwd(from header: String) -> String? {
        extractQuotedValue(forKey: "cwd", from: header)
    }

    /// Extracts the `thread_source` value (`"user"` or `"subagent"`) the same way as `extractCwd`.
    /// Subagent rollouts share their parent's cwd, so this is how the watcher tells a subagent's
    /// own file apart from the top-level session driving the worktree indicator.
    public static func extractThreadSource(from header: String) -> String? {
        extractQuotedValue(forKey: "thread_source", from: header)
    }

    private static func extractQuotedValue(forKey key: String, from header: String) -> String? {
        guard let keyRange = header.range(of: "\"\(key)\":\"") else { return nil }
        let afterKey = header[keyRange.upperBound...]
        guard let endQuote = afterKey.firstIndex(of: "\"") else { return nil }
        let value = String(afterKey[..<endQuote])
        return value.isEmpty ? nil : value
    }

    /// Scans the last lines of the tail text for `event_msg` entries and returns the state implied
    /// by the most recent recognized one. Malformed lines and unrelated event types are skipped.
    /// Returns `nil` when nothing decisive is found in the tail, mirroring
    /// `ClaudeTranscriptParser.inferState(fromTail:)` — the caller keeps whatever state is already
    /// published rather than guessing.
    public static func inferState(from tailText: String) -> String? {
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
            case "task_complete", "turn_complete":
                return "done"

            // Codex has no dedicated interrupt marker like Claude's — abandoning a turn via Esc
            // surfaces as turn_aborted. Mapped to idle (not done) so the border clears the same way
            // Claude's Escape-interrupt does, rather than showing the green "awaiting reply" state.
            case "turn_aborted":
                return "idle"

            case "task_started", "turn_started":
                return "running"

            // Unverified: this machine's Codex projects are all trust_level = "trusted", so no
            // approval prompt has ever been observed in a real rollout file. These event names come
            // from Codex 0.147's EventMsg enum (recovered via `strings` on the binary); if Codex
            // doesn't actually persist them to the rollout JSONL, this branch is simply never hit.
            case "exec_approval_request", "apply_patch_approval_request", "request_user_input", "elicitation_request":
                return "waitingForApproval"

            default:
                continue
            }
        }
        return nil
    }
}
