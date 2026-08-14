import Foundation

/// The subset of a GitHub PR's fields `PRCategorizer` needs. A protocol rather than a concrete
/// type so the App target's own `GitHubPR` (tied to the REST API's JSON shape) can conform
/// directly instead of being converted back and forth.
public protocol CategorizablePullRequest: Identifiable where ID == Int {
    var draft: Bool { get }
    var labelNames: [String] { get }
    var approvedBy: [String] { get }
    var approvedByMe: Bool { get set }
}

/// Splits a user's authored/assigned PRs into the sidebar's four buckets.
public enum PRCategorizer {
    public struct Categorized<PR: CategorizablePullRequest> {
        public let myOpenPRs: [PR]
        public let myDraftPRs: [PR]
        public let reviewRequestedPRs: [PR]
        public let doNotMergePRs: [PR]

        public init(myOpenPRs: [PR], myDraftPRs: [PR], reviewRequestedPRs: [PR], doNotMergePRs: [PR]) {
            self.myOpenPRs = myOpenPRs
            self.myDraftPRs = myDraftPRs
            self.reviewRequestedPRs = reviewRequestedPRs
            self.doNotMergePRs = doNotMergePRs
        }
    }

    private static let doNotMergeLabel = "!!! DONT' MERGE !!!"

    /// `authored`/`assigned` should already carry enrichment data (`approvedBy`, labels) —
    /// `approvedByMe` is derived here, from `username`, before bucketing:
    /// - `myOpenPRs` / `myDraftPRs`: authored, split by draft status
    /// - `reviewRequestedPRs`: assigned but not authored by `username`
    /// - `doNotMergePRs`: any PR (authored ∪ assigned, deduplicated by id) carrying the
    ///   "!!! DONT' MERGE !!!" label
    ///
    /// All buckets except `doNotMergePRs` itself exclude PRs carrying that label.
    public static func categorize<PR: CategorizablePullRequest>(
        authored rawAuthored: [PR],
        assigned rawAssigned: [PR],
        username: String
    ) -> Categorized<PR> {
        func withApprovedByMe(_ prs: [PR]) -> [PR] {
            prs.map { pullRequest in
                var copy = pullRequest
                copy.approvedByMe = pullRequest.approvedBy.contains(username)
                return copy
            }
        }
        let authored = withApprovedByMe(rawAuthored)
        let assigned = withApprovedByMe(rawAssigned)
        let notDNM = { (pullRequest: PR) in !pullRequest.labelNames.contains(doNotMergeLabel) }

        let myOpenPRs = authored.filter { !$0.draft && notDNM($0) }
        let myDraftPRs = authored.filter { $0.draft && notDNM($0) }
        let authoredIDs = Set(authored.map(\.id))
        let reviewRequestedPRs = assigned.filter { !authoredIDs.contains($0.id) && notDNM($0) }

        var seen = Set<Int>()
        let allPRs = (authored + assigned).filter { seen.insert($0.id).inserted }
        var dnmSeen = Set<Int>()
        let doNotMergePRs = allPRs.filter { $0.labelNames.contains(doNotMergeLabel) && dnmSeen.insert($0.id).inserted }

        return Categorized(
            myOpenPRs: myOpenPRs,
            myDraftPRs: myDraftPRs,
            reviewRequestedPRs: reviewRequestedPRs,
            doNotMergePRs: doNotMergePRs
        )
    }
}
