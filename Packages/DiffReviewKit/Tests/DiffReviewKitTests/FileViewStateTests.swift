import Testing

@testable import DiffReviewKit

@Suite("FileViewState")
struct FileViewStateTests {
    private func file(_ path: String, changedLines: Int = 1, text: String = "t") -> DiffFile {
        let lines = (0..<changedLines).map { index in
            DiffLine(kind: .addition, text: text, oldLineNumber: nil, newLineNumber: index + 1)
        }
        let hunk = DiffHunk(header: "@@ -0,0 +1,\(changedLines) @@", lines: lines)
        return DiffFile(path: path, kind: .modified, hunks: [hunk])
    }

    @Test("toggling Viewed on collapses the file and records its signature")
    func viewedCollapses() {
        var state = FileViewState()
        let alpha = file("alpha.swift")
        state.toggleViewed(alpha)
        #expect(state.viewedFiles["alpha.swift"] == alpha.contentSignature)
        #expect(state.collapsedFilePaths.contains("alpha.swift"))
    }

    @Test("toggling Viewed off expands the file again")
    func unviewedExpands() {
        var state = FileViewState()
        let alpha = file("alpha.swift")
        state.toggleViewed(alpha)
        state.toggleViewed(alpha)
        #expect(state.viewedFiles["alpha.swift"] == nil)
        #expect(!state.collapsedFilePaths.contains("alpha.swift"))
    }

    @Test("alpha viewed file whose content is unchanged stays viewed and collapsed on refresh")
    func unchangedStaysViewed() {
        var state = FileViewState()
        let alpha = file("alpha.swift")
        state.toggleViewed(alpha)
        state.reconcile(with: [file("alpha.swift")])
        #expect(state.viewedFiles["alpha.swift"] == alpha.contentSignature)
        #expect(state.collapsedFilePaths.contains("alpha.swift"))
    }

    @Test("alpha viewed file whose content changed is un-viewed and expanded on refresh")
    func changedBecomesExpanded() {
        var state = FileViewState()
        state.toggleViewed(file("alpha.swift", text: "old"))
        state.reconcile(with: [file("alpha.swift", text: "new")])
        #expect(state.viewedFiles["alpha.swift"] == nil)
        #expect(!state.collapsedFilePaths.contains("alpha.swift"))
    }

    @Test("a viewed, unchanged file the reviewer re-expanded is not collapsed again on refresh")
    func reexpandedViewedFileStaysExpanded() {
        var state = FileViewState()
        let alpha = file("alpha.swift")
        state.toggleViewed(alpha)
        state.reconcile(with: [file("alpha.swift")])
        state.collapsedFilePaths.remove("alpha.swift")
        state.reconcile(with: [file("alpha.swift")])
        #expect(state.viewedFiles["alpha.swift"] == alpha.contentSignature)
        #expect(!state.collapsedFilePaths.contains("alpha.swift"))
    }

    @Test("files that left the diff are pruned from viewed and collapsed state")
    func removedPruned() {
        var state = FileViewState()
        state.toggleViewed(file("gone.swift"))
        state.reconcile(with: [file("kept.swift")])
        #expect(state.viewedFiles.isEmpty)
        #expect(state.collapsedFilePaths.isEmpty)
    }

    @Test("alpha file over 500 changed lines starts collapsed on first sight")
    func bigFileAutoCollapses() {
        var state = FileViewState()
        state.reconcile(with: [file("big.swift", changedLines: 501), file("small.swift", changedLines: 500)])
        #expect(state.collapsedFilePaths == ["big.swift"])
    }

    @Test("auto-collapse does not reapply once alpha path has been seen, so an expanded big file stays expanded")
    func autoCollapseOnlyOnFirstSight() {
        var state = FileViewState()
        state.reconcile(with: [file("big.swift", changedLines: 600)])
        state.collapsedFilePaths.remove("big.swift")
        state.reconcile(with: [file("big.swift", changedLines: 600)])
        #expect(!state.collapsedFilePaths.contains("big.swift"))
    }

    @Test("an unviewed file keeps the collapse state the reviewer gave it across refreshes")
    func userCollapseKept() {
        var state = FileViewState()
        state.reconcile(with: [file("alpha.swift")])
        state.collapsedFilePaths.insert("alpha.swift")
        state.reconcile(with: [file("alpha.swift", text: "changed")])
        #expect(state.collapsedFilePaths.contains("alpha.swift"))
    }
}
