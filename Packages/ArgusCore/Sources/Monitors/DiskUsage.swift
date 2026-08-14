import Foundation

/// Free-space math for the disk-space monitor.
public struct DiskUsage: Sendable, Equatable {
    public let total: Int64
    public let free: Int64

    public init(total: Int64, free: Int64) {
        self.total = total
        self.free = free
    }

    /// Percentage of `total` that's `free`. Defaults to `100` (i.e. "plenty of room") when
    /// `total` is zero or negative, avoiding a division by zero rather than reporting NaN/low.
    public var percentFree: Double {
        guard total > 0 else { return 100 }
        return Double(free) / Double(total) * 100
    }

    /// Whether `percentFree` has dropped below `threshold`. Strictly less-than: a disk exactly at
    /// the threshold is not yet "low".
    public func isLow(threshold: Double) -> Bool {
        percentFree < threshold
    }
}
