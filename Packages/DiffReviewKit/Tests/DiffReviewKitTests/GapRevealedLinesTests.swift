import Testing

@testable import DiffReviewKit

@Suite("GapRevealedLines")
struct GapRevealedLinesTests {
    private let source = (1...30).map { "line \($0)" }

    private func file(kind: DiffFile.ChangeKind) -> DiffFile {
        DiffFile(path: "a.txt", kind: kind, hunks: [])
    }

    private func gap(oldStart: Int = 1, newStart: Int = 1, lineCount: Int?) -> DiffGap {
        DiffGap(id: "top", oldStart: oldStart, newStart: newStart, lineCount: lineCount, position: .middle)
    }

    @Test("top reveals from the start of the gap and bottom from its end, without overlapping")
    func topAndBottomSplit() {
        let result = GapRevealedLines.make(
            gap: gap(lineCount: 30),
            file: file(kind: .modified),
            expansion: GapExpansion(revealedFromTop: 3, revealedFromBottom: 2),
            lineCount: 30,
            sourceLines: source
        )
        #expect(result.top.map(\.text) == ["line 1", "line 2", "line 3"])
        #expect(result.bottom.map(\.text) == ["line 29", "line 30"])
        #expect(result.top.first?.newLineNumber == 1)
        #expect(result.bottom.last?.oldLineNumber == 30)
    }

    @Test("overlapping reveals meet in the middle rather than duplicating lines")
    func overlapClamped() {
        let result = GapRevealedLines.make(
            gap: gap(lineCount: 5),
            file: file(kind: .modified),
            expansion: GapExpansion(revealedFromTop: 4, revealedFromBottom: 4),
            lineCount: 5,
            sourceLines: Array(source.prefix(5))
        )
        let ids = (result.top + result.bottom).map(\.id)
        #expect(Set(ids).count == 5)
        #expect(result.top.count + result.bottom.count == 5)
    }

    @Test("an unknown length reveals nothing")
    func unknownLength() {
        let result = GapRevealedLines.make(
            gap: gap(lineCount: nil),
            file: file(kind: .modified),
            expansion: GapExpansion(revealedFromTop: 5),
            lineCount: nil,
            sourceLines: source
        )
        #expect(result.top.isEmpty && result.bottom.isEmpty)
    }

    @Test("ids are deterministic and path-prefixed, and a deleted file has no new-side number")
    func deletedFileIDs() {
        let deleted = DiffFile(path: "gone.txt", kind: .deleted, hunks: [])
        let result = GapRevealedLines.make(
            gap: gap(oldStart: 4, newStart: 1, lineCount: 30),
            file: deleted,
            expansion: GapExpansion(revealedFromTop: 2),
            lineCount: 30,
            sourceLines: source
        )
        #expect(result.top.map(\.id) == ["gone.txt|ctx|4|-", "gone.txt|ctx|5|-"])
        #expect(result.top.first?.newLineNumber == nil)
        #expect(result.top.first?.oldLineNumber == 4)
    }

    @Test("an added file has no old-side number, and its ids say so")
    func addedFileIDs() {
        let added = DiffFile(path: "new.txt", kind: .added, hunks: [])
        let result = GapRevealedLines.make(
            gap: gap(lineCount: 30),
            file: added,
            expansion: GapExpansion(revealedFromTop: 1),
            lineCount: 30,
            sourceLines: source
        )
        #expect(result.top.map(\.id) == ["new.txt|ctx|-|1"])
        #expect(result.top.first?.oldLineNumber == nil)
    }

    @Test("the same revealed line gets the same id every time it is built")
    func stableIDs() {
        let build = {
            GapRevealedLines.make(
                gap: gap(lineCount: 30),
                file: file(kind: .modified),
                expansion: GapExpansion(revealedFromTop: 3),
                lineCount: 30,
                sourceLines: source
            ).top.map(\.id)
        }
        #expect(build() == build())
    }
}
