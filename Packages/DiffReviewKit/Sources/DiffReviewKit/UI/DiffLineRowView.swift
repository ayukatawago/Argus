import AppKit
import SwiftUI

/// One side-by-side row of a file's diff: both code cells, the pending-selection toolbar, and the
/// composer and comment cards, each under the side it belongs to. Hover is local `@State`, so a mouse
/// move re-renders only this row.
struct DiffLineRowView: View {
    static let rowHeight: CGFloat = 20

    let row: SideBySideRow
    let file: DiffFile
    let layout: DiffFileLayout
    let model: DiffReviewModel
    @Bindable var interaction: DiffInteractionState

    @State private var hoveredSide: ReviewComment.Side?

    private var ref: RowRef { RowRef(filePath: file.path, rowID: row.id) }

    private var language: SyntaxLanguage {
        SyntaxLanguage.detect(fromPath: file.path)
    }

    var body: some View {
        VStack(spacing: 0) {
            rangeLabel

            HStack(spacing: 0) {
                cell(.old, line: row.left)
                Divider()
                cell(.new, line: row.right)
            }
            .overlay {
                if interaction.isSearching, interaction.search.isCurrent(ref) {
                    Rectangle().stroke(DiffReviewTheme.searchCurrentMatchBorder, lineWidth: 1.5).allowsHitTesting(false)
                }
            }

            if let selection = pendingSelectionEnding {
                pendingSelectionToolbar(selection)
            }

            attachments
        }
    }

    // MARK: - Cells

    @ViewBuilder
    private func cell(_ side: ReviewComment.Side, line: DiffLine?) -> some View {
        let number = line.flatMap { side == .old ? $0.oldLineNumber : $0.newLineNumber }
        let spans = layout.intraline[row.id].map { side == .old ? $0.old : $0.new }
        HStack(spacing: 0) {
            gutter(line: line, number: number, side: side)

            if let line {
                Text(Self.marker(for: line.kind))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Self.markerForeground(for: line.kind))
                    .frame(width: 14)
                    .frame(maxHeight: .infinity)

                Text(highlightedText(line, side: side, number: number, spans: spans))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(DiffReviewTheme.contextForeground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DiffFileListView.codeFrameReader(filePath: file.path, side: side, number: number))
                    .padding(.leading, 2)
                    .padding(.trailing, 4)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, minHeight: Self.rowHeight, maxHeight: Self.rowHeight, alignment: .leading)
        .background(codeBackground(line: line, side: side))
        .onHover { hovering in
            if hovering {
                hoveredSide = side
            } else if hoveredSide == side {
                hoveredSide = nil
            }
        }
    }

