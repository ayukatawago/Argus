import Testing

@testable import Monitors

@Suite("PRApprovalDigest")
struct PRApprovalDigestTests {
    @Test("a single APPROVED review is counted")
    func singleApproval() {
        let reviews = [ReviewSubmission(login: "alice", state: "APPROVED", submittedAt: "2026-01-01T00:00:00Z")]
        #expect(PRApprovalDigest.approvedLogins(from: reviews) == ["alice"])
    }

    @Test("a non-approving state is not counted")
    func nonApprovingStateNotCounted() {
        let reviews = [ReviewSubmission(login: "alice", state: "COMMENTED", submittedAt: "2026-01-01T00:00:00Z")]
        #expect(PRApprovalDigest.approvedLogins(from: reviews).isEmpty)
    }

    @Test("multiple approvers are returned sorted by login")
    func multipleApproversSorted() {
        let reviews = [
            ReviewSubmission(login: "zed", state: "APPROVED", submittedAt: "2026-01-01T00:00:00Z"),
            ReviewSubmission(login: "alice", state: "APPROVED", submittedAt: "2026-01-01T00:00:00Z"),
        ]
        #expect(PRApprovalDigest.approvedLogins(from: reviews) == ["alice", "zed"])
    }

    @Test("only the latest review per login counts, by submittedAt")
    func onlyLatestReviewCounts() {
        let reviews = [
            ReviewSubmission(login: "alice", state: "CHANGES_REQUESTED", submittedAt: "2026-01-01T00:00:00Z"),
            ReviewSubmission(login: "alice", state: "APPROVED", submittedAt: "2026-01-02T00:00:00Z"),
        ]
        #expect(PRApprovalDigest.approvedLogins(from: reviews) == ["alice"])
    }

    @Test("an approval later superseded by a non-approving review drops the reviewer entirely")
    func laterNonApprovalSupersedesEarlierApproval() {
        // Locks current behavior: the digest only remembers the latest state per login, so an
        // approve-then-comment sequence erases the approval rather than treating it as "stale".
        let reviews = [
            ReviewSubmission(login: "alice", state: "APPROVED", submittedAt: "2026-01-01T00:00:00Z"),
            ReviewSubmission(login: "alice", state: "COMMENTED", submittedAt: "2026-01-02T00:00:00Z"),
        ]
        #expect(PRApprovalDigest.approvedLogins(from: reviews).isEmpty)
    }

    @Test("an empty review list produces no approvers")
    func emptyReviewList() {
        #expect(PRApprovalDigest.approvedLogins(from: []).isEmpty)
    }

    @Test("out-of-order submission timestamps still resolve to the chronologically latest review")
    func outOfOrderSubmissions() {
        let reviews = [
            ReviewSubmission(login: "alice", state: "APPROVED", submittedAt: "2026-01-02T00:00:00Z"),
            ReviewSubmission(login: "alice", state: "CHANGES_REQUESTED", submittedAt: "2026-01-01T00:00:00Z"),
        ]
        #expect(PRApprovalDigest.approvedLogins(from: reviews) == ["alice"])
    }
}
