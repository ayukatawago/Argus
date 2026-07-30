import SwiftUI

/// Sidebar file tree: directories expand/collapse, changed files show per-file stats and a
/// comment-thread indicator. Selecting a file updates `model.selectedFilePath`; selecting a
/// directory only expands/collapses it.
struct FileTreeView: View {
    let model: DiffReviewModel

    @State private var treeSelection: String?

    private var tree: [FileTreeNode] {
        FileTreeBuilder.build(from: model.files)
    }

    var body: some View {
        List(tree, children: \.children, selection: $treeSelection) { node in
            FileTreeRow(node: node, commentCount: node.file.map { model.comments(for: $0.path).count } ?? 0)
        }
        .listStyle(.sidebar)
        .onChange(of: treeSelection) { _, newValue in
            guard let newValue, let file = findNode(id: newValue, in: tree)?.file else { return }
            model.selectedFilePath = file.path
        }
        .onChange(of: model.selectedFilePath) { _, newValue in
            treeSelection = newValue
        }
        .onAppear {
            treeSelection = model.selectedFilePath
        }
    }

    private func findNode(id: String, in nodes: [FileTreeNode]) -> FileTreeNode? {
        for node in nodes {
            if node.id == id { return node }
            if let children = node.children, let found = findNode(id: id, in: children) {
                return found
            }
        }
        return nil
    }
}

private struct FileTreeRow: View {
    let node: FileTreeNode
    let commentCount: Int

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .frame(width: 16)
            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if commentCount > 0 {
                Image(systemName: "bubble.left.fill")
                    .foregroundStyle(DiffReviewTheme.commentAccent)
                    .imageScale(.small)
            }
            if let file = node.file {
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
    }

    private var icon: String {
        switch node.file?.kind {
        case .added: "plus.circle"
        case .deleted: "minus.circle"
        case .modified: "pencil.circle"
        case .renamed: "arrow.turn.up.right"
        case nil: "folder"
        }
    }

    private var iconColor: Color {
        switch node.file?.kind {
        case .added: DiffReviewTheme.additionForeground
        case .deleted: DiffReviewTheme.deletionForeground
        case .modified, .renamed: .secondary
        case nil: .secondary
        }
    }
}
