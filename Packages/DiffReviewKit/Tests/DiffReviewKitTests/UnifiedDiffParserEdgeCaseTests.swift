import Foundation
import Testing

@testable import DiffReviewKit

@Suite("UnifiedDiffParser edge cases")
struct UnifiedDiffParserEdgeCaseTests {
    private func parse(_ lines: [String]) -> [DiffFile] {
        UnifiedDiffParser.parse(lines.joined(separator: "\n"))
    }

    @Test("a deleted `-- sql comment` line and an added `++ x` line are content, not headers")
    func dashDashContentLines() throws {
        let files = parse([
            "diff --git a/q.sql b/q.sql",
            "--- a/q.sql",
            "+++ b/q.sql",
            "@@ -1,2 +1,2 @@",
            "--- sql comment",
            "+++ x",
            " keep",
        ])
        let file = try #require(files.first)
        #expect(file.path == "q.sql")
        let hunk = try #require(file.hunks.first)
        #expect(hunk.lines.count == 3)
        #expect(hunk.lines[0].kind == .deletion)
        #expect(hunk.lines[0].text == "-- sql comment")
        #expect(hunk.lines[0].oldLineNumber == 1)
        #expect(hunk.lines[1].kind == .addition)
        #expect(hunk.lines[1].text == "++ x")
        #expect(hunk.lines[1].newLineNumber == 1)
    }

    @Test("a path containing a space keeps its name; git's trailing tab is trimmed")
    func pathWithSpace() throws {
        let files = parse([
            "diff --git a/my file.txt b/my file.txt",
            "--- a/my file.txt\t",
            "+++ b/my file.txt\t",
            "@@ -1 +1 @@",
            "-a",
            "+b",
        ])
        #expect(files.first?.path == "my file.txt")
    }

    @Test("a C-quoted unicode path is decoded")
    func quotedUnicodePath() throws {
        let files = parse([
            #"diff --git "a/caf\303\251.txt" "b/caf\303\251.txt""#,
            #"--- "a/caf\303\251.txt""#,
            #"+++ "b/caf\303\251.txt""#,
            "@@ -1 +1 @@",
            "-a",
            "+b",
        ])
        #expect(files.first?.path == "café.txt")
    }

    @Test("a quoted path with escaped quote and tab is decoded; a binary file falls back to the header")
    func quotedHeaderFallback() throws {
        let files = parse([
            #"diff --git "a/we\"ird\tname.bin" "b/we\"ird\tname.bin""#,
            "Binary files differ",
        ])
        let file = try #require(files.first)
        #expect(file.path == "we\"ird\tname.bin")
        #expect(file.isBinaryOrHunkless)
    }

    @Test("`\\ No newline at end of file` marks the preceding line and is not a row")
    func noNewlineAtEndOfFile() throws {
        let files = parse([
            "diff --git a/f b/f",
            "--- a/f",
            "+++ b/f",
            "@@ -1,2 +1,2 @@",
            " same",
            "-old",
            "\\ No newline at end of file",
            "+new",
            "\\ No newline at end of file",
        ])
        let hunk = try #require(files.first?.hunks.first)
        #expect(hunk.lines.count == 3)
        #expect(hunk.lines[0].hasNoNewlineAtEnd == false)
        #expect(hunk.lines[1].hasNoNewlineAtEnd)
        #expect(hunk.lines[2].hasNoNewlineAtEnd)
    }

    @Test("a rename with a modification reports both paths")
    func renameWithEdit() throws {
        let files = parse([
            "diff --git a/old name.txt b/new name.txt",
            "similarity index 80%",
            "rename from old name.txt",
            "rename to new name.txt",
            "--- a/old name.txt\t",
            "+++ b/new name.txt\t",
            "@@ -1 +1 @@",
            "-a",
            "+b",
        ])
        let file = try #require(files.first)
        #expect(file.kind == .renamed)
        #expect(file.path == "new name.txt")
        #expect(file.oldPath == "old name.txt")
    }

    @Test("hunk ranges are stored on DiffHunk, with a missing count meaning 1")
    func hunkRanges() throws {
        let files = parse([
            "diff --git a/f b/f",
            "--- a/f",
            "+++ b/f",
            "@@ -10,3 +12 @@ func x()",
            " a",
        ])
        let hunk = try #require(files.first?.hunks.first)
        #expect(hunk.oldRange == HunkRange(start: 10, count: 3))
        #expect(hunk.newRange == HunkRange(start: 12, count: 1))
        #expect(hunk.lines[0].oldLineNumber == 10)
        #expect(hunk.lines[0].newLineNumber == 12)
    }

    @Test("ids are deterministic across parses and unique within a file")
    func deterministicIDs() throws {
        let text = [
            "diff --git a/f b/f",
            "--- a/f",
            "+++ b/f",
            "@@ -1,2 +1,2 @@",
            "-a",
            "+b",
            "@@ -9,2 +9,2 @@",
            "-c",
            "+d",
        ].joined(separator: "\n")
        let first = try #require(UnifiedDiffParser.parse(text).first)
        let second = try #require(UnifiedDiffParser.parse(text).first)
        #expect(first == second)
        let ids = first.hunks.flatMap { [$0.id] + $0.lines.map(\.id) }
        #expect(Set(ids).count == ids.count)
    }

    @Test("decodePath/unquoteCStyle handle octal, escapes and plain paths")
    func decodePath() {
        #expect(UnifiedDiffParser.decodePath("plain.txt\t") == "plain.txt")
        #expect(UnifiedDiffParser.decodePath(#""a\\b""#) == #"a\b"#)
        #expect(UnifiedDiffParser.unquoteCStyle(#""\346\227\245\346\234\254""#) == "日本")
    }
}
