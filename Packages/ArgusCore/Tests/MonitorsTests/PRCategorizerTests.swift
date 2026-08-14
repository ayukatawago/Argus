import Testing

@testable import Monitors

private struct FakePR: CategorizablePullRequest, Equatable {
    let id: Int
    var draft: Bool = false
    var labelNames: [String] = []
    var approvedBy: [String] = []
    var approvedByMe: Bool = false
}

@Suite("PRCategorizer")
struct PRCategorizerTests {
    @Test("an open (non-draft) authored PR lands in myOpenPRs")
    func openAuthoredPR() {
        let pullRequest = FakePR(id: 1, draft: false)
        let result = PRCategorizer.categorize(authored: [pullRequest], assigned: [], username: "me")
        #expect(result.myOpenPRs.map(\.id) == [1])
        #expect(result.myDraftPRs.isEmpty)
    }

    @Test("a draft authored PR lands in myDraftPRs, not myOpenPRs")
    func draftAuthoredPR() {
        let pullRequest = FakePR(id: 1, draft: true)
        let result = PRCategorizer.categorize(authored: [pullRequest], assigned: [], username: "me")
        #expect(result.myDraftPRs.map(\.id) == [1])
        #expect(result.myOpenPRs.isEmpty)
    }

    @Test("an assigned PR not authored by the user lands in reviewRequestedPRs")
    func assignedNotAuthoredPR() {
        let pullRequest = FakePR(id: 2)
        let result = PRCategorizer.categorize(authored: [], assigned: [pullRequest], username: "me")
        #expect(result.reviewRequestedPRs.map(\.id) == [2])
    }

    @Test("a PR both authored and assigned appears only in the authored bucket, not reviewRequestedPRs")
    func authoredAndAssignedAppearsOnce() {
        let pullRequest = FakePR(id: 3)
        let result = PRCategorizer.categorize(authored: [pullRequest], assigned: [pullRequest], username: "me")
        #expect(result.myOpenPRs.map(\.id) == [3])
        #expect(result.reviewRequestedPRs.isEmpty)
    }

    @Test("a PR carrying the do-not-merge label is routed to doNotMergePRs, excluded elsewhere")
    func doNotMergeLabelRouting() {
        let authoredDNM = FakePR(id: 4, labelNames: ["!!! DONT' MERGE !!!"])
        let assignedDNM = FakePR(id: 5, labelNames: ["!!! DONT' MERGE !!!"])
        let result = PRCategorizer.categorize(authored: [authoredDNM], assigned: [assignedDNM], username: "me")
        #expect(result.myOpenPRs.isEmpty)
        #expect(result.reviewRequestedPRs.isEmpty)
        #expect(Set(result.doNotMergePRs.map(\.id)) == [4, 5])
    }

    @Test("a do-not-merge PR that is both authored and assigned appears once in doNotMergePRs")
    func doNotMergeDedupedAcrossAuthoredAndAssigned() {
        let pullRequest = FakePR(id: 6, labelNames: ["!!! DONT' MERGE !!!"])
        let result = PRCategorizer.categorize(authored: [pullRequest], assigned: [pullRequest], username: "me")
        #expect(result.doNotMergePRs.map(\.id) == [6])
    }

    @Test("approvedByMe is derived from approvedBy containing the given username")
    func approvedByMeDerivation() {
        let approvedPR = FakePR(id: 7, approvedBy: ["me", "someone-else"])
        let notApprovedPR = FakePR(id: 8, approvedBy: ["someone-else"])
        let result = PRCategorizer.categorize(authored: [approvedPR, notApprovedPR], assigned: [], username: "me")
        let approved = result.myOpenPRs.first { $0.id == 7 }
        let notApproved = result.myOpenPRs.first { $0.id == 8 }
        #expect(approved?.approvedByMe == true)
        #expect(notApproved?.approvedByMe == false)
    }

    @Test("empty authored and assigned lists produce empty buckets")
    func emptyInputs() {
        let result = PRCategorizer.categorize(authored: [FakePR](), assigned: [FakePR](), username: "me")
        #expect(result.myOpenPRs.isEmpty)
        #expect(result.myDraftPRs.isEmpty)
        #expect(result.reviewRequestedPRs.isEmpty)
        #expect(result.doNotMergePRs.isEmpty)
    }
}
