import AppKit
import SwiftUI

/// Identifies one rendered code cell: a line number on one side of the diff.
struct CodeCellKey: Hashable {
    let side: ReviewComment.Side
    let line: Int
}

struct CodeCellFramesKey: PreferenceKey {
    static let defaultValue: [CodeCellKey: CGRect] = [:]

    static func reduce(value: inout [CodeCellKey: CGRect], nextValue: () -> [CodeCellKey: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// A character-level position: a line number on one side plus a column (character offset) into it.
struct TextPosition: Comparable {
    let line: Int
    let column: Int

    static func < (lhs: TextPosition, rhs: TextPosition) -> Bool {
        (lhs.line, lhs.column) < (rhs.line, rhs.column)
    }
}

/// A text-editor-style selection within one side of the diff, from mid-line to mid-line.
struct TextSelectionRange: Equatable {
    let side: ReviewComment.Side
    let anchor: TextPosition
    let focus: TextPosition

    var start: TextPosition { min(anchor, focus) }
    var end: TextPosition { max(anchor, focus) }
}

extension SideBySideDiffView {
    static let rowSpace = "diffRows"

    /// Width of one monospaced character in the diff's code font.
    private static let characterWidth: CGFloat = {
        let size = NSFont.preferredFont(forTextStyle: .body).pointSize
        let font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        return ("M" as NSString).size(withAttributes: [.font: font]).width
    }()

    func codeFrameReader(side: ReviewComment.Side, number: Int?) -> some View {
        GeometryReader { geometry in
            Color.clear.preference(
                key: CodeCellFramesKey.self,
                value: number.map { [CodeCellKey(side: side, line: $0): geometry.frame(in: .named(Self.rowSpace))] }
                    ?? [:]
            )
        }
    }

    /// Click-and-drag selects text like an editor: the side is fixed by where the drag begins (left
    /// half = old, right half = new), and start/end land on the nearest character in the nearest line.
    var dragSelectGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.rowSpace))
            .onChanged { value in updateDragSelection(from: value.startLocation, to: value.location) }
    }

    private func updateDragSelection(from start: CGPoint, to end: CGPoint) {
        let side = side(atX: start.x)
        let texts = lineTexts(side: side)
        guard let anchor = position(at: start, side: side, texts: texts),
            let focus = position(at: end, side: side, texts: texts)
        else { return }
        activeCommentAnchor = nil
        pendingSelection = nil
        textSelection = TextSelectionRange(side: side, anchor: anchor, focus: focus)
    }

    /// A single click clears the text selection; a double-click selects the word under the pointer.
    var tapSelectGesture: some Gesture {
        SpatialTapGesture(coordinateSpace: .named(Self.rowSpace)).onEnded { value in
            if NSApp.currentEvent?.clickCount == 2 {
                selectWord(at: value.location)
            } else {
                textSelection = nil
            }
        }
    }

    /// Double-click selects the word (run of letters, digits and underscores) under `point`, or the
    /// run of punctuation if the click lands on a non-word character.
    func selectWord(at point: CGPoint) {
        let side = side(atX: point.x)
        let texts = lineTexts(side: side)
        guard let click = cellFrames.first(where: { $0.key.side == side && $0.value.contains(point) }),
            let text = texts[click.key.line], !text.isEmpty
        else { return }
        let characters = Array(text)
        let offset = Int(((point.x - click.value.minX) / Self.characterWidth).rounded(.down))
        guard characters.indices.contains(offset) else { return }
        func isWord(_ character: Character) -> Bool { character.isLetter || character.isNumber || character == "_" }
        let target = characters[offset]
        let matches: (Character) -> Bool =
            target.isWhitespace
            ? { $0.isWhitespace }
            : (isWord(target) ? isWord : { !isWord($0) && !$0.isWhitespace })
        var lower = offset
        var upper = offset + 1
        while lower > 0, matches(characters[lower - 1]) { lower -= 1 }
        while upper < characters.count, matches(characters[upper]) { upper += 1 }
        activeCommentAnchor = nil
        pendingSelection = nil
        textSelection = TextSelectionRange(
            side: side,
            anchor: TextPosition(line: click.key.line, column: lower),
            focus: TextPosition(line: click.key.line, column: upper))
    }

    private func side(atX xPos: CGFloat) -> ReviewComment.Side {
        let oldRight = cellFrames.filter { $0.key.side == .old }.map(\.value.maxX).max()
        let newLeft = cellFrames.filter { $0.key.side == .new }.map(\.value.minX).min()
        switch (oldRight, newLeft) {
        case (let oldRight?, _): return xPos <= oldRight ? .old : .new
        case (nil, let newLeft?): return xPos < newLeft ? .old : .new
        default: return .new
        }
    }

    /// The character position nearest `point` on `side`, clamping to the first/last line and to the
    /// line's length so dragging past an edge selects through to it.
    private func position(at point: CGPoint, side: ReviewComment.Side, texts: [Int: String]) -> TextPosition? {
        let candidates = cellFrames.filter { $0.key.side == side }
        guard
            let nearest = candidates.min(by: {
                distance(from: point.y, to: $0.value) < distance(from: point.y, to: $1.value)
            })
        else { return nil }
        let length = texts[nearest.key.line]?.count ?? 0
        let offset = ((point.x - nearest.value.minX) / Self.characterWidth).rounded()
        return TextPosition(line: nearest.key.line, column: max(0, min(length, Int(offset))))
    }

    private func distance(from yPos: CGFloat, to frame: CGRect) -> CGFloat {
        yPos < frame.minY ? frame.minY - yPos : (yPos > frame.maxY ? yPos - frame.maxY : 0)
    }

    /// Line number -> text for one side, across all hunks.
    func lineTexts(side: ReviewComment.Side) -> [Int: String] {
        var texts: [Int: String] = [:]
        for case .hunk(let hunk) in DiffBlockBuilder.blocks(for: file) {
            for row in SideBySideBuilder.rows(for: hunk) {
                let line = side == .old ? row.left : row.right
                if let line, let number = side == .old ? line.oldLineNumber : line.newLineNumber {
                    texts[number] = line.text
                }
            }
        }
        return texts
    }

    /// Paints the part of `line` covered by the current text selection, if any.
    func highlightTextSelection(
        in attributed: inout AttributedString, line: DiffLine, side: ReviewComment.Side, number: Int
    ) {
        guard let selection = textSelection, selection.side == side,
            (selection.start.line...selection.end.line).contains(number)
        else { return }
        let count = line.text.count
        let from = number == selection.start.line ? min(selection.start.column, count) : 0
        let upTo = number == selection.end.line ? min(selection.end.column, count) : count
        guard from < upTo else { return }
        let characters = attributed.characters
        let lower = characters.index(characters.startIndex, offsetBy: from)
        let upper = characters.index(characters.startIndex, offsetBy: upTo)
        attributed[lower..<upper].backgroundColor = Color(nsColor: .selectedTextBackgroundColor)
    }
}
