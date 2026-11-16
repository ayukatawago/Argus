import Foundation

/// One file's rendered rows plus the lookups its row views need. Built once per file and layout
/// revision by `DiffReviewModel.layout(for:)`, so no row is rebuilt per cell or per body pass.
/// Pure, so the lookups can be tested without a view.
struct DiffFileLayout {
    /// The changed character spans of a modified row (a deletion paired with an addition).
    struct IntralineSpans {
        let old: [Range<String.Index>]
        let new: [Range<String.Index>]
    }

    let items: [DiffRowItem]
    /// Keyed by row id; present only for rows that pair a deletion with an addition.
    let intraline: [String: IntralineSpans]
    /// Line number to text, per side, across every line row (revealed context included).
    let lineTexts: [ReviewComment.Side: [Int: String]]
    /// The gap each expander row stands for, keyed by expander id.
    let gapsByExpanderID: [String: DiffGap]

    static func make(file: DiffFile, gaps: [String: RevealedGap]) -> DiffFileLayout {
        let items = DiffRowItemBuilder.items(for: file, gaps: gaps)
        var intraline: [String: IntralineSpans] = [:]
        var oldTexts: [Int: String] = [:]
        var newTexts: [Int: String] = [:]

        for case .line(let row) in items {
            if let left = row.left, let number = left.oldLineNumber { oldTexts[number] = left.text }
            if let right = row.right, let number = right.newLineNumber { newTexts[number] = right.text }
            if let left = row.left, let right = row.right, left.kind == .deletion, right.kind == .addition {
                let ranges = IntralineDiff.changedRanges(old: left.text, new: right.text)
                intraline[row.id] = IntralineSpans(old: ranges.old, new: ranges.new)
            }
        }

        var gapsByExpanderID: [String: DiffGap] = [:]
        for case .gap(let gap) in DiffBlockBuilder.blocks(for: file) {
            gapsByExpanderID[DiffRowItemBuilder.expanderID(path: file.path, gapID: gap.id)] = gap
        }

        return DiffFileLayout(
            items: items,
            intraline: intraline,
            lineTexts: [.old: oldTexts, .new: newTexts],
            gapsByExpanderID: gapsByExpanderID
        )
    }
}
