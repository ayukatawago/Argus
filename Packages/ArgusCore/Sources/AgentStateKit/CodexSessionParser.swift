import Foundation

/// Pure parsing of Codex CLI session JSONL files: extracting the session's working directory and
/// inferring its current running/done state from its most recent event. Moved out of
/// CodexSessionWatcher so it's testable without touching the filesystem.
public enum CodexSessionParser {
    /// Extracts the `cwd` value by searching for `"cwd":"<path>"` in raw text.
    /// Avoids full JSON parsing — the session_meta first line is ~22 KB due to the embedded
    /// system prompt, so parsing it as JSON from a fixed-size header read would fail.
    /// macOS paths cannot contain `"` so a simple quote-delimited scan is safe.
    public static func extractCwd(from header: String) -> String? {
        guard let keyRange = header.range(of: #""cwd":""#) else { return nil }
        let afterKey = header[keyRange.upperBound...]
        guard let endQuote = afterKey.firstIndex(of: "\"") else { return nil }
        let value = String(afterKey[..<endQuote])
        return value.isEmpty ? nil : value
    }

    /// Scans the last lines of the tail text for `event_msg` entries and returns
    /// `"done"` / `"running"` based on the most recent `task_complete`/`turn_aborted` or
    /// `task_started`. Malformed lines and unrelated event types are skipped. Defaults to
    /// `"running"` when no recognized event is found.
    public static func inferState(from tailText: String) -> String {
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
