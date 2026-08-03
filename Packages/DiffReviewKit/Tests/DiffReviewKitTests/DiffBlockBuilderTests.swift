import Testing

@testable import DiffReviewKit

@Suite("DiffBlockBuilder")
struct DiffBlockBuilderTests {
    private func file(hunks: [DiffHunk]) -> DiffFile {
        DiffFile(path: "Sources/Foo.swift", kind: .modified, hunks: hunks)
    }

    private func hunk(_ header: String) -> DiffHunk {
        DiffHunk(header: header, lines: [DiffLine(kind: .context, text: "x", oldLineNumber: 1, newLineNumber: 1)])
    }

    @Test("no hunks produces no blocks")
    func noHunks() {
        #expect(DiffBlockBuilder.blocks(for: file(hunks: [])).isEmpty)
    }

    @Test("a hunk starting at line 1 has no top gap")
    func noTopGapAtFileStart() {
        let blocks = DiffBlockBuilder.blocks(for: file(hunks: [hunk("@@ -1,3 +1,4 @@")]))
        #expect(blocks.count == 2)
        guard case .gap(let gap) = blocks.last else {
            Issue.record("expected a trailing bottom gap")
            return
        }
        #expect(gap.position == .bottom)
    }

    @Test("a hunk starting past line 1 has a top gap sized to the lines before it")
    func topGapWhenHunkStartsLater() {
        let blocks = DiffBlockBuilder.blocks(for: file(hunks: [hunk("@@ -10,3 +10,3 @@")]))
        guard case .gap(let top) = blocks.first else {
            Issue.record("expected a leading top gap")
            return
        }
        #expect(top.position == .top)
        #expect(top.oldStart == 1)
        #expect(top.newStart == 1)
        #expect(top.lineCount == 9)
    }

    @Test("adjacent hunks with no unchanged lines between them have no middle gap")
    func noMiddleGapWhenHunksAreAdjacent() {
        let blocks = DiffBlockBuilder.blocks(
            for: file(hunks: [hunk("@@ -1,2 +1,2 @@"), hunk("@@ -3,2 +3,2 @@")])
        )
        let gaps = blocks.compactMap { block -> DiffGap? in
            guard case .gap(let gap) = block else { return nil }
            return gap
        }
        #expect(gaps.count == 1)
        #expect(gaps.first?.position == .bottom)
    }

    @Test("hunks separated by unchanged lines get a sized middle gap")
    func middleGapBetweenHunks() {
        let blocks = DiffBlockBuilder.blocks(
            for: file(hunks: [hunk("@@ -1,2 +1,2 @@"), hunk("@@ -20,2 +20,2 @@")])
        )
        guard case .hunk = blocks[0], case .gap(let middle) = blocks[1], case .hunk = blocks[2] else {
            Issue.record("expected hunk, gap, hunk")
            return
        }
        #expect(middle.position == .middle)
        #expect(middle.oldStart == 3)
        #expect(middle.newStart == 3)
        #expect(middle.lineCount == 17)
    }

    @Test("the trailing gap after the last hunk has no known line count")
    func bottomGapHasNoFixedCount() {
        let blocks = DiffBlockBuilder.blocks(for: file(hunks: [hunk("@@ -1,3 +1,4 @@")]))
        guard case .gap(let bottom) = blocks.last else {
            Issue.record("expected a trailing bottom gap")
            return
        }
        #expect(bottom.position == .bottom)
        #expect(bottom.lineCount == nil)
    }
}
