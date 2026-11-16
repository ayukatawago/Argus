import Testing

@testable import DiffReviewKit

@Suite("DiffFile.contentSignature")
struct DiffFileContentSignatureTests {
    private func file(lineID: String = "x", text: String = "changed") -> DiffFile {
        let lines = [
            DiffLine(kind: .context, text: "keep", oldLineNumber: 1, newLineNumber: 1, id: lineID),
            DiffLine(kind: .addition, text: text, oldLineNumber: nil, newLineNumber: 2, id: lineID + "-2"),
        ]
        let hunk = DiffHunk(header: "@@ -1,2 +1,2 @@", lines: lines, id: lineID)
        return DiffFile(path: "a.swift", kind: .modified, hunks: [hunk])
    }

    @Test("identical content gives the same signature")
    func stable() {
        #expect(file().contentSignature == file().contentSignature)
    }

    @Test("changing one line's text changes the signature")
    func lineChange() {
        #expect(file(text: "one").contentSignature != file(text: "two").contentSignature)
    }

    @Test("changing a line's kind changes the signature, even with the same text")
    func kindChange() {
        let addition = DiffLine(kind: .addition, text: "t", oldLineNumber: nil, newLineNumber: 1)
        let deletion = DiffLine(kind: .deletion, text: "t", oldLineNumber: 1, newLineNumber: nil)
        let added = DiffFile(path: "a", kind: .modified, hunks: [DiffHunk(header: "@@", lines: [addition])])
        let deleted = DiffFile(path: "a", kind: .modified, hunks: [DiffHunk(header: "@@", lines: [deletion])])
        #expect(added.contentSignature != deleted.contentSignature)
    }

    @Test("ids are ignored: the same content with different ids has the same signature")
    func idsIgnored() {
        #expect(file(lineID: "first").contentSignature == file(lineID: "second").contentSignature)
    }

    @Test("a file with no hunks still has a signature distinct from one with content")
    func emptyHunks() {
        let empty = DiffFile(path: "a.swift", kind: .modified, hunks: [])
        #expect(empty.contentSignature != file().contentSignature)
    }
}
