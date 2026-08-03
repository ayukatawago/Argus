import AppKit
import SwiftUI

/// Two-column diff for a single file: line numbers, added/removed highlighting, per-line "add
/// comment" affordance, multi-line range selection, collapsed-context expansion, and inline
/// comment threads.
struct SideBySideDiffView: View {
    let model: DiffReviewModel
    let file: DiffFile

    @State private var activeCommentAnchor: CommentAnchor?
    @State private var draftCommentText = ""
    @State private var pendingSelection: LineSelection?

    struct CommentAnchor: Equatable {
        let side: ReviewComment.Side
        let startLine: Int
        let endLine: Int
    }

    /// A shift-click-extendable line range, tracked per side, before it's turned into a comment.
    struct LineSelection: Equatable {
        let side: ReviewComment.Side
        let anchorLine: Int
        let focusLine: Int

        var range: ClosedRange<Int> { min(anchorLine, focusLine)...max(anchorLine, focusLine) }
    }

    /// Fixed row height, in points. Every row (including the empty placeholder on the unmatched
    /// side of a row) is pinned to this exact value — an integer at the device's pixel scale — so
    /// adjacent same-color rows' backgrounds tile without the hairline gaps that otherwise appear
    /// when each row's height is left to its font's fractional natural line height.
    private static let rowHeight: CGFloat = 20

    private var language: SyntaxLanguage {
        SyntaxLanguage.detect(fromPath: file.path)
    }

