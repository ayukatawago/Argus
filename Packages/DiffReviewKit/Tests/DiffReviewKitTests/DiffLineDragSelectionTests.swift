import CoreGraphics
import Testing

@testable import DiffReviewKit

@Suite("DiffFileListView gutter drag")
@MainActor
struct GutterDragSelectionTests {
    /// Line 1 spans y 0–20, line 2 spans 20–40, and line 3 spans 60–80 (a gap of 40–60 between them).
    private let line1 = CGRect(x: 0, y: 0, width: 100, height: 20)
    private let line2 = CGRect(x: 0, y: 20, width: 100, height: 20)
    private let line3 = CGRect(x: 0, y: 60, width: 100, height: 20)

    private var frames: [Int: CGRect] { [1: line1, 2: line2, 3: line3] }

    @Test("the nearest line is the one containing the pointer")
    func containingLine() {
        #expect(DiffFileListView.nearestLine(toY: 5, frames: frames) == 1)
        #expect(DiffFileListView.nearestLine(toY: 30, frames: frames) == 2)
        #expect(DiffFileListView.nearestLine(toY: 70, frames: frames) == 3)
    }

    @Test("positions above or below every line clamp to the first or last line")
    func clampsToEdges() {
        #expect(DiffFileListView.nearestLine(toY: -500, frames: frames) == 1)
        #expect(DiffFileListView.nearestLine(toY: 900, frames: frames) == 3)
    }

    @Test("between two lines the nearer one wins, and an exact tie goes to the upper one")
    func betweenLines() {
        #expect(DiffFileListView.nearestLine(toY: 45, frames: frames) == 2)
        #expect(DiffFileListView.nearestLine(toY: 55, frames: frames) == 3)
        #expect(DiffFileListView.nearestLine(toY: 50, frames: frames) == 2)
    }

    @Test("no lines gives no nearest line")
    func noLines() {
        #expect(DiffFileListView.nearestLine(toY: 10, frames: [:]) == nil)
    }

    @Test("a drag from a gutter spans the start line to the nearest line on its file and side")
    func rangeFromGutter() {
        let origin = CodeCellKey(filePath: "a.swift", side: .new, line: 2)
        let all: [CodeCellKey: CGRect] = [
            CodeCellKey(filePath: "a.swift", side: .new, line: 1): line1,
            CodeCellKey(filePath: "a.swift", side: .new, line: 2): line2,
            CodeCellKey(filePath: "a.swift", side: .new, line: 3): line3,
        ]
        let selection = DiffFileListView.lineDragSelection(from: origin, toY: 75, frames: all)
        #expect(selection.filePath == "a.swift")
        #expect(selection.side == .new)
        #expect(selection.anchorLine == 2)
        #expect(selection.focusLine == 3)
        #expect(selection.range == 2...3)
    }

    @Test("a drag that leaves the file or side keeps its starting file and side")
    func fixedToStartingFileAndSide() {
        let origin = CodeCellKey(filePath: "a.swift", side: .new, line: 2)
        let all: [CodeCellKey: CGRect] = [
            CodeCellKey(filePath: "a.swift", side: .new, line: 2): line2,
            // Same y as the pointer, but another side and another file.
            CodeCellKey(filePath: "a.swift", side: .old, line: 9): CGRect(x: 0, y: 500, width: 100, height: 20),
            CodeCellKey(filePath: "b.swift", side: .new, line: 7): CGRect(x: 0, y: 500, width: 100, height: 20),
        ]
        let selection = DiffFileListView.lineDragSelection(from: origin, toY: 510, frames: all)
        #expect(selection.filePath == "a.swift")
        #expect(selection.side == .new)
        #expect(selection.anchorLine == 2)
        #expect(selection.focusLine == 2)
    }

    @Test("a drag with no other line on its side stays on the starting line")
    func noOtherLine() {
        let origin = CodeCellKey(filePath: "a.swift", side: .old, line: 4)
        let selection = DiffFileListView.lineDragSelection(from: origin, toY: 300, frames: [:])
        #expect(selection.anchorLine == 4)
        #expect(selection.focusLine == 4)
    }
}

@Suite("DiffInteractionState line drag exclusivity")
@MainActor
struct LineDragExclusivityTests {
    @Test("a line-range drag clears the open composer and any text selection")
    func clearsOthers() {
        let interaction = DiffInteractionState()
        interaction.beginTextSelection(
            TextSelectionRange(
                filePath: "a",
                side: .new,
                anchor: TextPosition(line: 1, column: 0),
                focus: TextPosition(line: 1, column: 2)
            )
        )
        interaction.openCommentAnchor(DiffCommentAnchor(filePath: "a", side: .new, startLine: 1, endLine: 1))
        interaction.beginLineSelection(DiffLineSelection(filePath: "a", side: .new, anchorLine: 1, focusLine: 3))

        #expect(interaction.pendingSelection?.range == 1...3)
        #expect(interaction.activeCommentAnchor == nil)
        #expect(interaction.textSelection == nil)
    }

    @Test("starting a text selection still clears a line-range selection")
    func textSelectionClearsLineRange() {
        let interaction = DiffInteractionState()
        interaction.beginLineSelection(DiffLineSelection(filePath: "a", side: .new, anchorLine: 1, focusLine: 3))
        interaction.beginTextSelection(
            TextSelectionRange(
                filePath: "a",
                side: .new,
                anchor: TextPosition(line: 5, column: 0),
                focus: TextPosition(line: 5, column: 1)
            )
        )
        #expect(interaction.pendingSelection == nil)
        #expect(interaction.textSelection != nil)
    }
}
