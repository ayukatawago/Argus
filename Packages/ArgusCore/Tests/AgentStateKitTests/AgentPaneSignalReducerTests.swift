import Testing

@testable import AgentStateKit

@Suite("AgentPaneSignalReducer")
struct AgentPaneSignalReducerTests {
    private typealias KeyState = AgentPaneSignalReducer.KeyState

    // MARK: - Basic transitions

    @Test("a running signal from a fresh key publishes running")
    func runningSignalFromFreshKeyPublishesRunning() {
        let (next, publish) = AgentPaneSignalReducer.reduce(.running, previous: KeyState())
        #expect(publish == "running")
        #expect(next.lastEmitted == "running")
        #expect(next.hasRunSinceObserved)
    }

    @Test("a finished signal publishes done")
    func finishedSignalPublishesDone() {
        let (next, publish) = AgentPaneSignalReducer.reduce(.finished, previous: KeyState(lastEmitted: "running"))
        #expect(publish == "done")
        #expect(next.lastEmitted == "done")
    }

    @Test("an indeterminate (nil) signal leaves the key state untouched and publishes nothing")
    func indeterminateSignalIsANoOp() {
        let previous = KeyState(lastEmitted: "running", hasRunSinceObserved: true, pendingApprovalDowngrade: 1)
        let (next, publish) = AgentPaneSignalReducer.reduce(nil, previous: previous)
        #expect(publish == nil)
        #expect(next == previous)
    }

    // MARK: - The reported bug: re-observing an unchanged "finished" marker after dismissal

    @Test(
        """
        the regression this reducer exists to fix: re-observing the same "finished" marker on \
        consecutive polls (Claude's on-screen marker persists unchanged until the next turn \
        starts) publishes only once — a caller that applies "done" once, the user dismisses to \
        idle elsewhere, then keeps re-observing the same marker must never re-publish "done" and \
        stomp the dismissal
        """
    )
    func repeatedFinishedSignalPublishesOnlyOnce() {
        let first = AgentPaneSignalReducer.reduce(.finished, previous: KeyState(lastEmitted: "running"))
        #expect(first.publish == "done")

        // Same marker, still on screen, next poll: must NOT publish again.
        let second = AgentPaneSignalReducer.reduce(.finished, previous: first.next)
        #expect(second.publish == nil)
        #expect(second.next.lastEmitted == "done")

        // And again, many polls later — still nothing.
        let third = AgentPaneSignalReducer.reduce(.finished, previous: second.next)
        #expect(third.publish == nil)
    }

    @Test("a repeated running signal likewise publishes only on the first poll")
    func repeatedRunningSignalPublishesOnlyOnce() {
        let first = AgentPaneSignalReducer.reduce(.running, previous: KeyState())
        #expect(first.publish == "running")
        let second = AgentPaneSignalReducer.reduce(.running, previous: first.next)
        #expect(second.publish == nil)
    }

    @Test("a real transition after a held (unpublished) repeat still publishes correctly")
    func realTransitionAfterHeldRepeatStillPublishes() {
        let afterFinish = AgentPaneSignalReducer.reduce(.finished, previous: KeyState(lastEmitted: "running")).next
        let stillFinished = AgentPaneSignalReducer.reduce(.finished, previous: afterFinish).next
        // A new turn starts — a genuine change from "done" must publish immediately.
        let (next, publish) = AgentPaneSignalReducer.reduce(.running, previous: stillFinished)
        #expect(publish == "running")
        #expect(next.lastEmitted == "running")
    }

    // MARK: - Codex's ambiguous .ready signal

    @Test("a .ready signal before any run is observed publishes idle, not done")
    func readySignalBeforeAnyRunPublishesIdle() {
        let (_, publish) = AgentPaneSignalReducer.reduce(.ready, previous: KeyState())
        #expect(publish == "idle")
    }

    @Test("a .ready signal after a run has been observed publishes done")
    func readySignalAfterARunPublishesDone() {
        let afterRunning = AgentPaneSignalReducer.reduce(.running, previous: KeyState()).next
        let (_, publish) = AgentPaneSignalReducer.reduce(.ready, previous: afterRunning)
        #expect(publish == "done")
    }

    @Test("a .noAgentUI signal clears hasRunSinceObserved and publishes idle")
    func noAgentUIClearsLatchAndPublishesIdle() {
        let afterRunning = KeyState(lastEmitted: "running", hasRunSinceObserved: true)
        let (next, publish) = AgentPaneSignalReducer.reduce(.noAgentUI, previous: afterRunning)
        #expect(publish == "idle")
        #expect(!next.hasRunSinceObserved)
    }

    // MARK: - Approval debounce

    @Test("downgrading away from waitingForApproval requires two consecutive non-approval polls")
    func downgradeFromApprovalRequiresTwoConsecutivePolls() {
        let waiting = KeyState(lastEmitted: "waitingForApproval")

        let first = AgentPaneSignalReducer.reduce(.running, previous: waiting)
        #expect(first.publish == nil)
        #expect(first.next.lastEmitted == "waitingForApproval")
        #expect(first.next.pendingApprovalDowngrade == 1)

        let second = AgentPaneSignalReducer.reduce(.running, previous: first.next)
        #expect(second.publish == "running")
        #expect(second.next.lastEmitted == "running")
        #expect(second.next.pendingApprovalDowngrade == 0)
    }

    @Test("re-reporting waitingForApproval mid-debounce resets the counter rather than accumulating")
    func reReportingApprovalMidDebounceResetsCounter() {
        let waiting = KeyState(lastEmitted: "waitingForApproval")
        let held = AgentPaneSignalReducer.reduce(.running, previous: waiting).next
        #expect(held.pendingApprovalDowngrade == 1)

        // The dialog is still up on the next poll.
        let reconfirmed = AgentPaneSignalReducer.reduce(.awaitingApproval, previous: held)
        #expect(reconfirmed.publish == nil)
        #expect(reconfirmed.next.pendingApprovalDowngrade == 0)

        // A single subsequent non-approval poll must not be enough on its own now.
        let firstAfterReset = AgentPaneSignalReducer.reduce(.running, previous: reconfirmed.next)
        #expect(firstAfterReset.publish == nil)
        #expect(firstAfterReset.next.pendingApprovalDowngrade == 1)
    }

    @Test("an awaitingApproval signal from a fresh key publishes waitingForApproval immediately")
    func awaitingApprovalFromFreshKeyPublishesImmediately() {
        let (_, publish) = AgentPaneSignalReducer.reduce(.awaitingApproval, previous: KeyState())
        #expect(publish == "waitingForApproval")
    }

    @Test("a signal other than waitingForApproval while lastEmitted is nil (not waitingForApproval) is not debounced")
    func nonApprovalTransitionOutsideWaitingStateIsNotDebounced() {
        // previous.lastEmitted == "running" (not waitingForApproval) — the debounce path must not
        // trigger at all; a finished signal should publish on the very first poll.
        let (_, publish) = AgentPaneSignalReducer.reduce(.finished, previous: KeyState(lastEmitted: "running"))
        #expect(publish == "done")
    }
}
