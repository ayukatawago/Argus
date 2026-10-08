import Foundation
import Testing

@testable import DiffReviewKit

@Suite("PromptComposer")
struct PromptComposerTests {
    private func file() -> DiffFile {
        DiffFile(
            path: "Sources/A.swift",
            kind: .modified,
            hunks: [
                DiffHunk(
                    header: "@@ -5,2 +5,3 @@",
                    lines: [
                        DiffLine(kind: .context, text: "ctx", oldLineNumber: 5, newLineNumber: 5),
                        DiffLine(kind: .deletion, text: "gone", oldLineNumber: 6, newLineNumber: nil),
                        DiffLine(kind: .addition, text: "new", oldLineNumber: nil, newLineNumber: 6),
                    ],
                )
            ],
        )
    }

    @Test("reply prompt forbids edits and embeds the hunk and comment")
    func replyPrompt() {
        let comment = ReviewComment(filePath: "Sources/A.swift", side: .new, lineNumber: 6, body: "Why?")
        let prompt = PromptComposer.compose(comment: comment, file: file(), mode: .reply)
        #expect(prompt.contains("Do not modify any files."))
        #expect(prompt.contains("File: Sources/A.swift"))
        #expect(prompt.contains("Line 6 (new side):"))
        #expect(prompt.contains("@@ -5,2 +5,3 @@\n ctx\n-gone\n+new"))
        #expect(prompt.hasSuffix("Reviewer comment:\nWhy?"))
    }

    @Test("apply prompt asks for the change and a multi-line range is described")
    func applyPromptRange() {
        let comment = ReviewComment(
            filePath: "Sources/A.swift", side: .old, startLineNumber: 5, lineNumber: 6, body: "Fix")
        let prompt = PromptComposer.compose(comment: comment, file: file(), mode: .apply)
        #expect(prompt.contains("Make the requested change directly"))
        #expect(prompt.contains("Lines 5-6 (old side):"))
    }

    @Test("a comment on a line outside every hunk reports missing context")
    func contextNotFound() {
        let comment = ReviewComment(filePath: "Sources/A.swift", side: .new, lineNumber: 99, body: "x")
        let prompt = PromptComposer.compose(comment: comment, file: file(), mode: .reply)
        #expect(prompt.contains("(context not found)"))
    }
}

@Suite("SideBySideBuilder.rows")
struct SideBySideBuilderTests {
    private func line(_ kind: DiffLine.Kind, _ old: Int?, _ new: Int?) -> DiffLine {
        DiffLine(kind: kind, text: "t", oldLineNumber: old, newLineNumber: new)
    }

    @Test("context lines appear on both sides")
    func context() {
        let rows = SideBySideBuilder.rows(for: [line(.context, 1, 1)])
        #expect(rows.count == 1)
        #expect(rows[0].left == rows[0].right)
    }

    @Test("deletions pair index-wise with the following additions; extras get an empty cell")
    func pairing() {
        let rows = SideBySideBuilder.rows(for: [
            line(.deletion, 1, nil), line(.deletion, 2, nil), line(.deletion, 3, nil),
            line(.addition, nil, 1),
        ])
        #expect(rows.count == 3)
        #expect(rows[0].left?.oldLineNumber == 1)
        #expect(rows[0].right?.newLineNumber == 1)
        #expect(rows[1].left?.oldLineNumber == 2)
        #expect(rows[1].right == nil)
        #expect(rows[2].right == nil)
    }

    @Test("a pure addition has no left cell and row ids are unique and stable")
    func additionsAndIDs() {
        let lines = [line(.context, 1, 1), line(.addition, nil, 2), line(.addition, nil, 3)]
        let rows = SideBySideBuilder.rows(for: lines)
        #expect(rows.count == 3)
        #expect(rows[1].left == nil)
        #expect(Set(rows.map(\.id)).count == rows.count)
        #expect(rows.map(\.id) == SideBySideBuilder.rows(for: lines).map(\.id))
    }
}

@Suite("DiffSizeStat")
struct DiffSizeStatTests {
    @Test("sums file, addition and deletion counts")
    func totals() {
        let hunk = DiffHunk(
            header: "@@ -1,2 +1,2 @@",
            lines: [
                DiffLine(kind: .deletion, text: "a", oldLineNumber: 1, newLineNumber: nil),
                DiffLine(kind: .addition, text: "b", oldLineNumber: nil, newLineNumber: 1),
                DiffLine(kind: .addition, text: "c", oldLineNumber: nil, newLineNumber: 2),
            ]
        )
        let files = [
            DiffFile(path: "a", kind: .modified, hunks: [hunk]),
            DiffFile(path: "b", kind: .added, hunks: []),
        ]
        let stat = DiffSizeStat(label: "Total", files: files)
        #expect(stat.label == "Total")
        #expect(stat.fileCount == 2)
        #expect(stat.additions == 2)
        #expect(stat.deletions == 1)
        #expect(DiffSizeStat(label: "Empty", files: []) == DiffSizeStat(label: "Empty", files: []))
    }
}

@Suite("RevisionResolver parsing")
struct RevisionResolverParsingTests {
    @Test("drops only remote HEAD symbolic refs and shortens refnames")
    func branches() {
        let output = [
            "refs/heads/main",
            "refs/heads/feature/HEAD",
            "refs/remotes/origin/HEAD",
            "refs/remotes/origin/main",
            "refs/remotes/up/stream/HEAD",
        ].joined(separator: "\n")
        #expect(
            RevisionResolver.parseBranches(output) == [
                "main", "feature/HEAD", "origin/main", "up/stream/HEAD",
            ])
    }

    @Test("parses six-field log lines, flags root commits, and skips malformed lines")
    func commits() {
        let sep = "\u{1f}"
        let child = ["h1", "h", "fix: a", "Ann", "2 days ago", "p1"].joined(separator: sep)
        let root = ["h2", "h", "init", "Bob", "1 year ago", ""].joined(separator: sep)
        let commits = RevisionResolver.parseCommits([child, "garbage", root].joined(separator: "\n"))
        #expect(commits.map(\.hash) == ["h1", "h2"])
        #expect(commits[0].subject == "fix: a")
        #expect(commits[0].isRoot == false)
        #expect(commits[1].isRoot)
    }
}