    /// The line-number gutter: the blue "+" button on hover, the number, its own per-kind tint, and a
    /// hairline on its trailing edge.
    private func gutter(line: DiffLine?, number: Int?, side: ReviewComment.Side) -> some View {
        HStack(spacing: 0) {
            if line != nil {
                Button {
                    if let number {
                        interaction.openCommentAnchor(
                            DiffCommentAnchor(filePath: file.path, side: side, startLine: number, endLine: number)
                        )
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(DiffReviewTheme.addCommentForeground)
                        .frame(width: 14, height: 14)
                        .background(DiffReviewTheme.addCommentBackground, in: RoundedRectangle(cornerRadius: 3))
                }
                .buttonStyle(.plain)
                .opacity(hoveredSide == side ? 1 : 0)
                .allowsHitTesting(hoveredSide == side)
                .frame(width: 18)
            } else {
                Color.clear.frame(width: 18)
            }
            lineNumberView(number, side: side)
        }
        .padding(.trailing, 4)
        .frame(maxHeight: .infinity)
        .background(gutterBackground(line: line, side: side))
        .overlay {
            if let tint = selectionTint(line: line, side: side) {
                tint.allowsHitTesting(false)
            }
        }
        .overlay(alignment: .trailing) {
            Rectangle().fill(DiffReviewTheme.border).frame(width: 1)
        }
    }

    private func lineNumberView(_ number: Int?, side: ReviewComment.Side) -> some View {
        Text(number.map(String.init) ?? "")
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(DiffReviewTheme.lineNumberForeground)
            .frame(width: 36, alignment: .trailing)
            .textSelection(.disabled)
            .background(DiffFileListView.gutterFrameReader(filePath: file.path, side: side, number: number))
            .contentShape(Rectangle())
            .onTapGesture {
                if let number {
                    interaction.lineNumberClicked(
                        filePath: file.path,
                        side: side,
                        line: number,
                        extendSelection: NSEvent.modifierFlags.contains(.shift)
                    )
                }
            }
    }

    /// Selection and existing-comment tints, which take priority over the line's own kind tint.
    private func selectionTint(line: DiffLine?, side: ReviewComment.Side) -> Color? {
        let number = side == .old ? line?.oldLineNumber : line?.newLineNumber
        if let number, let pending = interaction.pendingSelection, pending.filePath == file.path,
            pending.side == side, pending.range.contains(number)
        {
            return DiffReviewTheme.selectionBackground
        }
        if let number, isWithinExistingCommentRange(line: number, side: side) {
            return DiffReviewTheme.commentRangeBackground
        }
        return nil
    }

    /// A modified line keeps its whole-line kind tint; the darker emphasis is layered over its changed
    /// spans in `highlightedText`.
    private func codeBackground(line: DiffLine?, side: ReviewComment.Side) -> Color {
        selectionTint(line: line, side: side) ?? Self.background(for: line?.kind)
    }

    private func gutterBackground(line: DiffLine?, side: ReviewComment.Side) -> Color {
        switch line?.kind {
        case .addition: DiffReviewTheme.additionGutterBackground
        case .deletion: DiffReviewTheme.deletionGutterBackground
        case .context, nil: DiffReviewTheme.contextGutterBackground
        }
    }

    private static func marker(for kind: DiffLine.Kind) -> String {
        switch kind {
        case .addition: "+"
        case .deletion: "\u{2212}"
        case .context: " "
        }
    }

    private static func markerForeground(for kind: DiffLine.Kind) -> Color {
        switch kind {
        case .addition: DiffReviewTheme.additionForeground
        case .deletion: DiffReviewTheme.deletionForeground
        case .context: DiffReviewTheme.lineNumberForeground
        }
    }

    private static func background(for kind: DiffLine.Kind?) -> Color {
        switch kind {
        case .addition: DiffReviewTheme.additionBackground
        case .deletion: DiffReviewTheme.deletionBackground
        default: .clear
        }
    }

    private static func emphasisBackground(for kind: DiffLine.Kind) -> Color {
        switch kind {
        case .addition: DiffReviewTheme.additionEmphasisBackground
        case .deletion: DiffReviewTheme.deletionEmphasisBackground
        case .context: .clear
        }
    }

    private func isWithinExistingCommentRange(line number: Int, side: ReviewComment.Side) -> Bool {
        model.comments(for: file.path).contains { comment in
            guard comment.side == side else { return false }
            return ((comment.startLineNumber ?? comment.lineNumber)...comment.lineNumber).contains(number)
        }
    }

    // MARK: - Highlighting

    private func highlightedText(
        _ line: DiffLine,
        side: ReviewComment.Side,
        number: Int?,
        spans: [Range<String.Index>]?
    ) -> AttributedString {
        guard !line.text.isEmpty else { return AttributedString(" ") }
        var attributed = SyntaxHighlighter.highlight(line.text, language: language)
        highlightSearchMatches(in: &attributed)
        if let spans, !spans.isEmpty {
            let emphasis = Self.emphasisBackground(for: line.kind)
            for range in spans {
                guard let attributedRange = Range(range, in: attributed) else { continue }
                attributed[attributedRange].backgroundColor = emphasis
            }
        }
        if let number { highlightTextSelection(in: &attributed, line: line, side: side, number: number) }
        return attributed
    }

    private func highlightSearchMatches(in attributed: inout AttributedString) {
        guard interaction.isSearching, interaction.search.contains(ref) else { return }
        let query = interaction.searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        var searchStart = attributed.startIndex
        while searchStart < attributed.endIndex,
            let found = attributed[searchStart...].range(of: query, options: .caseInsensitive)
        {
            attributed[found].backgroundColor = DiffReviewTheme.searchMatchBackground
            searchStart = found.upperBound
        }
    }

    /// Paints the part of `line` covered by the drag text selection, if that selection is in this file.
    private func highlightTextSelection(
        in attributed: inout AttributedString, line: DiffLine, side: ReviewComment.Side, number: Int
    ) {
        guard let selection = interaction.textSelection, selection.filePath == file.path, selection.side == side,
            (selection.start.line...selection.end.line).contains(number)
        else { return }
        let count = line.text.count
        let from = number == selection.start.line ? min(selection.start.column, count) : 0
        let upTo = number == selection.end.line ? min(selection.end.column, count) : count
        guard from < upTo else { return }
        let characters = attributed.characters
        let lower = characters.index(characters.startIndex, offsetBy: from)
        let upper = characters.index(characters.startIndex, offsetBy: upTo)
        attributed[lower..<upper].backgroundColor = DiffReviewTheme.textSelectionBackground
    }
}
