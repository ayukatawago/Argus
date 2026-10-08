import Foundation

/// A run of unchanged lines git collapsed out of the diff between (or around) hunks, available
/// to be revealed on demand — GitHub calls these the "..." expanders in its diff view.
public struct DiffGap: Identifiable, Hashable, Sendable {
    public enum Position: Sendable, Hashable {
        case top
        case middle
        case bottom
    }

    public let id: String
    /// First old-file line number the gap covers (1-based).
    public let oldStart: Int
    /// First new-file line number the gap covers (1-based).
    public let newStart: Int
    /// Number of lines in the gap, when known. `nil` only for a `.bottom` gap, whose extent isn't
    /// known without first reading the file to find where it actually ends.
    public let lineCount: Int?
    public let position: Position
}

/// One renderable unit of a file's diff: either a hunk as parsed from git, or a collapsed gap of
/// unchanged lines that can be expanded into view.
public enum DiffBlock: Identifiable, Sendable {
    case hunk(DiffHunk)
    case gap(DiffGap)

    public var id: String {
        switch self {
        case .hunk(let hunk): "hunk-\(hunk.id)"
        case .gap(let gap): "gap-\(gap.id)"
        }
    }
}

/// Builds the ordered top-to-bottom sequence of hunks and collapsed gaps for a file, by comparing
/// each hunk's old/new start+count (parsed from its `@@` header) against its neighbors.
public enum DiffBlockBuilder {
    public static func blocks(for file: DiffFile) -> [DiffBlock] {
        let hunks = file.hunks
        guard !hunks.isEmpty else { return [] }

        var blocks: [DiffBlock] = []
        if let first = hunks.first, let topGap = topGap(before: first) {
            blocks.append(.gap(topGap))
        }
        for (index, hunk) in hunks.enumerated() {
            blocks.append(.hunk(hunk))
            if index + 1 < hunks.count, let gap = middleGap(between: hunk, and: hunks[index + 1]) {
                blocks.append(.gap(gap))
            }
        }
        if let last = hunks.last, let bottomGap = bottomGap(after: last) {
            blocks.append(.gap(bottomGap))
        }
        return blocks
    }

    private static func topGap(before hunk: DiffHunk) -> DiffGap? {
        guard let oldRange = hunk.oldRange, let newRange = hunk.newRange else { return nil }
        let count = min(oldRange.start, newRange.start) - 1
        guard count > 0 else { return nil }
        return DiffGap(id: "top", oldStart: 1, newStart: 1, lineCount: count, position: .top)
    }

    private static func middleGap(between previous: DiffHunk, and next: DiffHunk) -> DiffGap? {
        guard let previousOld = previous.oldRange, let previousNew = previous.newRange, let nextNew = next.newRange
        else {
            return nil
        }
        let oldStart = previousOld.start + previousOld.count
        let newStart = previousNew.start + previousNew.count
        let count = nextNew.start - newStart
        guard count > 0 else { return nil }
        return DiffGap(
            id: "mid-\(oldStart)-\(newStart)",
            oldStart: oldStart,
            newStart: newStart,
            lineCount: count,
            position: .middle
        )
    }

    private static func bottomGap(after hunk: DiffHunk) -> DiffGap? {
        guard let oldRange = hunk.oldRange, let newRange = hunk.newRange else { return nil }
        let oldStart = oldRange.start + oldRange.count
        let newStart = newRange.start + newRange.count
        return DiffGap(id: "bottom", oldStart: oldStart, newStart: newStart, lineCount: nil, position: .bottom)
    }
}
