import SwiftUI

/// Sidebar file tree: all directories start expanded (SwiftUI's built-in `List(_:children:)`
/// always starts collapsed with no way to override that, so this is hand-rolled with
/// `DisclosureGroup`). Selecting a file updates `model.selectedFilePath`; directories only
/// expand/collapse.
struct FileTreeView: View {
    let model: DiffReviewModel

    @State private var expandedIDs: Set<String> = []

    private var tree: [FileTreeNode] {
        FileTreeBuilder.build(from: model.files)
    }

    var body: some View {
        List {
            ForEach(tree) { node in
                FileTreeRowRecursive(node: node, model: model, expandedIDs: $expandedIDs)
            }
        }
        .listStyle(.sidebar)
        .onAppear { expandAll(tree) }
        .onChange(of: model.files) { _, newFiles in
            expandAll(FileTreeBuilder.build(from: newFiles))
        }
    }

    private func expandAll(_ nodes: [FileTreeNode]) {
        var ids = expandedIDs
        collectDirectoryIDs(nodes, into: &ids)
        expandedIDs = ids
    }

    private func collectDirectoryIDs(_ nodes: [FileTreeNode], into set: inout Set<String>) {
        for node in nodes {
            guard let children = node.children else { continue }
            set.insert(node.id)
            collectDirectoryIDs(children, into: &set)
        }
    }
}

private struct FileTreeRowRecursive: View {
    let node: FileTreeNode
    let model: DiffReviewModel
    @Binding var expandedIDs: Set<String>

    var body: some View {
        if let children = node.children {
            DisclosureGroup(isExpanded: isExpandedBinding) {
                ForEach(children) { child in
                    FileTreeRowRecursive(node: child, model: model, expandedIDs: $expandedIDs)
                }
            } label: {
                FileTreeRowLabel(node: node, commentCount: 0)
            }
        } else {
            FileTreeRowLabel(node: node, commentCount: commentCount)
                .contentShape(Rectangle())
                .listRowBackground(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
                .onTapGesture {
                    if let file = node.file {
                        model.selectedFilePath = file.path
                    }
                }
        }
    }

    private var commentCount: Int {
        node.file.map { model.comments(for: $0.path).count } ?? 0
    }

    private var isSelected: Bool {
        node.file != nil && node.file?.path == model.selectedFilePath
    }

    private var isExpandedBinding: Binding<Bool> {
        Binding(
            get: { expandedIDs.contains(node.id) },
            set: { isExpanded in
                if isExpanded {
                    expandedIDs.insert(node.id)
                } else {
                    expandedIDs.remove(node.id)
                }
            }
        )
    }
}

private struct FileTreeRowLabel: View {
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
