import CoreGraphics
import Testing

@testable import DiffReviewKit

@Suite("DiffLineSelection")
struct DiffLineSelectionTests {
    @Test("a plain click starts a new single-line selection")
    func plainClick() {
        let existing = DiffLineSelection(filePath: "a", side: .new, anchorLine: 3, focusLine: 5)
        let selection = DiffLineSelection.clicked(filePath: "a", side: .new, line: 9, extending: existing, shift: false)
        #expect(selection.anchorLine == 9)
        #expect(selection.focusLine == 9)
    }

    @Test("shift-click extends from the anchor when the file and side match")
    func shiftExtendsSameFileAndSide() {
        let existing = DiffLineSelection(filePath: "a", side: .new, anchorLine: 3, focusLine: 3)
        let selection = DiffLineSelection.clicked(filePath: "a", side: .new, line: 7, extending: existing, shift: true)
        #expect(selection.range == 3...7)
    }

    @Test("shift-click in another file or on the other side starts over")
    func shiftDoesNotCrossFilesOrSides() {
        let existing = DiffLineSelection(filePath: "a", side: .new, anchorLine: 3, focusLine: 3)
        let otherFile = DiffLineSelection.clicked(filePath: "b", side: .new, line: 7, extending: existing, shift: true)
        let otherSide = DiffLineSelection.clicked(filePath: "a", side: .old, line: 7, extending: existing, shift: true)
        #expect(otherFile.anchorLine == 7 && otherFile.focusLine == 7 && otherFile.filePath == "b")
        #expect(otherSide.anchorLine == 7 && otherSide.focusLine == 7)
    }
}

@Suite("DiffSearchState")
struct DiffSearchStateTests {
    private func ref(_ id: String) -> RowRef {
        RowRef(filePath: "a.swift", rowID: id)
    }

    @Test("stepping wraps at both ends")
    func stepWraps() {
        var state = DiffSearchState()
        state.replaceMatches([ref("1"), ref("2"), ref("3")])
        #expect(state.currentMatch == ref("1"))
        #expect(state.step(-1) == ref("3"))
        #expect(state.step(1) == ref("1"))
        #expect(state.step(1) == ref("2"))
    }

    @Test("stepping with no matches returns nil")
    func emptyStep() {
        var state = DiffSearchState()
        #expect(state.step(1) == nil)
        #expect(state.currentMatch == nil)
    }

    @Test("replacing matches keeps the index in range")
    func replaceClamps() {
        var state = DiffSearchState()
        state.replaceMatches([ref("1"), ref("2"), ref("3")])
        state.step(1)
        state.step(1)
        state.replaceMatches([ref("1")])
        #expect(state.currentMatch == ref("1"))
        state.replaceMatches([])
        #expect(state.currentMatch == nil)
    }

    @Test("the current match stays current when the list is rebuilt with extra rows before it")
    func currentSurvivesRebuild() {
        var state = DiffSearchState()
        state.replaceMatches([ref("1"), ref("2"), ref("3")])
        state.step(1)
        state.replaceMatches([ref("0"), ref("1"), ref("2"), ref("3")])
        #expect(state.currentMatch == ref("2"))
    }

    @Test("a new query starts again from its first match")
    func newQueryStartsFromFirst() {
        var state = DiffSearchState()
        state.replaceMatches([ref("1"), ref("2"), ref("3")])
        state.step(1)
        state.resetCurrent()
        state.replaceMatches([ref("7"), ref("8")])
        #expect(state.currentMatch == ref("7"))
    }

    @Test("membership and the current match are separate questions")
    func containsAndCurrent() {
        var state = DiffSearchState()
        state.replaceMatches([ref("1"), ref("2")])
        state.step(1)
        #expect(state.contains(ref("1")))
        #expect(!state.contains(ref("9")))
        #expect(state.isCurrent(ref("2")))
        #expect(!state.isCurrent(ref("1")))
    }
}

@Suite("DiffSelectionCopy")
struct DiffSelectionCopyTests {
    @Test("a line range copies only the lines that exist on that side, in order")
    func lineRange() {
        let texts = [1: "one", 3: "three"]
        #expect(DiffSelectionCopy.text(lines: 1...3, texts: texts) == "one\nthree")
        #expect(DiffSelectionCopy.text(lines: 5...6, texts: texts) == nil)
    }

    @Test("a text selection trims the first and last line to its columns")
    func textSelection() {
        let texts = [1: "let value", 2: "return x"]
        let selection = TextSelectionRange(
            filePath: "a",
            side: .new,
            anchor: TextPosition(line: 1, column: 4),
            focus: TextPosition(line: 2, column: 6)
        )
        #expect(DiffSelectionCopy.text(for: selection, texts: texts) == "value\nreturn")
    }
}

