import Testing

@testable import DiffReviewKit

@Suite("DiffRowItemBuilder")
struct DiffRowItemTests {
    private func context(_ number: Int) -> DiffLine {
        DiffLine(kind: .context, text: "c\(number)", oldLineNumber: number, newLineNumber: number)
    }

    /// A two-line context hunk starting at `start`, so its header and row count are predictable.
    private func hunk(start: Int, header: String) -> DiffHunk {
        DiffHunk(header: header, lines: [context(start), context(start + 1)])
    }

    private func file(path: String = "a.txt", hunks: [DiffHunk]) -> DiffFile {
        DiffFile(path: path, kind: .modified, hunks: hunks)
    }

    private func expanderItems(_ items: [DiffRowItem]) -> [DiffRowItem.Expander] {
        items.compactMap { item -> DiffRowItem.Expander? in
            guard case .expander(let expander) = item else { return nil }
            return expander
        }
    }

    private let middleFile = DiffFile(
        path: "m.txt",
        kind: .modified,
        hunks: [
            DiffHunk(
                header: "@@ -1,2 +1,2 @@",
                lines: [DiffLine(kind: .context, text: "a", oldLineNumber: 1, newLineNumber: 1)]
            ),
            DiffHunk(
                header: "@@ -50,2 +50,2 @@",
                lines: [DiffLine(kind: .context, text: "b", oldLineNumber: 50, newLineNumber: 50)]
            ),
        ]
    )

    @Test("an untouched middle gap merges its expander with the following hunk's header")
    func expanderMergesHeader() {
        let items = DiffRowItemBuilder.items(for: middleFile, gaps: [:])
        // One expander for the middle gap, and one for the bottom gap after the last hunk.
        let expanders = expanderItems(items)
        #expect(expanders.count == 2)
        #expect(expanders.first?.id == "m.txt|gap|mid-3-3")
        #expect(expanders.first?.hunkHeader == "@@ -50,2 +50,2 @@")
        #expect(expanders.first?.offersUp == true)
        #expect(expanders.first?.offersDown == true)
        #expect(expanders.first?.offersAll == false)
        #expect(expanders.last?.hunkHeader == nil)
        // The following hunk's header is carried by the expander, so no standalone header row.
        let headers = items.filter { if case .hunkHeader = $0 { true } else { false } }
        #expect(headers.count == 1)
    }

    @Test("a middle gap with 20 or fewer lines left collapses to one expand-all button")
    func collapsesToExpandAll() {
        let gap = DiffGap(id: "mid-3-3", oldStart: 3, newStart: 3, lineCount: 15, position: .middle)
        let state = RevealedGap(expansion: GapExpansion(), lineCount: 15, top: [], bottom: [])
        let items = DiffRowItemBuilder.items(for: middleFile, gaps: [gap.id: state])
        let expander = expanderItems(items).first
        #expect(expander?.offersAll == true)
        #expect(expander?.offersUp == false)
        #expect(expander?.offersDown == false)
        #expect(expander?.remaining == 15)
    }

    @Test("a fully expanded gap drops its row and its @@ header, leaving the revealed lines")
    func fullyExpandedDropsHeader() {
        let gap = DiffGap(id: "mid-3-3", oldStart: 3, newStart: 3, lineCount: 2, position: .middle)
        let revealed = [context(3), context(4)]
        let state = RevealedGap(
            expansion: GapExpansion(revealedFromTop: 2),
            lineCount: 2,
            top: revealed,
            bottom: []
        )
        let items = DiffRowItemBuilder.items(for: middleFile, gaps: [gap.id: state])
        // The middle gap's expander is gone; only the bottom gap (length still unknown) remains.
        #expect(!items.contains { $0.id == "m.txt|gap|mid-3-3" })
        let headers = items.filter { if case .hunkHeader = $0 { true } else { false } }
        #expect(headers.count == 1, "only the first hunk's header should remain")
        #expect(items.first?.id == "m.txt|h0|header")
    }

    @Test("a top gap merges with hunk 1 and offers only ↑")
    func topGap() {
        let topFile = file(hunks: [hunk(start: 100, header: "@@ -100,2 +100,2 @@")])
        let items = DiffRowItemBuilder.items(for: topFile, gaps: [:])
        let expander = expanderItems(items).first
        #expect(expander?.hunkHeader == "@@ -100,2 +100,2 @@")
        #expect(expander?.offersUp == true)
        #expect(expander?.offersDown == false)
        #expect(expander?.remaining == 99)
    }

