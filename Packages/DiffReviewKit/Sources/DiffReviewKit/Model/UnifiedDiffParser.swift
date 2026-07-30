import Foundation

/// Parses `git diff` unified-diff output into `[DiffFile]`. Pure and dependency-free (no git
/// invocation) so it can be tested against fixed diff text.
public enum UnifiedDiffParser {
    /// Per-file metadata lines (mode/rename/`---`/`+++`) accumulated while scanning one
    /// `diff --git` block, before its hunks are parsed.
    private struct FileBlockMetadata {
        var oldPath: String?
        var newPath: String?
        var isNewFile = false
        var isDeletedFile = false
        var renameFrom: String?
        var renameTo: String?
    }

    /// Result of scanning one file block: its metadata, the raw hunk-area lines (still to be
    /// parsed by `parseHunks`), and the index to resume scanning the overall diff from.
    private struct FileBlockScanResult {
        var metadata: FileBlockMetadata
        var hunkLines: [String]
        var nextIndex: Int
    }

    public static func parse(_ text: String) -> [DiffFile] {
        guard !text.isEmpty else { return [] }
        let lines = normalizedLines(text)

        var files: [DiffFile] = []
        var index = 0

        while index < lines.count {
            guard lines[index].hasPrefix("diff --git ") else {
                index += 1
                continue
            }
            let headerPaths = extractHeaderPaths(lines[index])
            index += 1

            let block = parseFileBlock(lines, startingAt: index)
            index = block.nextIndex

            files.append(buildFile(metadata: block.metadata, headerPaths: headerPaths, hunkLines: block.hunkLines))
        }

        return files
    }

    private static func normalizedLines(_ text: String) -> [String] {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.hasSuffix("\r") ? String($0.dropLast()) : String($0) }
    }

    /// Scans metadata and hunk lines for one file block, stopping at the next `diff --git` line
    /// (or end of input).
    private static func parseFileBlock(_ lines: [String], startingAt start: Int) -> FileBlockScanResult {
        var metadata = FileBlockMetadata()
        var hunkLines: [String] = []
        var index = start

        while index < lines.count, !lines[index].hasPrefix("diff --git ") {
            let line = lines[index]
            index += 1
            if line.hasPrefix("new file mode") {
                metadata.isNewFile = true
            } else if line.hasPrefix("deleted file mode") {
                metadata.isDeletedFile = true
            } else if line.hasPrefix("rename from ") {
                metadata.renameFrom = String(line.dropFirst("rename from ".count))
            } else if line.hasPrefix("rename to ") {
                metadata.renameTo = String(line.dropFirst("rename to ".count))
            } else if line.hasPrefix("--- ") {
                metadata.oldPath = stripGitPrefix(String(line.dropFirst(4)))
            } else if line.hasPrefix("+++ ") {
                metadata.newPath = stripGitPrefix(String(line.dropFirst(4)))
            } else if line.hasPrefix("@@ ") || !hunkLines.isEmpty {
                hunkLines.append(line)
            }
        }

        return FileBlockScanResult(metadata: metadata, hunkLines: hunkLines, nextIndex: index)
    }

    private static func buildFile(
        metadata: FileBlockMetadata,
        headerPaths: (old: String, new: String)?,
        hunkLines: [String]
    ) -> DiffFile {
        let resolvedNewPath =
            metadata.renameTo ?? metadata.newPath ?? headerPaths?.new ?? metadata.renameFrom ?? metadata.oldPath
            ?? "unknown"
        let resolvedOldPath = metadata.renameFrom ?? metadata.oldPath ?? headerPaths?.old

        let kind: DiffFile.ChangeKind =
            if metadata.isNewFile {
                .added
            } else if metadata.isDeletedFile {
                .deleted
            } else if metadata.renameFrom != nil || metadata.renameTo != nil {
                .renamed
            } else {
                .modified
            }

        return DiffFile(
            path: resolvedNewPath,
            oldPath: kind == .renamed ? resolvedOldPath : nil,
            kind: kind,
            hunks: parseHunks(hunkLines)
        )
    }

    // MARK: - Header path fallback

    /// Best-effort extraction of the two paths from a `diff --git a/X b/Y` line. Used only when
    /// the more reliable `--- `/`+++ ` lines are absent (e.g. binary files, pure renames).
    /// Ambiguous when a path itself contains the literal substring `" b/"`.
    private static func extractHeaderPaths(_ line: String) -> (old: String, new: String)? {
        let prefix = "diff --git "
        guard line.hasPrefix(prefix) else { return nil }
        let rest = line.dropFirst(prefix.count)
        guard let range = rest.range(of: " b/") else { return nil }
        let oldPart = rest[rest.startIndex..<range.lowerBound]
        let newPart = rest[range.upperBound...]
        guard oldPart.hasPrefix("a/") else { return nil }
        return (String(oldPart.dropFirst(2)), String(newPart))
    }

    private static func stripGitPrefix(_ path: String) -> String? {
        if path == "/dev/null" { return nil }
        if path.hasPrefix("a/") || path.hasPrefix("b/") {
            return String(path.dropFirst(2))
        }
        return path
    }

    // MARK: - Hunks

    private static func parseHunks(_ lines: [String]) -> [DiffHunk] {
        var hunks: [DiffHunk] = []
        var index = 0

        while index < lines.count {
            guard lines[index].hasPrefix("@@ "), let range = parseHunkRange(lines[index]) else {
                index += 1
                continue
            }
            let header = lines[index]
            index += 1

            var oldLine = range.old
            var newLine = range.new
            var diffLines: [DiffLine] = []

            while index < lines.count, !lines[index].hasPrefix("@@ ") {
                let raw = lines[index]
                index += 1
                guard let marker = raw.first else { continue }
                let text = String(raw.dropFirst())
                switch marker {
                case " ":
                    diffLines.append(
                        DiffLine(kind: .context, text: text, oldLineNumber: oldLine, newLineNumber: newLine)
                    )
                    oldLine += 1
                    newLine += 1

                case "-":
                    diffLines.append(DiffLine(kind: .deletion, text: text, oldLineNumber: oldLine, newLineNumber: nil))
                    oldLine += 1

                case "+":
                    diffLines.append(DiffLine(kind: .addition, text: text, oldLineNumber: nil, newLineNumber: newLine))
                    newLine += 1

                default:
                    continue  // "\ No newline at end of file" and anything else — not a content row.
                }
            }

            hunks.append(DiffHunk(header: header, lines: diffLines))
        }

        return hunks
    }

    private static func parseHunkRange(_ header: String) -> (old: Int, new: Int)? {
        let parts = header.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 3, parts[0] == "@@" else { return nil }
        guard let old = parseRangeStart(String(parts[1])), let new = parseRangeStart(String(parts[2])) else {
            return nil
        }
        return (old, new)
    }

    private static func parseRangeStart(_ token: String) -> Int? {
        guard let sign = token.first, sign == "-" || sign == "+" else { return nil }
        let body = token.dropFirst()
        let numberPart = body.split(separator: ",").first.map(String.init) ?? String(body)
        return Int(numberPart)
    }
}
