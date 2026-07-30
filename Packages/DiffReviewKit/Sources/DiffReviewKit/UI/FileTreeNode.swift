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
    static func build(from files: [DiffFile]) -> [FileTreeNode] {
        let entries = files.map { (components: $0.path.split(separator: "/").map(String.init), file: $0) }
        return buildLevel(entries, pathPrefix: "")
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