    @Test("a short top gap collapses to the single expand-all button")
    func shortTopGapExpandsAll() {
        let topFile = file(hunks: [hunk(start: 10, header: "@@ -10,2 +10,2 @@")])
        let expander = expanderItems(DiffRowItemBuilder.items(for: topFile, gaps: [:])).first
        #expect(expander?.remaining == 9)
        #expect(expander?.offersAll == true)
        #expect(expander?.offersUp == false)
    }

    @Test("a bottom gap offers only ↓ and carries no hunk header")
    func bottomGap() {
        let bottomFile = file(hunks: [hunk(start: 1, header: "@@ -1,2 +1,2 @@")])
        let items = DiffRowItemBuilder.items(for: bottomFile, gaps: [:])
        let expander = expanderItems(items).first
        #expect(expander?.hunkHeader == nil)
        #expect(expander?.offersDown == true)
        #expect(expander?.offersUp == false)
        #expect(expander?.remaining == nil, "bottom gap length is unknown until its file is fetched")
    }

    @Test("a hunk starting at line 1 with no gap before it keeps a plain header")
    func plainHeaderWithoutGap() {
        let items = DiffRowItemBuilder.items(
            for: file(hunks: [hunk(start: 1, header: "@@ -1,2 +1,2 @@")]),
            gaps: [:]
        )
        #expect(items.first?.id == "a.txt|h0|header")
    }

    @Test("adjacent hunks with no hidden lines between them each keep their header")
    func adjacentHunksKeepHeaders() {
        let adjacent = file(hunks: [
            hunk(start: 1, header: "@@ -1,2 +1,2 @@"),
            hunk(start: 3, header: "@@ -3,2 +3,2 @@"),
        ])
        let headers = DiffRowItemBuilder.items(for: adjacent, gaps: [:]).compactMap { item -> String? in
            guard case .hunkHeader(_, let text) = item else { return nil }
            return text
        }
        #expect(headers == ["@@ -1,2 +1,2 @@", "@@ -3,2 +3,2 @@"])
    }

    @Test("revealed top lines come before the expander, and revealed bottom lines after it")
    func revealedOrdering() {
        let gap = DiffGap(id: "mid-3-3", oldStart: 3, newStart: 3, lineCount: 40, position: .middle)
        let state = RevealedGap(
            expansion: GapExpansion(revealedFromTop: 1, revealedFromBottom: 1),
            lineCount: 40,
            top: [context(3)],
            bottom: [context(42)]
        )
        let items = DiffRowItemBuilder.items(for: middleFile, gaps: [gap.id: state])
        let order = items.map { item -> String in
            switch item {
            case .expander: "expander"
            case .hunkHeader: "header"
            case .line(let row): row.left?.text ?? "?"
            }
        }
        #expect(order == ["header", "a", "c3", "expander", "c42", "b", "expander"])
    }

    @Test("ids are prefixed with the file path, so identical hunks in two files stay unique")
    func idsUniqueAcrossFiles() {
        let first = file(path: "one.txt", hunks: [hunk(start: 1, header: "@@ -1,2 +1,2 @@")])
        let second = file(path: "two.txt", hunks: [hunk(start: 1, header: "@@ -1,2 +1,2 @@")])
        let ids = (DiffRowItemBuilder.items(for: first, gaps: [:]) + DiffRowItemBuilder.items(for: second, gaps: [:]))
            .map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.allSatisfy { $0.hasPrefix("one.txt|") || $0.hasPrefix("two.txt|") })
    }

    @Test("a bottom gap resolved to zero lines disappears entirely")
    func emptyBottomGapDisappears() {
        let bottomFile = file(hunks: [hunk(start: 1, header: "@@ -1,2 +1,2 @@")])
        let state = RevealedGap(expansion: GapExpansion(), lineCount: 0, top: [], bottom: [])
        let items = DiffRowItemBuilder.items(
            for: bottomFile,
            gaps: ["bottom": state]
        )
        #expect(expanderItems(items).isEmpty)
    }
}
