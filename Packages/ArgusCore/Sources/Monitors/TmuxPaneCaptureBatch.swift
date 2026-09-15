import Foundation

/// Pure helpers for batching several tmux panes' `capture-pane` output into a single subprocess
/// call — used by `AgentPaneDisplayWatcher` (App/, which alone can see live tmux sessions) to
/// scrape every live Claude/Codex pane's on-screen state once a second in one round trip instead
/// of one process spawn per pane. Lives alongside `TmuxPaneParser`/`TmuxWindowParser` — this
/// package's established home for pure tmux-output parsing.
public enum TmuxPaneCaptureBatch {
    /// A delimiter tmux's `display-message -p` can print back verbatim. `#` is a format-escape
    /// character in tmux's own format strings (`###foo` prints as `##foo`, verified live), so the
    /// delimiter must not contain one.
    public static let delimiterPrefix = "ARGUS_PANE:"

    /// Parses `tmux list-panes -a -F "#{session_name}|#{pane_height}"` output into a session name
    /// -> pane height dictionary. Lines that don't match the expected shape, or whose height isn't
    /// a valid integer, are skipped.
    public static func parseSessionHeights(from output: String) -> [String: Int] {
        var result: [String: Int] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "|", maxSplits: 1)
            guard parts.count == 2, let height = Int(parts[1]) else { continue }
            result[String(parts[0])] = height
        }
        return result
    }

    /// Builds the argument list for one chained `tmux` invocation (run directly via `Process`, not
    /// a shell, so each `;` must be its own array element rather than a shell-escaped `\;` — verified
    /// live) that captures every session in `sessionNames`, each preceded by a `display-message`
    /// delimiter line carrying its name so `splitCapture` can attribute output back to the right
    /// session.
    ///
    /// Each capture is windowed to that session's own on-screen tail via `-S <height -
    /// contextLines>` when its height is known and exceeds `contextLines` (verified live: `-S`
    /// counts forward from the top of the visible window, so this value yields exactly the last
    /// `contextLines` lines — measured 3.6KB windowed vs 8.4KB for a full-pane capture on a
    /// same-size real pane) — otherwise the session is captured in full, a safe fallback for a
    /// session whose height wasn't reported.
    ///
    /// A session vanishing mid-batch aborts everything chained after it (tmux's `can't find pane`
    /// error, verified live) — by design, not a bug to route around: the caller treats this as
    /// "no data this poll" for every session ordered after the failure and simply re-lists on the
    /// next poll; nothing else in this pipeline assumes every requested session's data arrives.
    public static func captureArguments(
        sessionNames: [String],
        heightBySession: [String: Int],
        contextLines: Int = 16
    ) -> [String] {
        var args: [String] = []
        for (index, session) in sessionNames.enumerated() {
            if index > 0 { args.append(";") }
            args.append(contentsOf: ["display-message", "-p", "\(delimiterPrefix)\(session)"])
            args.append(";")
            args.append(contentsOf: ["capture-pane", "-p", "-J", "-t", session])
            if let height = heightBySession[session], height > contextLines {
                args.append(contentsOf: ["-S", "\(height - contextLines)"])
            }
        }
        return args
    }

    /// Splits one batched capture's combined stdout back into a session name -> pane text
    /// dictionary, using the `ARGUS_PANE:<session>` delimiter lines `captureArguments` interleaves.
    /// A session whose delimiter never appears at all (batch aborted before reaching it — see
    /// `captureArguments`) is simply absent from the result, not present with empty text; the one
    /// session whose own `capture-pane` failed (its delimiter printed, but nothing followed before
    /// the abort) does get an empty-string entry — callers must treat that the same as "no data",
    /// not as a legitimate empty pane, since a real tmux pane is never actually blank.
    public static func splitCapture(_ output: String, sessionNames: [String]) -> [String: String] {
        var result: [String: String] = [:]
        var currentSession: String?
        var currentLines: [Substring] = []
        func flush() {
            if let session = currentSession {
                result[session] = currentLines.joined(separator: "\n")
            }
            currentLines = []
        }
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix(delimiterPrefix) {
                flush()
                currentSession = String(line.dropFirst(delimiterPrefix.count))
            } else {
                currentLines.append(line)
            }
        }
        flush()
        return result
    }
}
