import Foundation

/// Arbitrates the many session files that can be bound to one worktree — the Argus project dir
/// alone accumulates over a dozen Claude transcripts across sessions — down to the one state its
/// sidebar/window indicator shows. Pure and filesystem-free so it's testable without a
/// watcher; shared by `ClaudeTranscriptWatcher` and `CodexSessionWatcher`, which each reduce their
/// own file set to `SessionObservation`s before calling in.
public enum SessionActivityArbiter {
    /// One session file's contribution to a worktree's published state: the state its own tail
    /// implies, and the newest activity timestamp backing that read (an in-file entry timestamp for
    /// Claude, whose mtime is not trustworthy — see `ClaudeTranscriptParser.scan(tail:)` — or simply
    /// mtime for Codex, whose rollouts are append-only and never rewritten in place).
    public struct SessionObservation: Equatable, Sendable {
        public let cwd: String
        public let state: String
        public let lastActivity: Date

        public init(cwd: String, state: String, lastActivity: Date) {
            self.cwd = cwd
            self.state = state
            self.lastActivity = lastActivity
        }
    }

    /// One state change (or clearing `idle`) the watcher should hand to `AgentStateBus`.
    public struct StateEmission: Equatable, Sendable {
        public let cwd: String
        public let state: String

        public init(cwd: String, state: String) {
            self.cwd = cwd
            self.state = state
        }
    }

    /// Reduces every observation to at most one state per cwd: among observations whose
    /// `lastActivity` falls inside `window` (and isn't in the future), the most recently active
    /// file wins. A cwd with no such observation is simply absent from the result — `emissions`
    /// below is what turns that absence into an `idle` clear.
    ///
    /// Newest-activity-wins, not a priority aggregate (waitingForApproval > done > running > idle):
    /// a priority aggregate would let an abandoned mid-turn "running" file that's still inside the
    /// window outrank — and mask — a live sibling session's genuine "done", losing the product's
    /// primary attention signal. Newest-wins instead handles the motivating case directly: a live
    /// agent pane keeps writing (tool_result, attachment, …) so it out-dates a just-finished
    /// sibling, and the sibling's "done" only takes over once the live pane itself goes quiet.
    ///
    /// A future-dated observation is dropped outright rather than allowed to pin a cwd forever —
    /// clock skew or a malformed timestamp shouldn't freeze the indicator.
    public static func resolve(
        _ observations: [SessionObservation],
        now: Date,
        window: TimeInterval
    ) -> [String: String] {
        var winners: [String: SessionObservation] = [:]
        for observation in observations {
            guard observation.lastActivity <= now else { continue }
            guard now.timeIntervalSince(observation.lastActivity) < window else { continue }
            guard let current = winners[observation.cwd] else {
                winners[observation.cwd] = observation
                continue
            }
            if isNewerWinner(observation, than: current) {
                winners[observation.cwd] = observation
            }
        }
        return winners.mapValues(\.state)
    }

    /// Ties on `lastActivity` (two files updated in the same instant) resolve by
    /// `AgentState.displayPriority` so the result never depends on input order.
    private static func isNewerWinner(_ candidate: SessionObservation, than incumbent: SessionObservation) -> Bool {
        if candidate.lastActivity != incumbent.lastActivity {
            return candidate.lastActivity > incumbent.lastActivity
        }
        let candidatePriority = AgentState(hookState: candidate.state).displayPriority
        let incumbentPriority = AgentState(hookState: incumbent.state).displayPriority
        return candidatePriority > incumbentPriority
    }

    /// Diffs `resolve`'s per-cwd result against what was last published: a changed/new state emits,
    /// and a cwd that dropped out of the result (every file bound to it went stale or vanished)
    /// emits `idle` once — unless it was already idle, so a long-abandoned worktree doesn't
    /// re-publish `idle` on every poll. Sorted by cwd so emission order is deterministic, unlike the
    /// per-file `contentsOfDirectory`/`Set` iteration order the watchers scan in.
    public static func emissions(resolved: [String: String], lastEmitted: [String: String]) -> [StateEmission] {
        var result: [StateEmission] = []
        for cwd in Set(resolved.keys).union(lastEmitted.keys).sorted() {
            let newState = resolved[cwd] ?? "idle"
            guard lastEmitted[cwd] != newState else { continue }
            result.append(StateEmission(cwd: cwd, state: newState))
        }
        return result
    }
}