    var body: some View {
        ScrollView {
            if file.isBinaryOrHunkless {
                Text("No line-level changes to display (binary file, rename, or mode-only change).")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(DiffBlockBuilder.blocks(for: file)) { block in
                        blockView(block)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: DiffBlock) -> some View {
        switch block {
        case .hunk(let hunk):
            hunkHeader(hunk)
            ForEach(SideBySideBuilder.rows(for: hunk)) { row in
                rowView(row)
            }

        case .gap(let gap):
            gapView(gap)
        }
    }

    private func hunkHeader(_ hunk: DiffHunk) -> some View {
        Text(hunk.header)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(Color.secondary.opacity(0.08))
    }

    // MARK: - Rows

    @ViewBuilder
    func rowView(_ row: SideBySideRow) -> some View {
        let modification = intralineChanges(for: row)
        HStack(spacing: 0) {
            cell(row: row, line: row.left, side: .old, changedRanges: modification?.old)
            Divider()
            cell(row: row, line: row.right, side: .new, changedRanges: modification?.new)
        }

        if let anchor = activeCommentAnchor, matches(anchor, row: row) {
            commentComposer(anchor: anchor)
        } else if let pendingSelection, isSelectionEnd(row: row, selection: pendingSelection) {
            pendingSelectionToolbar(pendingSelection)
        }

        ForEach(commentsAnchored(to: row)) { comment in
            CommentThreadView(model: model, comment: comment)
        }
    }

    /// A row counts as a "modification" only when it pairs a removed line with its replacement
    /// (as opposed to a standalone added/removed line, or unchanged context) — only then does it
    /// make sense to highlight just the changed span instead of the whole line.
    private func intralineChanges(
        for row: SideBySideRow
    ) -> (old: [Range<String.Index>], new: [Range<String.Index>])? {
        guard let left = row.left, let right = row.right, left.kind == .deletion, right.kind == .addition else {
            return nil
        }
        return IntralineDiff.changedRanges(old: left.text, new: right.text)
    }

    private func matches(_ anchor: CommentAnchor, row: SideBySideRow) -> Bool {
        switch anchor.side {
        case .old: row.left?.oldLineNumber == anchor.endLine
        case .new: row.right?.newLineNumber == anchor.endLine
        }
    }

    private func isSelectionEnd(row: SideBySideRow, selection: LineSelection) -> Bool {
        let number = selection.side == .old ? row.left?.oldLineNumber : row.right?.newLineNumber
        return number == selection.range.upperBound
    }

    private func commentsAnchored(to row: SideBySideRow) -> [ReviewComment] {
        model.comments(for: file.path).filter { comment in
            switch comment.side {
            case .old: row.left?.oldLineNumber == comment.lineNumber
            case .new: row.right?.newLineNumber == comment.lineNumber
            }
        }
    }

    // MARK: - Line selection

    private func handleLineNumberTap(side: ReviewComment.Side, line: Int) {
        activeCommentAnchor = nil
        if NSEvent.modifierFlags.contains(.shift), let existing = pendingSelection, existing.side == side {
            pendingSelection = LineSelection(side: side, anchorLine: existing.anchorLine, focusLine: line)
        } else {
            pendingSelection = LineSelection(side: side, anchorLine: line, focusLine: line)
        }
    }

    @ViewBuilder
    private func pendingSelectionToolbar(_ selection: LineSelection) -> some View {
        HStack(spacing: 8) {
            Button {
                activeCommentAnchor = CommentAnchor(
                    side: selection.side,
                    startLine: selection.range.lowerBound,
                    endLine: selection.range.upperBound
                )
                pendingSelection = nil
            } label: {
                Label(commentButtonTitle(for: selection.range), systemImage: "plus.bubble")
            }
            .buttonStyle(.borderless)

            Button {
                pendingSelection = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)

            Spacer()
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(DiffReviewTheme.selectionBackground)
    }

    private func commentButtonTitle(for range: ClosedRange<Int>) -> String {
        range.lowerBound == range.upperBound
            ? "Comment on line \(range.lowerBound)"
            : "Comment on lines \(range.lowerBound)\u{2013}\(range.upperBound)"
    }

    // MARK: - Cell rendering

    @ViewBuilder
    private func cell(
        row: SideBySideRow,
        line: DiffLine?,
        side: ReviewComment.Side,
        changedRanges: [Range<String.Index>]?
    ) -> some View {
        HStack(spacing: 6) {
            if let line {
                let number = side == .old ? line.oldLineNumber : line.newLineNumber
                Text(number.map(String.init) ?? "")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(DiffReviewTheme.lineNumberForeground)
                    .frame(width: 36, alignment: .trailing)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let number { handleLineNumberTap(side: side, line: number) }
                    }

                Button {
                    if let number {
                        activeCommentAnchor = CommentAnchor(side: side, startLine: number, endLine: number)
                        pendingSelection = nil
                    }
                } label: {
                    Image(systemName: "plus.bubble")
                }
                .buttonStyle(.borderless)
                .opacity(0.35)
                .frame(width: 14)

                Text(highlightedText(line, changedRanges: changedRanges))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(DiffReviewTheme.contextForeground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            } else {
                Color.clear
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, minHeight: Self.rowHeight, maxHeight: Self.rowHeight, alignment: .leading)
        .background(rowBackground(line: line, side: side, changedRanges: changedRanges))
    }

    private func highlightedText(_ line: DiffLine, changedRanges: [Range<String.Index>]?) -> AttributedString {
        guard !line.text.isEmpty else { return AttributedString(" ") }
        var attributed = SyntaxHighlighter.highlight(line.text, language: language)
        guard let changedRanges, !changedRanges.isEmpty else { return attributed }
        let emphasis = emphasisBackground(for: line.kind)
        for range in changedRanges {
            guard let attributedRange = Range(range, in: attributed) else { continue }
            attributed[attributedRange].backgroundColor = emphasis
        }
        return attributed
    }

    /// A modified line (changedRanges != nil) shows no whole-line tint — only the changed span,
    /// via a backgroundColor run inside highlightedText — so unchanged text on that line reads
    /// normally instead of implying the entire line is new/removed. Pending-selection and
    /// existing-comment-range tints take priority over the plain addition/deletion tint since
    /// they're both rarer and more important for the reviewer to notice.
    private func rowBackground(
        line: DiffLine?,
        side: ReviewComment.Side,
        changedRanges: [Range<String.Index>]?
    ) -> Color {
        let number = side == .old ? line?.oldLineNumber : line?.newLineNumber
        if let number, let pendingSelection, pendingSelection.side == side, pendingSelection.range.contains(number) {
            return DiffReviewTheme.selectionBackground
        }
        if let number, isWithinExistingCommentRange(line: number, side: side) {
            return DiffReviewTheme.commentRangeBackground
        }
        return changedRanges == nil ? background(for: line?.kind) : .clear
    }

    private func isWithinExistingCommentRange(line number: Int, side: ReviewComment.Side) -> Bool {
        model.comments(for: file.path).contains { comment in
            guard comment.side == side else { return false }
            let range = (comment.startLineNumber ?? comment.lineNumber)...comment.lineNumber
            return range.contains(number)
        }
    }

    private func background(for kind: DiffLine.Kind?) -> Color {
        switch kind {
        case .addition: DiffReviewTheme.additionBackground
        case .deletion: DiffReviewTheme.deletionBackground
        default: .clear
        }
    }

    private func emphasisBackground(for kind: DiffLine.Kind) -> Color {
        switch kind {
        case .addition: DiffReviewTheme.additionEmphasisBackground
        case .deletion: DiffReviewTheme.deletionEmphasisBackground
        case .context: .clear
        }
    }

    // MARK: - Comment composer

    @ViewBuilder
    private func commentComposer(anchor: CommentAnchor) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if anchor.startLine != anchor.endLine {
                Text("Commenting on lines \(anchor.startLine)\u{2013}\(anchor.endLine)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $draftCommentText)
                .frame(height: 60)
                .font(.system(.body, design: .monospaced))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))

            HStack {
                Spacer()
                Button("Cancel") {
                    activeCommentAnchor = nil
                    draftCommentText = ""
                }
                Button("Comment") {
                    model.addComment(
                        filePath: file.path,
                        side: anchor.side,
                        startLineNumber: anchor.startLine == anchor.endLine ? nil : anchor.startLine,
                        lineNumber: anchor.endLine,
                        body: draftCommentText
                    )
                    activeCommentAnchor = nil
                    draftCommentText = ""
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(draftCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06))
    }
}
