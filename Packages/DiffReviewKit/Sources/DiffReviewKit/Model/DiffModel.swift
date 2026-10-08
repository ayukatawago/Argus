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

/// A `(start, count)` line range parsed from one side of a hunk's `@@` header.
public struct HunkRange: Hashable, Sendable {
    public let start: Int
    public let count: Int

    public init(start: Int, count: Int) {
        self.start = start
        self.count = count
    }
}

/// A contiguous hunk of changed lines within a file, as reported by a unified diff `@@` header.
public struct DiffHunk: Identifiable, Hashable, Sendable {
    /// Deterministic: the parser assigns `"<fileIndex>-<hunkIndex>"`; hand-built hunks default to
    /// their header text (unique within a file).
    public let id: String
    public let header: String
    public let lines: [DiffLine]
    /// Old-file range parsed once from `header`; `nil` when the header is malformed.
    public let oldRange: HunkRange?
    /// New-file range parsed once from `header`; `nil` when the header is malformed.
    public let newRange: HunkRange?

    public init(header: String, lines: [DiffLine], id: String? = nil) {
        self.id = id ?? header
        self.header = header
        self.lines = lines
        let ranges = Self.parseRanges(header)
        oldRange = ranges?.old
        newRange = ranges?.new
    }

    /// Parses `@@ -start[,count] +start[,count] @@ ...`; a missing count means 1.
    static func parseRanges(_ header: String) -> (old: HunkRange, new: HunkRange)? {
        let parts = header.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 3, parts[0] == "@@",
            let old = parseRange(parts[1], sign: "-"), let new = parseRange(parts[2], sign: "+")
        else { return nil }
        return (old, new)
    }

    private static func parseRange(_ token: Substring, sign: Character) -> HunkRange? {
        guard token.first == sign else { return nil }
        let components = token.dropFirst().split(separator: ",", omittingEmptySubsequences: false)
        guard let first = components.first, let start = Int(first) else { return nil }
        let count = components.count > 1 ? (Int(components[1]) ?? 1) : 1
        return HunkRange(start: start, count: count)
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

    /// Deterministic: the parser assigns `"<fileIndex>-<hunkIndex>-<lineIndex>"`; hand-built lines
    /// default to a value derived from kind + line numbers.
    public let id: String
    public let kind: Kind
    public let text: String
    /// Line number in the old (base) file; `nil` for pure additions.
    public let oldLineNumber: Int?
    /// Line number in the new (head) file; `nil` for pure deletions.
    public let newLineNumber: Int?
    /// True when git followed this line with `\ No newline at end of file`.
    public var hasNoNewlineAtEnd: Bool

    public init(
        kind: Kind,
        text: String,
        oldLineNumber: Int?,
        newLineNumber: Int?,
        id: String? = nil,
        hasNoNewlineAtEnd: Bool = false
    ) {
        self.id = id ?? "\(kind)-\(oldLineNumber ?? -1)-\(newLineNumber ?? -1)"
        self.kind = kind
        self.text = text
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
        self.hasNoNewlineAtEnd = hasNoNewlineAtEnd
    }
}
