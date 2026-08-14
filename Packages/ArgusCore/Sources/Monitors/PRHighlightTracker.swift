import Foundation

/// The subset of a PR's fields `PRHighlightTracker` needs to detect an approval-state change.
public protocol ApprovalTrackable: Identifiable where ID == Int {
    var approvedBy: [String] { get }
    var approvedByMe: Bool { get }
}

/// Tracks which PRs' approval state changed since the last check, driving the sidebar's
/// "something changed" highlight. Stateful across calls — one tracker per monitored set of PRs.
public final class PRHighlightTracker {
    public private(set) var highlightedIDs: Set<Int> = []

    private var knownApprovedBy: [Int: [String]] = [:]
    private var hasCompletedInitialFetch = false

    public init() {}

    /// Call once per refresh with the full set of PRs the highlight applies to (e.g. open +
    /// review-requested). Highlights any PR whose `approvedBy` set changed since the last call,
    /// except PRs already approved by the current user (`approvedByMe`), which never highlight.
    /// The very first call establishes a baseline and highlights nothing — there's no prior state
    /// to compare against. PRs no longer present in `trackable` have their snapshot and highlight
    /// both pruned.
    public func update<PR: ApprovalTrackable>(trackable: [PR]) {
        let trackableIDs = Set(trackable.map(\.id))
        if hasCompletedInitialFetch {
            for pullRequest in trackable where !pullRequest.approvedByMe {
                if knownApprovedBy[pullRequest.id] != pullRequest.approvedBy {
                    highlightedIDs.insert(pullRequest.id)
                }
            }
        }
        for pullRequest in trackable {
            knownApprovedBy[pullRequest.id] = pullRequest.approvedBy
        }
        knownApprovedBy = knownApprovedBy.filter { trackableIDs.contains($0.key) }
        highlightedIDs = highlightedIDs.filter { id in
            guard trackableIDs.contains(id) else { return false }
            return !(trackable.first { $0.id == id }?.approvedByMe ?? false)
        }
        hasCompletedInitialFetch = true
    }

    /// Dismisses a PR's highlight (e.g. once the user has seen it), without affecting its
    /// tracked approval snapshot.
    public func dismiss(id: Int) {
        highlightedIDs.remove(id)
    }
}
