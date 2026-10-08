import Foundation

/// One entry in the markdown preview's file tree. The JSON shape (`type`/`name`/`path`/`children`)
/// is what `markdown-preview.html` consumes, so field names must not change.
public struct MarkdownTreeNode: Encodable, Equatable, Sendable {
    public let type: String
    public let name: String
    public let path: String?
    public let children: [MarkdownTreeNode]?
}

/// Builds the directory tree of markdown files shown beside a preview. Bounded and defensive: it
/// runs over arbitrary worktrees, which can hold `node_modules` trees, symlink loops and very large
/// monorepos, and the previous unbounded recursive walk could freeze the UI or recurse forever.
public enum MarkdownFileTree {
    /// Dependency/build output folders that never hold documentation worth previewing.
    public static let skippedDirectoryNames: Set<String> = [
        "node_modules", "Pods", "Carthage", "DerivedData", "vendor", "__pycache__",
    ]

    /// Markdown files under `path`, directories first, both groups sorted by name. Hidden entries
    /// and `skippedDirectoryNames` are omitted; symlinked directories are not followed; directories
    /// containing no markdown are dropped. Stops descending past `maxDepth` levels and stops
    /// collecting after `maxNodes` entries.
    public static func build(
        at path: String, maxDepth: Int = 8, maxNodes: Int = 5_000, fileManager: FileManager = .default
    ) -> [MarkdownTreeNode] {
        var remaining = maxNodes
        return children(of: path, depth: maxDepth, remaining: &remaining, fileManager: fileManager)
    }

    private static func children(
        of dirPath: String, depth: Int, remaining: inout Int, fileManager: FileManager
    ) -> [MarkdownTreeNode] {
        guard depth > 0, remaining > 0, let entries = try? fileManager.contentsOfDirectory(atPath: dirPath) else {
            return []
        }
        var dirs: [MarkdownTreeNode] = []
        var files: [MarkdownTreeNode] = []
        for name in entries.sorted() where !name.hasPrefix(".") {
            guard remaining > 0 else { break }
            let fullPath = (dirPath as NSString).appendingPathComponent(name)
            let type = (try? fileManager.attributesOfItem(atPath: fullPath))?[.type] as? FileAttributeType
            if type == .typeDirectory {
                guard !skippedDirectoryNames.contains(name) else { continue }
                let nested = children(of: fullPath, depth: depth - 1, remaining: &remaining, fileManager: fileManager)
                if !nested.isEmpty {
                    dirs.append(MarkdownTreeNode(type: "dir", name: name, path: nil, children: nested))
                }
            } else if type != nil, name.lowercased().hasSuffix(".md") {
                remaining -= 1
                files.append(MarkdownTreeNode(type: "file", name: name, path: fullPath, children: nil))
            }
        }
        return dirs + files
    }
}
