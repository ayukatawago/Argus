import Testing

@testable import DiffReviewKit

@Suite("DiffSearch")
struct DiffSearchTests {
    private func file(_ path: String, _ texts: [String]) -> DiffFile {
        let lines = texts.enumerated().map { index, text in
            DiffLine(kind: .addition, text: text, oldLineNumber: nil, newLineNumber: index + 1)
        }
        let hunk = DiffHunk(header: "@@ -0,0 +1,\(texts.count) @@", lines: lines)
        return DiffFile(path: path, kind: .modified, hunks: [hunk])
    }

    @Test("matches are found across every file, in display order, case-insensitively")
    func acrossFiles() {
        let matches = DiffSearch.matches(
            in: [file("a.swift", ["let Foo = 1", "bar"]), file("b.swift", ["foo()"])],
            query: "foo"
        )
        #expect(matches.map(\.filePath) == ["a.swift", "b.swift"])
        #expect(matches.count == 2)
    }

    @Test("identical hunks in two files give match ids that are still unique")
    func uniqueRowIDs() {
        let matches = DiffSearch.matches(
            in: [file("a.swift", ["hit"]), file("b.swift", ["hit"])],
            query: "hit"
        )
        #expect(Set(matches).count == 2)
    }

    @Test("an empty or whitespace query matches nothing")
    func emptyQuery() {
        let files = [file("a.swift", ["anything"])]
        #expect(DiffSearch.matches(in: files, query: "").isEmpty)
        #expect(DiffSearch.matches(in: files, query: "   ").isEmpty)
    }

    @Test("a query is trimmed before matching")
    func trimmed() {
        #expect(DiffSearch.matches(in: [file("a.swift", ["alpha"])], query: " alpha ").count == 1)
    }

    @Test("a match on the old side of a paired row counts")
    func pairedRow() {
        let deletion = DiffLine(kind: .deletion, text: "old token", oldLineNumber: 1, newLineNumber: nil)
        let addition = DiffLine(kind: .addition, text: "new", oldLineNumber: nil, newLineNumber: 1)
        let hunk = DiffHunk(header: "@@ -1 +1 @@", lines: [deletion, addition])
        let paired = DiffFile(path: "p.swift", kind: .modified, hunks: [hunk])
        #expect(DiffSearch.matches(in: [paired], query: "token").count == 1)
    }

    @Test("a file with no hunks contributes no matches")
    func hunkless() {
        let empty = DiffFile(path: "bin.dat", kind: .modified, hunks: [])
        #expect(DiffSearch.matches(in: [empty], query: "x").isEmpty)
    }
}
