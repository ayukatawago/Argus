import SwiftUI

/// The pinned header of one file's section: collapse chevron, path (old → new for a rename), `+N −M`,
/// the five-block diffstat, comment count, and the Viewed checkbox.
struct DiffFileHeaderView: View {
    let file: DiffFile
    let isViewed: Bool
    let isCollapsed: Bool
    let commentCount: Int
    let onToggleCollapsed: () -> Void
    let onToggleViewed: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggleCollapsed) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .frame(width: 12)
            }
            .buttonStyle(.borderless)

            Text(title)
                .font(.system(.callout, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 4) {
                Text("+\(file.additionCount)").foregroundStyle(DiffReviewTheme.additionForeground)
                Text("\u{2212}\(file.deletionCount)").foregroundStyle(DiffReviewTheme.deletionForeground)
            }
            .font(.caption.monospacedDigit())

            DiffStatBar(additions: file.additionCount, deletions: file.deletionCount)

            Spacer(minLength: 8)

            if commentCount > 0 {
                Label("\(commentCount)", systemImage: "bubble.left.fill")
                    .font(.caption)
                    .foregroundStyle(DiffReviewTheme.commentAccent)
            }

            Button(action: onToggleViewed) {
                HStack(spacing: 4) {
                    Image(systemName: isViewed ? "checkmark.square.fill" : "square")
                    Text("Viewed")
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DiffReviewTheme.fileHeaderBackground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DiffReviewTheme.fileHeaderBorder).frame(height: 1)
        }
    }

    private var title: String {
        guard let oldPath = file.oldPath else { return file.path }
        return "\(oldPath) \u{2192} \(file.path)"
    }
}

/// GitHub's five-block change bar: green for additions, red for deletions, gray for the rest.
private struct DiffStatBar: View {
    let additions: Int
    let deletions: Int

    var body: some View {
        HStack(spacing: 1) {
            let blocks = DiffStatBlocks.blocks(additions: additions, deletions: deletions)
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, kind in
                Rectangle().fill(color(for: kind)).frame(width: 8, height: 8)
            }
        }
    }

    private func color(for kind: DiffStatBlocks.Kind) -> Color {
        switch kind {
        case .addition: DiffReviewTheme.additionForeground
        case .deletion: DiffReviewTheme.deletionForeground
        case .neutral: DiffReviewTheme.fileHeaderBorder
        }
    }
}
