import AppKit
import SwiftUI

/// Identifies one rendered code cell: a line number on one side of one file's diff.
struct CodeCellKey: Hashable {
    let filePath: String
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

/// A text-editor-style selection within one side of one file's diff, from mid-line to mid-line.
struct TextSelectionRange: Equatable {
    let filePath: String
    let side: ReviewComment.Side
    let anchor: TextPosition
    let focus: TextPosition

    var start: TextPosition { min(anchor, focus) }
    var end: TextPosition { max(anchor, focus) }
}

extension DiffFileListView {
    /// Width of one monospaced character in the diff's code font.
    private static let characterWidth: CGFloat = {
        let size = NSFont.preferredFont(forTextStyle: .body).pointSize
        let font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        return ("M" as NSString).size(withAttributes: [.font: font]).width
    }()

    /// Reports the cell's frame, in the list's coordinate space, under its file, side and line.
    static func codeFrameReader(filePath: String, side: ReviewComment.Side, number: Int?) -> some View {
        GeometryReader { geometry in
            Color.clear.preference(
                key: CodeCellFramesKey.self,
                value: number.map {
                    [CodeCellKey(filePath: filePath, side: side, line: $0): geometry.frame(in: .named(rowSpace))]
                } ?? [:]
            )
        }
    }

    /// Click-and-drag selects text like an editor. A drag only starts on a code cell, so one that begins
    /// on a comment card, a header, an expander or empty space leaves the open composer alone. The drag
    /// belongs to the file under its start point, and its side is fixed by which half of that file's rows
    /// it starts in. The end lands on the nearest character in the nearest line, so a drag can't leave
    /// the file it began in.
    var dragSelectGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.rowSpace))
            .onChanged { value in updateDragSelection(from: value.startLocation, to: value.location) }
    }

    private func updateDragSelection(from start: CGPoint, to end: CGPoint) {
        let frames = interaction.cellFrames.frames
        guard let startCell = frames.first(where: { $0.value.contains(start) }) else { return }
        let filePath = startCell.key.filePath
        let side = Self.side(atX: start.x, filePath: filePath, frames: frames)
        let texts = layout(forPath: filePath)?.lineTexts[side] ?? [:]
        guard let anchor = Self.position(at: start, filePath: filePath, side: side, texts: texts, frames: frames),
            let focus = Self.position(at: end, filePath: filePath, side: side, texts: texts, frames: frames)
        else { return }
        interaction.beginTextSelection(
            TextSelectionRange(filePath: filePath, side: side, anchor: anchor, focus: focus)
        )
    }

    /// A single click clears the text selection; a double-click selects the word under the pointer.
    var tapSelectGesture: some Gesture {
        SpatialTapGesture(coordinateSpace: .named(Self.rowSpace)).onEnded { value in
            if NSApp.currentEvent?.clickCount == 2 {
                selectWord(at: value.location)
            } else {
                interaction.clearTextSelection()
            }
        }
    }

    /// Double-click selects the word (run of letters, digits and underscores) under `point`, or the run
    /// of punctuation if the click lands on a non-word character.
    func selectWord(at point: CGPoint) {
        let frames = interaction.cellFrames.frames
        guard let hit = frames.first(where: { $0.value.contains(point) }) else { return }
        let filePath = hit.key.filePath
        let side = Self.side(atX: point.x, filePath: filePath, frames: frames)
        guard
            let click = frames.first(where: {
                $0.key.filePath == filePath && $0.key.side == side && $0.value.contains(point)
            }),
            let text = layout(forPath: filePath)?.lineTexts[side]?[click.key.line], !text.isEmpty
        else { return }
        let characters = Array(text)
        let offset = Int(((point.x - click.value.minX) / Self.characterWidth).rounded(.down))
        guard let bounds = Self.wordBounds(in: characters, at: offset) else { return }
        interaction.beginTextSelection(
            TextSelectionRange(
                filePath: filePath,
                side: side,
                anchor: TextPosition(line: click.key.line, column: bounds.lowerBound),
                focus: TextPosition(line: click.key.line, column: bounds.upperBound)
            )
        )
    }

    /// The half-open run of characters that share the class of the character at `offset`: a word, a run
    /// of whitespace, or a run of punctuation. `nil` when `offset` is outside the line.
    static func wordBounds(in characters: [Character], at offset: Int) -> Range<Int>? {
        guard characters.indices.contains(offset) else { return nil }
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
        return lower..<upper
    }

    private static func side(atX xPos: CGFloat, filePath: String, frames: [CodeCellKey: CGRect]) -> ReviewComment.Side {
        let cells = frames.filter { $0.key.filePath == filePath }
        let oldRight = cells.filter { $0.key.side == .old }.map(\.value.maxX).max()
        let newLeft = cells.filter { $0.key.side == .new }.map(\.value.minX).min()
        switch (oldRight, newLeft) {
        case (let oldRight?, _): return xPos <= oldRight ? .old : .new
        case (nil, let newLeft?): return xPos < newLeft ? .old : .new
        default: return .new
        }
    }

    /// The character position nearest `point` on `side` of one file, clamping to the first/last line and
    /// to the line's length so dragging past an edge selects through to it.
    private static func position(
        at point: CGPoint,
        filePath: String,
        side: ReviewComment.Side,
        texts: [Int: String],
        frames: [CodeCellKey: CGRect]
    ) -> TextPosition? {
        let candidates = frames.filter { $0.key.filePath == filePath && $0.key.side == side }
        guard
            let nearest = candidates.min(by: {
                distance(from: point.y, to: $0.value) < distance(from: point.y, to: $1.value)
            })
        else { return nil }
        let length = texts[nearest.key.line]?.count ?? 0
        let offset = ((point.x - nearest.value.minX) / characterWidth).rounded()
        return TextPosition(line: nearest.key.line, column: max(0, min(length, Int(offset))))
    }

    private static func distance(from yPos: CGFloat, to frame: CGRect) -> CGFloat {
        yPos < frame.minY ? frame.minY - yPos : (yPos > frame.maxY ? yPos - frame.maxY : 0)
    }
}
