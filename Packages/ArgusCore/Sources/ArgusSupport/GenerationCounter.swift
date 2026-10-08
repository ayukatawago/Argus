import Foundation

/// Per-key version numbers for detecting that something happened *while* an `await` was in flight.
///
/// Take a `current(_:)` token before suspending; afterwards, `bump(_:)` having been called in the
/// meantime means the key was touched by someone else and the continuation's assumptions are stale.
/// Used where an async teardown (kill a tmux session, then unmount its view) can be overtaken by a
/// reopen of the same thing before it resumes.
public struct GenerationCounter<Key: Hashable>: Sendable where Key: Sendable {
    private var generations: [Key: Int] = [:]

    public init() {}

    public func current(_ key: Key) -> Int { generations[key] ?? 0 }

    /// Marks `key` as touched.
    public mutating func bump(_ key: Key) { generations[key, default: 0] += 1 }

    /// True when `key` has not been bumped since `token` was taken.
    public func isUnchanged(_ key: Key, since token: Int) -> Bool { current(key) == token }
}
