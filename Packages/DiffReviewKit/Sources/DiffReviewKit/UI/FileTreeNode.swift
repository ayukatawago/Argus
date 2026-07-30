import Foundation

/// One node in the hierarchical view of changed files: either a directory (`children` populated,
/// `file` nil) or a changed file (`file` populated, `children` nil).
struct FileTreeNode: Identifiable, Hashable {
    let id: String
    let name: String
    let file: DiffFile?
    var children: [FileTreeNode]?

    var isDirectory: Bool { children != nil }
}

/// Builds a directory tree from a flat list of changed files, grouping by path component.
enum FileTreeBuilder {
    /// Builds the tree, then collapses directory chains with no branching (a folder whose only
    /// child is itself a folder) into a single row — e.g. `Sources/DiffReviewKit/UI` instead of
    /// three nested rows — matching GitHub's PR file tree.
    static func build(from files: [DiffFile]) -> [FileTreeNode] {
        let entries = files.map { (components: $0.path.split(separator: "/").map(String.init), file: $0) }
        return buildLevel(entries, pathPrefix: "").map(compressed)
    }

    /// Merges a run of single-child directories into one node, working bottom-up so a chain of
    /// any length collapses fully (e.g. `A > B > C` becomes one `"A/B/C"` node).
    private static func compressed(_ node: FileTreeNode) -> FileTreeNode {
        guard let children = node.children else { return node }
        let compressedChildren = children.map(compressed)
        if compressedChildren.count == 1, let onlyChild = compressedChildren.first, onlyChild.isDirectory {
            return FileTreeNode(
                id: onlyChild.id,
                name: "\(node.name)/\(onlyChild.name)",
                file: nil,
                children: onlyChild.children
            )
        }
        return FileTreeNode(id: node.id, name: node.name, file: nil, children: compressedChildren)
    }

    private static func buildLevel(
        _ entries: [(components: [String], file: DiffFile)],
        pathPrefix: String
    ) -> [FileTreeNode] {
        var groups: [String: [(components: [String], file: DiffFile)]] = [:]
        var order: [String] = []

        for entry in entries {
            guard let head = entry.components.first else { continue }
            if groups[head] == nil {
                order.append(head)
            }
            groups[head, default: []].append((Array(entry.components.dropFirst()), entry.file))
        }

        return
            order
            .map { name in node(named: name, group: groups[name] ?? [], pathPrefix: pathPrefix) }
            .sorted(by: isOrderedBefore)
    }

    private static func node(
        named name: String,
        group: [(components: [String], file: DiffFile)],
        pathPrefix: String
    ) -> FileTreeNode {
        let fullPath = pathPrefix.isEmpty ? name : "\(pathPrefix)/\(name)"
        if group.count == 1, let onlyEntry = group.first, onlyEntry.components.isEmpty {
            return FileTreeNode(id: fullPath, name: name, file: onlyEntry.file, children: nil)
        }
        return FileTreeNode(id: fullPath, name: name, file: nil, children: buildLevel(group, pathPrefix: fullPath))
    }

    private static func isOrderedBefore(_ lhs: FileTreeNode, _ rhs: FileTreeNode) -> Bool {
        switch (lhs.isDirectory, rhs.isDirectory) {
        case (true, false): true
        case (false, true): false
        default: lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
