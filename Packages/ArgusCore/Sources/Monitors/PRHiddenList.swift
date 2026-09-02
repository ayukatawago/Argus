import Foundation

/// The set of PR ids the user has dismissed from the sidebar's PR monitor. Hiding is a UI
/// preference, not an approval/categorization concern, so it's kept separate from
/// `PRCategorizer`'s buckets and applied on top of them via `split`.
public struct PRHiddenList: Equatable, Sendable {
    public private(set) var ids: Set<Int>

    public init(ids: Set<Int> = []) {
        self.ids = ids
    }

    /// Hides `id`. Returns whether it was newly hidden, so callers only persist/republish on an
    /// actual change.
    @discardableResult
    public mutating func hide(_ id: Int) -> Bool {
        ids.insert(id).inserted
    }

    /// Reveals every id in `revealed`. Returns whether anything was actually hidden beforehand.
    @discardableResult
    public mutating func reveal(_ revealed: Set<Int>) -> Bool {
        let before = ids
        ids.subtract(revealed)
        return ids != before
    }

    /// Drops any hidden id no longer present in a successful fetch (merged/closed, or the user
    /// was unassigned) so the hidden set can't grow forever. Returns whether anything was pruned.
    @discardableResult
    public mutating func prune(keeping presentIDs: Set<Int>) -> Bool {
        let before = ids
        ids.formIntersection(presentIDs)
        return ids != before
    }

    /// Order-preserving partition of `prs` into those not in `ids` and those in `ids`.
    public func split<PR: Identifiable>(_ prs: [PR]) -> (visible: [PR], hidden: [PR]) where PR.ID == Int {
        var visible: [PR] = []
        var hidden: [PR] = []
        for pullRequest in prs {
            if ids.contains(pullRequest.id) {
                hidden.append(pullRequest)
            } else {
                visible.append(pullRequest)
            }
        }
        return (visible, hidden)
    }
}
