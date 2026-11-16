import Foundation
import Observation

/// A comment composer's anchor: the file, the side, and the line range it covers.
struct DiffCommentAnchor: Equatable {
    let filePath: String
    let side: ReviewComment.Side
    let startLine: Int
    let endLine: Int
}

/// A shift-click-extendable line range on one side of one file, before it becomes a comment.
struct DiffLineSelection: Equatable {
    let filePath: String
    let side: ReviewComment.Side
    let anchorLine: Int
    let focusLine: Int

    var range: ClosedRange<Int> { min(anchorLine, focusLine)...max(anchorLine, focusLine) }

    /// The selection a line-number click leaves behind. Shift extends from the existing anchor only when
    /// that anchor is in the same file and on the same side; anything else starts a new selection.
    static func clicked(
        filePath: String,
        side: ReviewComment.Side,
        line: Int,
        extending existing: DiffLineSelection?,
        shift: Bool
    ) -> DiffLineSelection {
        guard shift, let existing, existing.filePath == filePath, existing.side == side else {
            return DiffLineSelection(filePath: filePath, side: side, anchorLine: line, focusLine: line)
        }
        return DiffLineSelection(filePath: filePath, side: side, anchorLine: existing.anchorLine, focusLine: line)
    }
}

/// A request to scroll the list to a file's header. The token rises on every request, so asking for the
/// same file twice still counts as a change.
struct DiffScrollRequest: Equatable {
    let filePath: String
    let token: Int
}

/// Which matches exist and which one is current. Pure, so stepping and clamping are testable.
struct DiffSearchState: Equatable {
    private(set) var matches: [RowRef] = []
    private(set) var matchSet: Set<RowRef> = []
    private(set) var currentIndex = 0

    var currentMatch: RowRef? {
        matches.indices.contains(currentIndex) ? matches[currentIndex] : nil
    }

    func contains(_ ref: RowRef) -> Bool {
        matchSet.contains(ref)
    }

    func isCurrent(_ ref: RowRef) -> Bool {
        currentMatch == ref
    }

    /// Replaces the match list. The current match stays current if its row is still a match (a gap
    /// expansion shifts indices but not row ids); otherwise the index is clamped into range.
    mutating func replaceMatches(_ newMatches: [RowRef]) {
        let previous = currentMatch
        matches = newMatches
        matchSet = Set(newMatches)
        if let previous, let index = newMatches.firstIndex(of: previous) {
            currentIndex = index
        } else {
            currentIndex = min(currentIndex, max(0, matches.count - 1))
        }
    }

    /// Forgets the current match, so the next `replaceMatches` starts again from the first match.
    mutating func resetCurrent() {
        matches = []
        matchSet = []
        currentIndex = 0
    }

    /// Moves the current match by `delta`, wrapping at both ends, and returns the new current match.
    @discardableResult
    mutating func step(_ delta: Int) -> RowRef? {
        guard !matches.isEmpty else { return nil }
        let count = matches.count
        currentIndex = ((currentIndex + delta) % count + count) % count
        return currentMatch
    }
}

/// Holds the code cell and line-number gutter frames used to hit-test drags and double-clicks. A reference
/// box that is not observed: writing it from a preference change must not re-render the list.
@MainActor
final class DiffCellFrames {
    var frames: [CodeCellKey: CGRect] = [:]
    var gutterFrames: [CodeCellKey: CGRect] = [:]
}

/// Interaction state for the whole diff list: the open composer, the pending line selection, the drag
/// text selection, search, and the scroll request. Every selection carries its file path, and starting
/// one anywhere clears the others. Row views read this; the list body must not.
@MainActor
@Observable
final class DiffInteractionState {
    private(set) var activeCommentAnchor: DiffCommentAnchor?
    private(set) var pendingSelection: DiffLineSelection?
    private(set) var textSelection: TextSelectionRange?
    var draftCommentText = ""

    private(set) var scrollRequest: DiffScrollRequest?
    @ObservationIgnored private var scrollToken = 0

    var isSearching = false
    var searchQuery = ""
    private(set) var search = DiffSearchState()
    private(set) var searchFocusToken = 0

    @ObservationIgnored let cellFrames = DiffCellFrames()

    // MARK: - Selection and composer (each clears the others)

    func openCommentAnchor(_ anchor: DiffCommentAnchor) {
        // A draft belongs to the line it was typed on; opening a different anchor starts an empty one.
        if activeCommentAnchor != anchor {
            draftCommentText = ""
        }
        activeCommentAnchor = anchor
        pendingSelection = nil
        textSelection = nil
    }

    /// Closes the composer and discards its draft.
    func closeCommentComposer() {
        activeCommentAnchor = nil
        draftCommentText = ""
    }

    /// Drops every selection and the composer. Called when the diff is replaced, since their line
    /// numbers and column offsets then refer to text that may no longer be on screen.
    func clearSelectionsForNewDiff() {
        closeCommentComposer()
        pendingSelection = nil
        textSelection = nil
    }

    func lineNumberClicked(filePath: String, side: ReviewComment.Side, line: Int, extendSelection: Bool) {
        pendingSelection = DiffLineSelection.clicked(
            filePath: filePath,
            side: side,
            line: line,
            extending: pendingSelection,
            shift: extendSelection
        )
        activeCommentAnchor = nil
        textSelection = nil
    }

    /// A drag from a line-number gutter selects a line range. Like a click, it clears the composer and any
    /// text selection.
    func beginLineSelection(_ selection: DiffLineSelection) {
        pendingSelection = selection
        activeCommentAnchor = nil
        textSelection = nil
    }

    func dismissLineSelection() {
        pendingSelection = nil
    }

    func beginTextSelection(_ selection: TextSelectionRange) {
        textSelection = selection
        activeCommentAnchor = nil
        pendingSelection = nil
    }

    func clearTextSelection() {
        textSelection = nil
    }

    // MARK: - Scrolling

    func requestScroll(to filePath: String) {
        scrollToken += 1
        scrollRequest = DiffScrollRequest(filePath: filePath, token: scrollToken)
    }

    // MARK: - Search

    func openSearch() {
        isSearching = true
        searchFocusToken += 1
    }

    func closeSearch() {
        isSearching = false
        searchQuery = ""
        search = DiffSearchState()
    }

    /// Recomputes the match list. Called once per query change and once per layout revision, never per row.
    func refreshSearchMatches(sections: [DiffRowSection]) {
        guard isSearching else { return }
        search.replaceMatches(DiffSearch.matches(query: searchQuery, sections: sections))
    }

    /// A new query starts again from its first match. Returns that match, to scroll to.
    func searchQueryChanged(sections: [DiffRowSection]) -> RowRef? {
        search.resetCurrent()
        refreshSearchMatches(sections: sections)
        return search.currentMatch
    }

    func stepSearch(_ delta: Int) -> RowRef? {
        search.step(delta)
    }
}
