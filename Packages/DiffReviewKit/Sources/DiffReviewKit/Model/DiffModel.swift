import Foundation

/// A single changed file within a diff.
public struct DiffFile: Identifiable, Hashable, Sendable {
    public enum ChangeKind: Sendable, Hashable {
        case added
        case deleted
        case modified
        case renamed
    }

    public var id: String { path }

    /// Path shown for the file (the "new" path for renames/adds; the only path otherwise).
    public let path: String
    /// Original path, populated only for renames.
    public let oldPath: String?
    public let kind: ChangeKind
    public let hunks: [DiffHunk]

    public init(path: String, oldPath: String? = nil, kind: ChangeKind, hunks: [DiffHunk]) {
        self.path = path
        self.oldPath = oldPath
        self.kind = kind
        self.hunks = hunks
    }

    public var additionCount: Int {
        hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .addition }.count }
    }

    public var deletionCount: Int {
        hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .deletion }.count }
    }

    /// True for files git reported no line-level hunks for (binary diffs, pure renames, mode-only
    /// changes) — the UI should show a placeholder instead of an empty side-by-side view.
    public var isBinaryOrHunkless: Bool { hunks.isEmpty }
}

/// A contiguous hunk of changed lines within a file, as reported by a unified diff `@@` header.
public struct DiffHunk: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let header: String
    public let lines: [DiffLine]

    public init(header: String, lines: [DiffLine]) {
        self.header = header
        self.lines = lines
    }
}

/// A single row of a diff, tagged with the old/new line numbers needed to render two aligned
/// side-by-side columns.
public struct DiffLine: Identifiable, Hashable, Sendable {
    public enum Kind: Sendable, Hashable {
        case context
        case addition
        case deletion
    }

    public let id = UUID()
    public let kind: Kind
    public let text: String
    /// Line number in the old (base) file; `nil` for pure additions.
    public let oldLineNumber: Int?
    /// Line number in the new (head) file; `nil` for pure deletions.
    public let newLineNumber: Int?

    public init(kind: Kind, text: String, oldLineNumber: Int?, newLineNumber: Int?) {
        self.kind = kind
        self.text = text
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
    }
}
