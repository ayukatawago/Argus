import Foundation

/// Wrap-around cycling through the sidebar's worktree list (leader `n`/`p`).
public enum WorktreeNavigator {
    /// Computes the next worktree ID to select when cycling through `eligible` (already filtered
    /// to visible + active worktrees, in sidebar order) in `forward`/backward order from
    /// `current`. Wraps around at either end. Returns `nil` when `eligible` is empty. When
    /// `current` is `nil` or no longer present in `eligible` (e.g. it was just hidden or
    /// released), selects the first eligible worktree instead of cycling from nowhere.
    public static func next(from current: String?, in eligible: [String], forward: Bool) -> String? {
        guard !eligible.isEmpty else { return nil }
        guard let current, let idx = eligible.firstIndex(of: current) else {
            return eligible.first
        }
        let nextIndex = forward ? (idx + 1) % eligible.count : (idx - 1 + eligible.count) % eligible.count
        return eligible[nextIndex]
    }

    /// The next worktree needing attention after `current`, wrapping around and never returning
    /// `current` itself. `priority` rates an ID (nil = doesn't need attention); among candidates
    /// the highest priority wins, with ties broken by position after `current`.
    public static func nextAttention(
        from current: String?, in ordered: [String], priority: (String) -> Int?
    ) -> String? {
        let start = current.flatMap { ordered.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        let rotated = (0..<ordered.count).map { ordered[(start + $0) % ordered.count] }.filter { $0 != current }
        var best: (id: String, priority: Int)?
        for id in rotated {
            guard let value = priority(id) else { continue }
            if let current = best, current.priority >= value { continue }
            best = (id, value)
        }
        return best?.id
    }
}
