import SwiftUI

/// Sidebar list of changed files with add/delete counts and a comment-thread indicator.
struct FileListView: View {
    let model: DiffReviewModel

    var body: some View {
        List(
            model.files,
            selection: Binding(
                get: { model.selectedFilePath },
                set: { model.selectedFilePath = $0 }
            )
        ) { file in
            FileRow(file: file, commentCount: model.comments(for: file.path).count)
        }
        .listStyle(.sidebar)
    }
}

private struct FileRow: View {
    let file: DiffFile
    let commentCount: Int

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .frame(width: 16)
            Text(file.path)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer()
            if commentCount > 0 {
                Image(systemName: "bubble.left.fill")
                    .foregroundStyle(DiffReviewTheme.commentAccent)
                    .imageScale(.small)
            }
            HStack(spacing: 2) {
                if file.additionCount > 0 {
                    Text("+\(file.additionCount)").foregroundStyle(DiffReviewTheme.additionForeground)
                }
                if file.deletionCount > 0 {
                    Text("-\(file.deletionCount)").foregroundStyle(DiffReviewTheme.deletionForeground)
                }
            }
            .font(.caption.monospacedDigit())
        }
    }

    private var icon: String {
        switch file.kind {
        case .added: "plus.circle"
        case .deleted: "minus.circle"
        case .modified: "pencil.circle"
        case .renamed: "arrow.turn.up.right"
        }
    }

    private var iconColor: Color {
        switch file.kind {
        case .added: DiffReviewTheme.additionForeground
        case .deleted: DiffReviewTheme.deletionForeground
        case .modified, .renamed: .secondary
        }
    }
}
