import Foundation
import Testing

@testable import AgentStateKit

/// Covers `ClaudeTranscriptWatcher.applySidechainLiveness(to:sidechainActivityByCwd:)` — pure and
/// filesystem-free (`transcriptFiles()`/`subagentFiles()` hardcode `~/.claude/projects`, so unlike
/// the parser/arbiter this watcher isn't otherwise unit-testable), covering the fix for the false
/// idle a `Task` subagent run causes: the parent transcript is silent for the subagent's whole
/// run, so without this bump a subagent lasting past `activityWindow` (15 minutes) ages the
/// parent's "running" observation out and the row goes idle while genuinely still working.
@Suite("ClaudeTranscriptWatcher.applySidechainLiveness")
struct ClaudeTranscriptWatcherSidechainTests {
    private static let cwd = "/Users/taku/workspace/app/Argus"
    private static let baseTime = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("a running observation is bumped to newer sidechain activity for the same cwd")
    func runningObservationIsBumpedToNewerSidechainActivity() {
        let observation = SessionActivityArbiter.SessionObservation(
            cwd: Self.cwd, state: "running", lastActivity: Self.baseTime)
        let bumped = ClaudeTranscriptWatcher.applySidechainLiveness(
            to: observation,
            sidechainActivityByCwd: [Self.cwd: Self.baseTime.addingTimeInterval(600)]
        )
        #expect(bumped.lastActivity == Self.baseTime.addingTimeInterval(600))
        #expect(bumped.state == "running")
        #expect(bumped.cwd == Self.cwd)
    }

    @Test("a running observation already newer than the sidechain activity is left unchanged")
    func runningObservationNewerThanSidechainIsUnchanged() {
        let observation = SessionActivityArbiter.SessionObservation(
            cwd: Self.cwd, state: "running", lastActivity: Self.baseTime)
        let bumped = ClaudeTranscriptWatcher.applySidechainLiveness(
            to: observation,
            sidechainActivityByCwd: [Self.cwd: Self.baseTime.addingTimeInterval(-600)]
        )
        #expect(bumped.lastActivity == Self.baseTime)
    }

    @Test(
        """
        a "done" observation is never bumped by sidechain activity — a subagent still finishing \
        must not keep an already-finished parent turn artificially fresh and resurrect its border
        """
    )
    func doneObservationIsNeverBumped() {
        let observation = SessionActivityArbiter.SessionObservation(
            cwd: Self.cwd, state: "done", lastActivity: Self.baseTime)
        let bumped = ClaudeTranscriptWatcher.applySidechainLiveness(
            to: observation,
            sidechainActivityByCwd: [Self.cwd: Self.baseTime.addingTimeInterval(600)]
        )
        #expect(bumped.lastActivity == Self.baseTime)
        #expect(bumped == observation)
    }

    @Test("an idle observation is never bumped by sidechain activity")
    func idleObservationIsNeverBumped() {
        let observation = SessionActivityArbiter.SessionObservation(
            cwd: Self.cwd, state: "idle", lastActivity: Self.baseTime)
        let bumped = ClaudeTranscriptWatcher.applySidechainLiveness(
            to: observation,
            sidechainActivityByCwd: [Self.cwd: Self.baseTime.addingTimeInterval(600)]
        )
        #expect(bumped == observation)
    }

    @Test("no sidechain activity recorded for this cwd leaves the observation unchanged")
    func noSidechainActivityForCwdLeavesObservationUnchanged() {
        let observation = SessionActivityArbiter.SessionObservation(
            cwd: Self.cwd, state: "running", lastActivity: Self.baseTime)
        let bumped = ClaudeTranscriptWatcher.applySidechainLiveness(
            to: observation,
            sidechainActivityByCwd: ["/some/other/worktree": Self.baseTime.addingTimeInterval(600)]
        )
        #expect(bumped == observation)
    }

    @Test(
        """
        the motivating scenario: a running parent observation whose own last activity is stale \
        (beyond what a 15-minute activityWindow alone would tolerate) is kept fresh by a \
        still-running subagent's newer activity for the same cwd
        """
    )
    func staleRunningParentIsKeptFreshByLiveSubagent() {
        let parentLastActivity = Self.baseTime
        // `now` is 16 minutes past the parent's own last write — past a 15-minute activityWindow
        // on its own — while the subagent, still actively running, wrote 1 minute ago.
        let now = parentLastActivity.addingTimeInterval(16 * 60)
        let subagentLastActivity = now.addingTimeInterval(-60)
        let observation = SessionActivityArbiter.SessionObservation(
            cwd: Self.cwd, state: "running", lastActivity: parentLastActivity)

        let bumped = ClaudeTranscriptWatcher.applySidechainLiveness(
            to: observation,
            sidechainActivityByCwd: [Self.cwd: subagentLastActivity]
        )

        let resolvedWithoutBump = SessionActivityArbiter.resolve([observation], now: now, window: 900)
        let resolvedWithBump = SessionActivityArbiter.resolve([bumped], now: now, window: 900)

        #expect(resolvedWithoutBump[Self.cwd] == nil)
        #expect(resolvedWithBump[Self.cwd] == "running")
    }
}
