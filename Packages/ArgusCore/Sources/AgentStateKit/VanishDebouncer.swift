import Foundation

/// Decides when a key that was covered on the previous poll is genuinely gone.
///
/// A single poll that fails to list a session is indistinguishable from a transient `tmux
/// list-panes` hiccup. Concluding "gone" on one miss would wipe the key's reducer memory and
/// publish idle; if the session reappears next poll with its on-screen "finished" marker unchanged,
/// that wiped memory reads it as a brand-new signal and republishes done — a spontaneous done with
/// nothing having happened. So a key must miss `threshold` consecutive polls first, and while it
/// is inside that grace period it is reported as `stillMissing` so the caller keeps covering it.
public struct VanishDebouncer<Key: Hashable & Sendable>: Sendable {
    public struct Outcome: Equatable, Sendable {
        /// Missed this poll but still within the grace period: keep treating as covered.
        public let stillMissing: Set<Key>
        /// Has now missed `threshold` polls in a row: treat as gone.
        public let vanished: Set<Key>
    }

    public let threshold: Int
    private var covered: Set<Key> = []
    private var streaks: [Key: Int] = [:]

    public init(threshold: Int) {
        self.threshold = max(1, threshold)
    }

    /// Feeds one poll's found keys. Afterwards the covered set is `found ∪ stillMissing`.
    public mutating func update(found: Set<Key>) -> Outcome {
        for key in found { streaks.removeValue(forKey: key) }
        var stillMissing: Set<Key> = []
        var vanished: Set<Key> = []
        for key in covered.subtracting(found) {
            let streak = (streaks[key] ?? 0) + 1
            if streak >= threshold {
                streaks.removeValue(forKey: key)
                vanished.insert(key)
            } else {
                streaks[key] = streak
                stillMissing.insert(key)
            }
        }
        covered = found.union(stillMissing)
        return Outcome(stillMissing: stillMissing, vanished: vanished)
    }

    /// Forgets everything, returning the keys that were covered (the caller idles them).
    public mutating func reset() -> Set<Key> {
        defer {
            covered = []
            streaks = [:]
        }
        return covered
    }
}
