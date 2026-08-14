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
}
