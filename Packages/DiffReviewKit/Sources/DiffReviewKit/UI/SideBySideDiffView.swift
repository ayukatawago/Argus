import SwiftUI

/// One rendered row of the side-by-side view: a line from the old file, the new file, or both
/// (for unchanged context lines).
struct SideBySideRow: Identifiable {
    let id: String
    let left: DiffLine?
    let right: DiffLine?
}

/// Pairs a hunk's flat sequence of context/deletion/addition lines into side-by-side rows, the way
/// GitHub's split diff view does: consecutive deletions are paired index-wise with the consecutive
/// additions that follow them, and unmatched lines get an empty cell on the other side.
enum SideBySideBuilder {
    static func rows(for hunk: DiffHunk) -> [SideBySideRow] {
        var rows: [SideBySideRow] = []
        let lines = hunk.lines
        var index = 0

        while index < lines.count {
            let line = lines[index]
            switch line.kind {
            case .context:
                rows.append(SideBySideRow(id: line.id.uuidString, left: line, right: line))
                index += 1

            case .deletion, .addition:
                var deletions: [DiffLine] = []
                while index < lines.count, lines[index].kind == .deletion {
                    deletions.append(lines[index])
                    index += 1
                }
                var additions: [DiffLine] = []
                while index < lines.count, lines[index].kind == .addition {
                    additions.append(lines[index])
                    index += 1
                }
                let pairCount = max(deletions.count, additions.count)
                for pairIndex in 0..<pairCount {
                    let left = deletions[safe: pairIndex]
                    let right = additions[safe: pairIndex]
                    rows.append(
                        SideBySideRow(
                            id: "\(left?.id.uuidString ?? "-")|\(right?.id.uuidString ?? "-")",
                            left: left,
                            right: right
                        )
                    )
                }
            }
        }

        return rows
    }
}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// Two-column diff for a single file: line numbers, added/removed highlighting, per-line "add
/// comment" affordance, and inline comment threads.
struct SideBySideDiffView: View {
    let model: DiffReviewModel
    let file: DiffFile

    @State private var activeCommentAnchor: CommentAnchor?
    @State private var draftCommentText = ""

    struct CommentAnchor: Equatable {
        let side: ReviewComment.Side
        let lineNumber: Int
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
                    ForEach(file.hunks) { hunk in
                        hunkHeader(hunk)
                        ForEach(SideBySideBuilder.rows(for: hunk)) { row in
                            rowView(row)
                        }
                    }
                }
            }
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

    @ViewBuilder
    private func rowView(_ row: SideBySideRow) -> some View {
        let modification = intralineChanges(for: row)
        HStack(spacing: 0) {
            cell(line: row.left, side: .old, changedRanges: modification?.old)
            Divider()
            cell(line: row.right, side: .new, changedRanges: modification?.new)
        }

        if let anchor = activeCommentAnchor, matches(anchor, row: row) {
            commentComposer(anchor: anchor)
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
        case .old: row.left?.oldLineNumber == anchor.lineNumber
        case .new: row.right?.newLineNumber == anchor.lineNumber
        }
    }

    private func commentsAnchored(to row: SideBySideRow) -> [ReviewComment] {
        model.comments(for: file.path).filter { comment in
            switch comment.side {
            case .old: row.left?.oldLineNumber == comment.lineNumber
            case .new: row.right?.newLineNumber == comment.lineNumber
            }
        }
    }

    @ViewBuilder
    private func cell(line: DiffLine?, side: ReviewComment.Side, changedRanges: [Range<String.Index>]?) -> some View {
        HStack(spacing: 6) {
            if let line {
                let number = side == .old ? line.oldLineNumber : line.newLineNumber
                Text(number.map(String.init) ?? "")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(DiffReviewTheme.lineNumberForeground)
                    .frame(width: 36, alignment: .trailing)

                Button {
                    if let number {
                        activeCommentAnchor = CommentAnchor(side: side, lineNumber: number)
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
        // A modified line (changedRanges != nil) shows no whole-line tint — only the changed span,
        // via a backgroundColor run inside highlightedText — so unchanged text on that line reads
        // normally instead of implying the entire line is new/removed.
        .background(changedRanges == nil ? background(for: line?.kind) : .clear)
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

    @ViewBuilder
    private func commentComposer(anchor: CommentAnchor) -> some View {
        VStack(alignment: .leading, spacing: 6) {
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
                        lineNumber: anchor.lineNumber,
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