@Suite("DiffFileListView word selection")
@MainActor
struct WordBoundsTests {
    @Test("a word, a whitespace run and a punctuation run each select as one unit")
    func wordBounds() {
        let characters = Array("let foo_1 = (x)")
        #expect(DiffFileListView.wordBounds(in: characters, at: 5) == 4..<9)
        #expect(DiffFileListView.wordBounds(in: characters, at: 3) == 3..<4)
        #expect(DiffFileListView.wordBounds(in: characters, at: 10) == 10..<11)
        #expect(DiffFileListView.wordBounds(in: characters, at: 99) == nil)
    }
}

@Suite("DiffInteractionState")
@MainActor
struct DiffInteractionStateTests {
    private func anchor(_ path: String, line: Int = 4) -> DiffCommentAnchor {
        DiffCommentAnchor(filePath: path, side: .new, startLine: line, endLine: line)
    }

    private func textSelection(_ path: String) -> TextSelectionRange {
        TextSelectionRange(
            filePath: path,
            side: .new,
            anchor: TextPosition(line: 1, column: 0),
            focus: TextPosition(line: 1, column: 3)
        )
    }

    @Test("opening a composer clears a selection in any file")
    func anchorClearsSelections() {
        let state = DiffInteractionState()
        state.lineNumberClicked(filePath: "a", side: .new, line: 2, extendSelection: false)
        state.openCommentAnchor(anchor("b"))
        #expect(state.activeCommentAnchor?.filePath == "b")
        #expect(state.pendingSelection == nil)

        state.beginTextSelection(textSelection("a"))
        #expect(state.activeCommentAnchor == nil)
        #expect(state.textSelection?.filePath == "a")
    }

    @Test("a text selection in one file clears the line selection in another")
    func textSelectionClearsOtherFile() {
        let state = DiffInteractionState()
        state.lineNumberClicked(filePath: "a", side: .new, line: 2, extendSelection: false)
        state.beginTextSelection(textSelection("b"))
        #expect(state.pendingSelection == nil)
        #expect(state.textSelection?.filePath == "b")
    }

    @Test("a line click clears any text selection and open composer")
    func lineClickClearsTextAndComposer() {
        let state = DiffInteractionState()
        state.beginTextSelection(textSelection("a"))
        state.openCommentAnchor(anchor("a"))
        state.lineNumberClicked(filePath: "a", side: .new, line: 8, extendSelection: false)
        #expect(state.textSelection == nil)
        #expect(state.activeCommentAnchor == nil)
        #expect(state.pendingSelection?.anchorLine == 8)
    }

    @Test("closing the composer discards its draft")
    func closingDiscardsDraft() {
        let state = DiffInteractionState()
        state.openCommentAnchor(anchor("a"))
        state.draftCommentText = "nit"
        state.closeCommentComposer()
        #expect(state.activeCommentAnchor == nil)
        #expect(state.draftCommentText.isEmpty)
    }

    @Test("a draft is kept while its own anchor stays open, and reset for a different anchor")
    func draftFollowsAnchor() {
        let state = DiffInteractionState()
        state.openCommentAnchor(anchor("a", line: 4))
        state.draftCommentText = "nit"
        state.openCommentAnchor(anchor("a", line: 4))
        #expect(state.draftCommentText == "nit")
        state.openCommentAnchor(anchor("a", line: 9))
        #expect(state.draftCommentText.isEmpty)
    }

    @Test("a new diff clears the composer, its draft and both selections")
    func newDiffClearsSelections() {
        let state = DiffInteractionState()
        state.openCommentAnchor(anchor("a"))
        state.draftCommentText = "nit"
        state.clearSelectionsForNewDiff()
        #expect(state.activeCommentAnchor == nil)
        #expect(state.draftCommentText.isEmpty)

        state.lineNumberClicked(filePath: "a", side: .new, line: 2, extendSelection: false)
        state.clearSelectionsForNewDiff()
        #expect(state.pendingSelection == nil)

        state.beginTextSelection(textSelection("a"))
        state.clearSelectionsForNewDiff()
        #expect(state.textSelection == nil)
    }

    @Test("repeated scroll requests for one file still change the request")
    func scrollTokenRises() {
        let state = DiffInteractionState()
        state.requestScroll(to: "a")
        let first = state.scrollRequest
        state.requestScroll(to: "a")
        #expect(state.scrollRequest != first)
        #expect(state.scrollRequest?.token == 2)
        #expect(state.scrollRequest?.filePath == "a")
    }

    @Test("closing search clears the query, matches and open state")
    func closeSearchResets() {
        let state = DiffInteractionState()
        state.openSearch()
        state.searchQuery = "foo"
        state.closeSearch()
        #expect(!state.isSearching)
        #expect(state.searchQuery.isEmpty)
        #expect(state.search.matches.isEmpty)
    }
}
