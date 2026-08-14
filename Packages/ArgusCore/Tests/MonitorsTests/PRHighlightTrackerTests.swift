import Testing

@testable import Monitors

private struct FakeTrackablePR: ApprovalTrackable {
    let id: Int
    var approvedBy: [String] = []
    var approvedByMe: Bool = false
}

@Suite("PRHighlightTracker")
struct PRHighlightTrackerTests {
    @Test("the first call establishes a baseline and highlights nothing")
    func firstCallHighlightsNothing() {
        let tracker = PRHighlightTracker()
        tracker.update(trackable: [FakeTrackablePR(id: 1, approvedBy: ["alice"])])
        #expect(tracker.highlightedIDs.isEmpty)
    }

    @Test("an approval set change after the baseline highlights the PR")
    func approvalChangeHighlights() {
        let tracker = PRHighlightTracker()
        tracker.update(trackable: [FakeTrackablePR(id: 1, approvedBy: [])])
        tracker.update(trackable: [FakeTrackablePR(id: 1, approvedBy: ["alice"])])
        #expect(tracker.highlightedIDs.contains(1))
    }

    @Test("no change between calls does not highlight")
    func noChangeDoesNotHighlight() {
        let tracker = PRHighlightTracker()
        tracker.update(trackable: [FakeTrackablePR(id: 1, approvedBy: ["alice"])])
        tracker.update(trackable: [FakeTrackablePR(id: 1, approvedBy: ["alice"])])
        #expect(!tracker.highlightedIDs.contains(1))
    }

    @Test("a PR already approved by the current user never highlights, even when approvedBy changes")
    func approvedByMeNeverHighlights() {
        let tracker = PRHighlightTracker()
        tracker.update(trackable: [FakeTrackablePR(id: 1, approvedBy: [], approvedByMe: true)])
        tracker.update(trackable: [FakeTrackablePR(id: 1, approvedBy: ["me"], approvedByMe: true)])
        #expect(!tracker.highlightedIDs.contains(1))
    }

    @Test("a highlighted PR that becomes approvedByMe on a later call loses its highlight")
    func becomingApprovedByMeClearsHighlight() {
        let tracker = PRHighlightTracker()
        tracker.update(trackable: [FakeTrackablePR(id: 1, approvedBy: [])])
        tracker.update(trackable: [FakeTrackablePR(id: 1, approvedBy: ["alice"])])
        #expect(tracker.highlightedIDs.contains(1))

        tracker.update(trackable: [FakeTrackablePR(id: 1, approvedBy: ["alice", "me"], approvedByMe: true)])
        #expect(!tracker.highlightedIDs.contains(1))
    }

    @Test("both the snapshot and the highlight are pruned when a PR leaves the tracked list")
    func leavingListPrunesSnapshotAndHighlight() {
        let tracker = PRHighlightTracker()
        tracker.update(trackable: [FakeTrackablePR(id: 1, approvedBy: [])])
        tracker.update(trackable: [FakeTrackablePR(id: 1, approvedBy: ["alice"])])
        #expect(tracker.highlightedIDs.contains(1))

        // PR 1 drops out of the tracked set entirely (e.g. merged, closed, or reassigned).
        tracker.update(trackable: [] as [FakeTrackablePR])
        #expect(!tracker.highlightedIDs.contains(1))

        // If PR 1 reappears with the SAME approvedBy as before it left, it highlights again,
        // proving the snapshot (not just the highlight) was pruned rather than retained.
        tracker.update(trackable: [FakeTrackablePR(id: 1, approvedBy: ["alice"])])
        #expect(tracker.highlightedIDs.contains(1))
    }

    @Test("dismiss clears a highlight without affecting the tracked approval snapshot")
    func dismissClearsHighlightOnly() {
        let tracker = PRHighlightTracker()
        tracker.update(trackable: [FakeTrackablePR(id: 1, approvedBy: [])])
        tracker.update(trackable: [FakeTrackablePR(id: 1, approvedBy: ["alice"])])
        #expect(tracker.highlightedIDs.contains(1))

        tracker.dismiss(id: 1)
        #expect(!tracker.highlightedIDs.contains(1))

        // No further approval change — should stay dismissed since the snapshot didn't change.
        tracker.update(trackable: [FakeTrackablePR(id: 1, approvedBy: ["alice"])])
        #expect(!tracker.highlightedIDs.contains(1))
    }
}
