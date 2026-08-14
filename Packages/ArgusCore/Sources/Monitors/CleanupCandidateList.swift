import Foundation

/// The subset of a disk-cleanup candidate's fields `CleanupCandidateList` needs to filter and
/// sort — independent of the App target's `CleanupCandidate` (which also carries selection state,
/// a path, and a last-modified date used only for display).
public protocol SizedCandidate {
    var displayName: String { get }
    var sizeBytes: Int64? { get }
}

/// Filter/sort rules for the disk cleanup popup's candidate list.
public enum CleanupCandidateList {
    public static let smallSizeThresholdBytes: Int64 = 1_073_741_824  // 1 GiB

    /// Filters out candidates below `smallSizeThresholdBytes` when `hideSmall` is set, then sorts
    /// by `comparator`. A candidate whose size isn't known yet (still being scanned, `nil`) is
    /// never hidden by the small-size filter, regardless of `hideSmall`.
    public static func visible<T: SizedCandidate>(
        _ candidates: [T],
        hideSmall: Bool,
        sortedBy comparator: (T, T) -> Bool
    ) -> [T] {
        var list = candidates
        if hideSmall {
            list = list.filter { candidate in
                guard let size = candidate.sizeBytes else { return true }
                return size >= smallSizeThresholdBytes
            }
        }
        return list.sorted(by: comparator)
    }

    public static func byName<T: SizedCandidate>(_ lhs: T, _ rhs: T) -> Bool {
        lhs.displayName < rhs.displayName
    }

    /// Largest first. A candidate with an unknown size (`nil`) sorts last.
    public static func bySizeDescending<T: SizedCandidate>(_ lhs: T, _ rhs: T) -> Bool {
        (lhs.sizeBytes ?? -1) > (rhs.sizeBytes ?? -1)
    }
}
