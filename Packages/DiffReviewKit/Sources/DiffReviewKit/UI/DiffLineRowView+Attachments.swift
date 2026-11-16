import AppKit
import SwiftUI

/// The selection toolbar under a pending line selection, and the comment composer and cards anchored to a row.
extension DiffLineRowView {
    // MARK: - Selection toolbar

    /// The pending selection ends on this row, so its toolbar sits under this row.
    var pendingSelectionEnding: DiffLineSelection? {
        guard let selection = interaction.pendingSelection, selection.filePath == file.path else { return nil }
        let number = selection.side == .old ? row.left?.oldLineNumber : row.right?.newLineNumber
        return number == selection.range.upperBound ? selection : nil
    }

    func pendingSelectionToolbar(_ selection: DiffLineSelection) -> some View {
        HStack(spacing: 8) {
            Button {
                interaction.openCommentAnchor(
                    DiffCommentAnchor(
                        filePath: selection.filePath,
                        side: selection.side,
                        startLine: selection.range.lowerBound,
                        endLine: selection.range.upperBound
                    )
                )
            } label: {
                Label(Self.commentButtonTitle(for: selection.range), systemImage: "plus.bubble")
            }
            .buttonStyle(.borderless)

            Button {
                let texts = layout.lineTexts[selection.side] ?? [:]
                DiffSelectionCopy.copyToPasteboard(DiffSelectionCopy.text(lines: selection.range, texts: texts))
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(.borderless)

            Button {
                interaction.dismissLineSelection()
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

    private static func commentButtonTitle(for range: ClosedRange<Int>) -> String {
        range.lowerBound == range.upperBound
            ? "Comment on line \(range.lowerBound)"
            : "Comment on lines \(range.lowerBound)\u{2013}\(range.upperBound)"
    }

    // MARK: - Range label

    /// The multi-line range (a pending selection, or the open composer's anchor) that starts on this row.
    private var rangeStart: (side: ReviewComment.Side, range: ClosedRange<Int>)? {
        func starts(_ side: ReviewComment.Side, _ range: ClosedRange<Int>) -> Bool {
            let number = side == .old ? row.left?.oldLineNumber : row.right?.newLineNumber
            return range.count > 1 && number == range.lowerBound
        }
        if let pending = interaction.pendingSelection, pending.filePath == file.path,
            starts(pending.side, pending.range)
        {
            return (pending.side, pending.range)
        }
        if let anchor = interaction.activeCommentAnchor, anchor.filePath == file.path {
            let range = anchor.startLine...anchor.endLine
            if starts(anchor.side, range) { return (anchor.side, range) }
        }
        return nil
    }

    /// A "Lines a–b" chip directly above the first selected line, aligned to the gutter of its side, so the
    /// range stays readable when the toolbar or composer sits far below under the last line.
    @ViewBuilder
    var rangeLabel: some View {
        if let start = rangeStart {
            HStack(spacing: 0) {
                rangeLabelHalf(.old, start: start)
                Color.clear.frame(width: 1)
                rangeLabelHalf(.new, start: start)
            }
        }
    }

    private func rangeLabelHalf(
        _ side: ReviewComment.Side,
        start: (side: ReviewComment.Side, range: ClosedRange<Int>)
    ) -> some View {
        HStack(spacing: 0) {
            if start.side == side {
                Text("Lines \(start.range.lowerBound)\u{2013}\(start.range.upperBound)")
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .foregroundStyle(DiffReviewTheme.addCommentForeground)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(DiffReviewTheme.selectionBackground, in: RoundedRectangle(cornerRadius: 3))
                    .padding(.leading, 4)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 16, maxHeight: 16)
    }

    // MARK: - Comments and composer

    /// The composer anchored to this row, if the open anchor ends here.
    private var composerAnchor: DiffCommentAnchor? {
        guard let anchor = interaction.activeCommentAnchor, anchor.filePath == file.path else { return nil }
        switch anchor.side {
        case .old: return row.left?.oldLineNumber == anchor.endLine ? anchor : nil
        case .new: return row.right?.newLineNumber == anchor.endLine ? anchor : nil
        }
    }

    private var commentsAnchoredHere: [ReviewComment] {
        model.comments(for: file.path).filter { comment in
            switch comment.side {
            case .old: row.left?.oldLineNumber == comment.lineNumber
            case .new: row.right?.newLineNumber == comment.lineNumber
            }
        }
    }

    @ViewBuilder
    var attachments: some View {
        let composer = composerAnchor
        let comments = commentsAnchoredHere
        if composer != nil || !comments.isEmpty {
            HStack(alignment: .top, spacing: 0) {
                attachmentColumn(.old, composer: composer, comments: comments)
                attachmentColumn(.new, composer: composer, comments: comments)
            }
        }
    }

    /// One half of the attachment row: cards for the comments on this side, and the composer if it is
    /// anchored to this side. The other half stays empty, as on GitHub.
    private func attachmentColumn(
        _ side: ReviewComment.Side,
        composer: DiffCommentAnchor?,
        comments: [ReviewComment]
    ) -> some View {
        VStack(spacing: 0) {
            if let composer, composer.side == side {
                commentComposer(composer)
            }
            ForEach(comments.filter { $0.side == side }) { comment in
                CommentThreadView(model: model, comment: comment)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func commentComposer(_ anchor: DiffCommentAnchor) -> some View {
        CommentCard(
            lineRange: anchor.startLine == anchor.endLine
                ? "Line \(anchor.startLine)"
                : "Lines \(anchor.startLine)\u{2013}\(anchor.endLine)",
            status: nil
        ) {
            TextEditor(text: $interaction.draftCommentText)
                .frame(height: 60)
                .font(.system(.body, design: .monospaced))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(DiffReviewTheme.cardBorder))
        } footer: {
            HStack {
                Spacer()
                Button("Cancel") {
                    interaction.closeCommentComposer()
                }
                Button("Comment") {
                    model.addComment(
                        filePath: file.path,
                        side: anchor.side,
                        startLineNumber: anchor.startLine == anchor.endLine ? nil : anchor.startLine,
                        lineNumber: anchor.endLine,
                        body: interaction.draftCommentText
                    )
                    interaction.closeCommentComposer()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(interaction.draftCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
