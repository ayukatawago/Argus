import Foundation

/// The PRs the user has snoozed from the sidebar's PR monitor. Hiding is a UI preference, not an
/// approval/categorization concern, so it's kept separate from `PRCategorizer`'s buckets and
/// applied on top of them via `split`. A hidden PR remembers its `updated_at` at hide time and
/// reappears once `reconcile` sees that change (new commits, comments, reviews, ...).
public struct PRHiddenList: Equatable, Sendable {
    /// PR id → `updated_at` when hidden; `nil` means no baseline is known yet (a legacy file, or a
    /// PR hidden before `updatedAt` was decoded) and is filled in by the next `reconcile`.
    public private(set) var entries: [Int: String?]

    public var ids: Set<Int> { Set(entries.keys) }

    public init(entries: [Int: String?] = [:]) {
        self.entries = entries
    }

    /// Hides `id`, remembering `updatedAt`. Returns whether it was newly hidden, so callers only
    /// persist/republish on an actual change.
    @discardableResult
    public mutating func hide(_ id: Int, updatedAt: String?) -> Bool {
        guard !entries.keys.contains(id) else { return false }
        entries[id] = .some(updatedAt)
        return true
    }

    /// Reveals every id in `revealed`. Returns whether anything was actually hidden beforehand.
    @discardableResult
    public mutating func reveal(_ revealed: Set<Int>) -> Bool {
        let before = entries.count
        for id in revealed { entries.removeValue(forKey: id) }
        return entries.count != before
    }

    /// Reconciles against a successful fetch's `current` id → `updated_at`. Drops any hidden id no
    /// longer present (merged/closed, or the user was unassigned) so the set can't grow forever,
    /// and any whose `updated_at` changed since it was hidden (the PR got activity, so it should
    /// reappear). A `nil` baseline adopts the current value. Returns whether anything changed.
    @discardableResult
    public mutating func reconcile(current: [Int: String?]) -> Bool {
        let before = entries
        for (id, snapshot) in before {
            guard let currentValue = current[id] else {
                entries.removeValue(forKey: id)
                continue
            }
            switch (snapshot, currentValue) {
            case (.some(let old), .some(let new)) where old != new:
                entries.removeValue(forKey: id)

            case (.none, .some):
                entries[id] = .some(currentValue)

            default:
                break
            }
        }
        return entries != before
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
