import Foundation

/// One flat row of a file's diff as the all-files list renders it: a hunk header, a gap expander
/// (optionally carrying the following hunk's `@@` text), or a line row. Ids are prefixed with the
/// file path, so they stay unique when several files share a list.
enum DiffRowItem: Identifiable {
    case hunkHeader(id: String, text: String)
    case expander(Expander)
    case line(SideBySideRow)

    struct Expander: Identifiable, Equatable {
        let id: String
        /// Lines still hidden; `nil` while a bottom gap's length is unknown.
        let remaining: Int?
        /// The ↑ button: reveals lines just above the next hunk.
        let offersUp: Bool
        /// The ↓ button: reveals lines just below the previous hunk.
        let offersDown: Bool
        /// The single ↕ button that reveals the whole gap, shown once one step is enough.
        let offersAll: Bool
        /// The following hunk's `@@` header, merged into this row. `nil` for a bottom gap.
        let hunkHeader: String?
    }

    var id: String {
        switch self {
        case .hunkHeader(let id, _): id
        case .expander(let expander): expander.id
        case .line(let row): row.id
        }
    }
}

/// One file's rows, as handed to the list: a section of the flat row items.
struct DiffRowSection {
    let filePath: String
    let items: [DiffRowItem]
}

/// What a single gap currently shows.
struct RevealedGap: Equatable {
    var expansion: GapExpansion
    /// The gap's length, once known (always known for top and middle gaps).
    var lineCount: Int?
    /// Revealed lines just below the previous hunk, in file order.
    var top: [DiffLine]
    /// Revealed lines just above the next hunk, in file order.
    var bottom: [DiffLine]
}

/// Lays out a file's blocks (hunks and gaps) as flat rows. Pure, so the merging rules are testable.
///
/// Per gap, the rows are: revealed top lines, then the expander (merged with the following hunk's
/// `@@` header), then revealed bottom lines. A fully expanded gap emits only its revealed lines, so
/// its `@@` header disappears and the code reads as one block. A hunk that follows a gap never gets a
/// header of its own, since the gap's expander carries it. A hunk with no gap before it, and one
/// that directly follows another hunk, keep a plain header.
enum DiffRowItemBuilder {
    static func items(for file: DiffFile, gaps: [String: RevealedGap]) -> [DiffRowItem] {
        let blocks = DiffBlockBuilder.blocks(for: file)
        var items: [DiffRowItem] = []
        var hunkIndex = 0

        for (index, block) in blocks.enumerated() {
            switch block {
            case .hunk(let hunk):
                let followsGap: Bool = {
                    guard index > 0, case .gap = blocks[index - 1] else { return false }
                    return true
                }()
                if !followsGap {
                    items.append(.hunkHeader(id: "\(file.path)|h\(hunkIndex)|header", text: hunk.header))
                }
                let rows = SideBySideBuilder.rows(for: hunk)
                for (rowIndex, row) in rows.enumerated() {
                    items.append(.line(prefixed(row, id: "\(file.path)|h\(hunkIndex)|\(rowIndex)")))
                }
                hunkIndex += 1

            case .gap(let gap):
                let state =
                    gaps[gap.id]
                    ?? RevealedGap(expansion: GapExpansion(), lineCount: gap.lineCount, top: [], bottom: [])
                items += revealedRows(state.top)

                if !state.expansion.isFullyExpanded(lineCount: state.lineCount) {
                    let nextHunk = nextHunkHeader(after: index, in: blocks)
                    items.append(.expander(expander(for: gap, in: file, state: state, hunkHeader: nextHunk)))
                }
                items += revealedRows(state.bottom)
            }
        }
        return items
    }

    /// Id of the expander row for a gap, prefixed with the file path like every row id.
    static func expanderID(path: String, gapID: String) -> String {
        "\(path)|gap|\(gapID)"
    }

    private static func expander(
        for gap: DiffGap,
        in file: DiffFile,
        state: RevealedGap,
        hunkHeader: String?
    ) -> DiffRowItem.Expander {
        let remaining = state.expansion.remaining(lineCount: state.lineCount)
        let collapsesToAll = remaining.map { $0 <= GapExpansion.defaultStep } ?? false
        return DiffRowItem.Expander(
            id: expanderID(path: file.path, gapID: gap.id),
            remaining: remaining,
            offersUp: !collapsesToAll && gap.position != .bottom,
            offersDown: !collapsesToAll && gap.position != .top,
            offersAll: collapsesToAll,
            hunkHeader: gap.position == .bottom ? nil : hunkHeader
        )
    }

    private static func nextHunkHeader(after index: Int, in blocks: [DiffBlock]) -> String? {
        guard index + 1 < blocks.count, case .hunk(let hunk) = blocks[index + 1] else { return nil }
        return hunk.header
    }

    private static func revealedRows(_ lines: [DiffLine]) -> [DiffRowItem] {
        SideBySideBuilder.rows(for: lines).map { DiffRowItem.line($0) }
    }

    private static func prefixed(_ row: SideBySideRow, id: String) -> SideBySideRow {
        SideBySideRow(id: id, left: row.left, right: row.right)
    }
}
