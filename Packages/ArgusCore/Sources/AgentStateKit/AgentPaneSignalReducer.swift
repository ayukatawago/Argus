import Foundation

/// Pure per-key reducer turning a poll's raw `AgentPaneDisplayParser.PaneSignal` into (at most)
/// one state change for `AgentPaneDisplayWatcher` to publish. Kept separate from the watcher
/// (which owns the actual tmux polling) so this stateful-but-side-effect-free logic is unit
/// testable without a live pane — mirrors why `ClaudeTranscriptParser`/`SessionActivityArbiter`
/// are split out from their watcher.
///
/// Exists to fix a real bug: without the dedup here, the watcher would call
/// `AgentStateBus.apply(_:source:)` on every poll a decisive signal is found, including polls
/// where nothing changed. Claude's on-screen "finished" marker (`✻ Sautéed for 31m 19s`) persists
/// unchanged until the *next* turn starts, so re-asserting `.done` every second would stomp right
/// back over a user's dismissal (`AgentStateBus.dismissAttentionStates`, which publishes `.idle`
/// but has no way to change what the pane itself displays) within one poll interval — the
/// dismissed border would reappear almost immediately. `KeyState.lastEmitted` is this reducer's
/// own memory of what it last concluded, deliberately independent of `AgentStateBus`'s currently
/// published state (which dismissal is meant to be free to diverge from).
public enum AgentPaneSignalReducer {
    /// One key's memory across polls.
    public struct KeyState: Equatable, Sendable {
        /// The state string this reducer last decided to emit, or `nil` before any decisive
        /// signal has been seen.
        public var lastEmitted: String?
        /// Has a running/finished signal been seen since this key started being watched? Needed
        /// only to disambiguate Codex's `.ready` signal, which is shown both before the first turn
        /// and after one finishes (Claude needs no equivalent — see
        /// `AgentPaneDisplayParser.Patterns.claudeDefaults`'s doc comment).
        public var hasRunSinceObserved: Bool
        /// Consecutive polls that have reported something other than `waitingForApproval` while
        /// that is still `lastEmitted` — see `reduce(_:previous:)`'s doc comment.
        public var pendingApprovalDowngrade: Int

        public init(lastEmitted: String? = nil, hasRunSinceObserved: Bool = false, pendingApprovalDowngrade: Int = 0) {
            self.lastEmitted = lastEmitted
            self.hasRunSinceObserved = hasRunSinceObserved
            self.pendingApprovalDowngrade = pendingApprovalDowngrade
        }
    }

    /// Reduces one poll's signal against `previous` state, returning the updated state to carry
    /// into the next poll and, only when a change should actually be published, the new state
    /// string (`AgentStateBus`/`HookPayload`'s vocabulary: "running"/"done"/"idle"/
    /// "waitingForApproval"). A `nil` signal (indeterminate — see `AgentPaneDisplayParser.signal`)
    /// leaves `previous` untouched and publishes nothing, the same "keep whatever's already there"
    /// contract the parser itself follows.
    ///
    /// A pane with an open approval dialog shows no active spinner — indistinguishable, purely
    /// from the display signal, from "the agent simply hasn't resumed yet". Downgrading
    /// `waitingForApproval` straight to whatever the very next poll reports would race the
    /// `PermissionRequest` hook exactly while the dialog might still be closing — the same hazard
    /// `ClaudeTranscriptParser`'s `stop_reason: tool_use` handling exists to avoid. Requiring two
    /// consecutive non-approval polls before downgrading gives that race room to resolve; a poll
    /// that reports `waitingForApproval` again while a downgrade is pending resets the count rather
    /// than accumulating toward it.
    public static func reduce(
        _ signal: AgentPaneDisplayParser.PaneSignal?,
        previous: KeyState
    ) -> (next: KeyState, publish: String?) {
        guard let signal else { return (previous, nil) }

        var next = previous
        let rawState: String
        switch signal {
        case .awaitingApproval:
            rawState = "waitingForApproval"

        case .running:
            next.hasRunSinceObserved = true
            rawState = "running"

        case .finished:
            next.hasRunSinceObserved = true
            rawState = "done"

        case .ready:
            rawState = previous.hasRunSinceObserved ? "done" : "idle"

        case .noAgentUI:
            next.hasRunSinceObserved = false
            rawState = "idle"
        }

        guard previous.lastEmitted == "waitingForApproval", rawState != "waitingForApproval" else {
            next.pendingApprovalDowngrade = 0
            return publishIfChanged(rawState, into: next)
        }

        let pollsWithoutApproval = previous.pendingApprovalDowngrade + 1
        guard pollsWithoutApproval >= 2 else {
            next.pendingApprovalDowngrade = pollsWithoutApproval
            return (next, nil)
        }
        next.pendingApprovalDowngrade = 0
        return publishIfChanged(rawState, into: next)
    }

    private static func publishIfChanged(_ state: String, into keyState: KeyState) -> (KeyState, String?) {
        guard keyState.lastEmitted != state else { return (keyState, nil) }
        var updated = keyState
        updated.lastEmitted = state
        return (updated, state)
    }
}
