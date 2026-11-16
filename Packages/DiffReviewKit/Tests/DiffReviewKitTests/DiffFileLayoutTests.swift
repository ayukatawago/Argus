import Testing

@testable import DiffReviewKit

@Suite("DiffFileLayout")
struct DiffFileLayoutTests {
    private func modifiedFile(path: String) -> DiffFile {
        let hunk = DiffHunk(
            header: "@@ -1,2 +1,2 @@ func x()",
            lines: [
                DiffLine(kind: .deletion, text: "let value = 1", oldLineNumber: 1, newLineNumber: nil),
                DiffLine(kind: .addition, text: "let value = 2", oldLineNumber: nil, newLineNumber: 1),
                DiffLine(kind: .context, text: "return value", oldLineNumber: 2, newLineNumber: 2),
            ]
        )
        return DiffFile(path: path, kind: .modified, hunks: [hunk])
    }

    @Test("a deletion paired with an addition gets intraline spans, plain context does not")
    func intralineOnlyForPairedModifications() {
        let layout = DiffFileLayout.make(file: modifiedFile(path: "a.swift"), gaps: [:])
        let modified = layout.items.compactMap { item -> String? in
            guard case .line(let row) = item, row.left?.kind == .deletion else { return nil }
            return row.id
        }
        #expect(modified.count == 1)
        #expect(layout.intraline[modified[0]] != nil)
        #expect(layout.intraline.count == 1)
    }

    @Test("line texts are keyed by line number per side")
    func lineTextsPerSide() {
        let layout = DiffFileLayout.make(file: modifiedFile(path: "a.swift"), gaps: [:])
        #expect(layout.lineTexts[.old]?[1] == "let value = 1")
        #expect(layout.lineTexts[.new]?[1] == "let value = 2")
        #expect(layout.lineTexts[.old]?[2] == "return value")
        #expect(layout.lineTexts[.new]?[2] == "return value")
    }

    @Test("each expander id maps back to the gap it stands for, top and bottom")
    func expanderLookup() {
        let line = DiffLine(kind: .context, text: "x", oldLineNumber: 10, newLineNumber: 10)
        let hunk = DiffHunk(header: "@@ -10,1 +10,1 @@", lines: [line])
        let file = DiffFile(path: "a.swift", kind: .modified, hunks: [hunk])
        let layout = DiffFileLayout.make(file: file, gaps: [:])
        let expanderIDs = layout.items.compactMap { item -> String? in
            guard case .expander(let expander) = item else { return nil }
            return expander.id
        }
        // A hunk starting at line 10 leaves a top gap and a bottom gap.
        #expect(expanderIDs.count == 2)
        let positions = expanderIDs.map { layout.gapsByExpanderID[$0]?.position }
        #expect(positions == [.top, .bottom])
        #expect(expanderIDs.allSatisfy { $0.hasPrefix("a.swift|gap|") })
    }
}
