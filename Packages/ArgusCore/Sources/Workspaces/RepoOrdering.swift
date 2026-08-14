import Foundation

/// Pure logic for the sidebar's persisted repo drag-reorder.
public enum RepoOrdering {
    /// Reorders `discovered` to match `order` (a list of `mainPath`s), appending any repos not
    /// present in `order` at the end, in their discovered position. Returns `discovered`
    /// unchanged when `order` is empty (the default, before the user has ever reordered).
    public static func apply(order: [String], to discovered: [GitRepo]) -> [GitRepo] {
        guard !order.isEmpty else { return discovered }
        let byPath = discovered.reduce(into: [String: GitRepo]()) { $0[$1.mainPath] = $1 }
        let ordered = order.compactMap { byPath[$0] }
        let known = Set(order)
        let appended = discovered.filter { !known.contains($0.mainPath) }
        return ordered + appended
    }

    /// Computes the new `mainPath` order after dragging the repo at `fromIndex` to `toIndex`
    /// within `repos`. Returns `nil` for a no-op move (same index, or either index out of bounds)
    /// — callers should leave their persisted order untouched in that case.
    public static func move(fromIndex: Int, toIndex: Int, in repos: [GitRepo]) -> [String]? {
        guard fromIndex != toIndex, repos.indices.contains(fromIndex), repos.indices.contains(toIndex) else {
            return nil
        }
        var order = repos.map(\.mainPath)
        let item = order.remove(at: fromIndex)
        let insertAt = fromIndex < toIndex ? toIndex - 1 : toIndex
        order.insert(item, at: insertAt)
        return order
    }
}
