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

            files.append(
                buildFile(
                    metadata: block.metadata, headerPaths: headerPaths, hunkLines: block.hunkLines,
                    fileIndex: files.count)
            )
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
            // Once the first `@@` is seen, every remaining line belongs to a hunk: a deleted
            // `-- foo` or added `++ x` line must never be mistaken for a `---`/`+++` header.
            if !hunkLines.isEmpty || line.hasPrefix("@@ ") {
                hunkLines.append(line)
            } else if line.hasPrefix("new file mode") {
                metadata.isNewFile = true
            } else if line.hasPrefix("deleted file mode") {
                metadata.isDeletedFile = true
            } else if line.hasPrefix("rename from ") {
                metadata.renameFrom = decodePath(String(line.dropFirst("rename from ".count)))
            } else if line.hasPrefix("rename to ") {
                metadata.renameTo = decodePath(String(line.dropFirst("rename to ".count)))
            } else if line.hasPrefix("--- ") {
                metadata.oldPath = stripGitPrefix(decodePath(String(line.dropFirst(4))))
            } else if line.hasPrefix("+++ ") {
                metadata.newPath = stripGitPrefix(decodePath(String(line.dropFirst(4))))
            }
        }

        return FileBlockScanResult(metadata: metadata, hunkLines: hunkLines, nextIndex: index)
    }

    private static func buildFile(
        metadata: FileBlockMetadata,
        headerPaths: (old: String, new: String)?,
        hunkLines: [String],
        fileIndex: Int
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
            hunks: parseHunks(hunkLines, fileIndex: fileIndex)
        )
    }

    // MARK: - Header path fallback

    /// Best-effort extraction of the two paths from a `diff --git a/X b/Y` line (either side may
    /// be C-quoted). Used only when the more reliable `--- `/`+++ ` lines are absent (e.g. binary
    /// files, pure renames). Ambiguous when an unquoted path itself contains the literal `" b/"`.
    private static func extractHeaderPaths(_ line: String) -> (old: String, new: String)? {
        let prefix = "diff --git "
        guard line.hasPrefix(prefix) else { return nil }
        let rest = String(line.dropFirst(prefix.count))
        let oldPart: String
        let newPart: String
        if rest.hasPrefix("\""), let end = closingQuoteIndex(rest) {
            oldPart = String(rest[...end])
            newPart = rest[rest.index(after: end)...].trimmingCharacters(in: .whitespaces)
        } else if let range = rest.range(of: " \"b/") ?? rest.range(of: " b/") {
            oldPart = String(rest[rest.startIndex..<range.lowerBound])
            newPart = String(rest[rest.index(after: range.lowerBound)...])
        } else {
            return nil
        }
        guard let old = stripGitPrefix(decodePath(oldPart)), let new = stripGitPrefix(decodePath(newPart)) else {
            return nil
        }
        return (old, new)
    }

    /// Index of the quote closing the C-quoted string that starts at `text.startIndex`.
    private static func closingQuoteIndex(_ text: String) -> String.Index? {
        var index = text.index(after: text.startIndex)
        while index < text.endIndex {
            if text[index] == "\\" {
                index = text.index(after: index)
                guard index < text.endIndex else { return nil }
            } else if text[index] == "\"" {
                return index
            }
            index = text.index(after: index)
        }
        return nil
    }

    /// Strips git's trailing `\t` (added after paths containing spaces) and un-C-quotes the path.
    static func decodePath(_ raw: String) -> String {
        var path = raw
        if path.hasPrefix("\"") {
            if let end = closingQuoteIndex(path) { path = String(path[...end]) }
            return unquoteCStyle(path)
        }
        if let tab = path.firstIndex(of: "\t") { path = String(path[..<tab]) }
        return path
    }

    /// Decodes git's C-style quoting (`\"`, `\\`, `\n`, `\t`, octal `\NNN` byte escapes).
    static func unquoteCStyle(_ quoted: String) -> String {
        guard quoted.count >= 2, quoted.hasPrefix("\""), quoted.hasSuffix("\"") else { return quoted }
        let bytes = Array(quoted.utf8.dropFirst().dropLast())
        var output: [UInt8] = []
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            guard byte == UInt8(ascii: "\\"), index < bytes.count else {
                output.append(byte)
                continue
            }
            let escaped = bytes[index]
            index += 1
            if (UInt8(ascii: "0")...UInt8(ascii: "7")).contains(escaped) {
                var value = Int(escaped - UInt8(ascii: "0"))
                var digits = 1
                while digits < 3, index < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "7")).contains(bytes[index]) {
                    value = value * 8 + Int(bytes[index] - UInt8(ascii: "0"))
                    index += 1
                    digits += 1
                }
                output.append(UInt8(truncatingIfNeeded: value))
                continue
            }
            switch escaped {
            case UInt8(ascii: "n"): output.append(0x0A)
            case UInt8(ascii: "t"): output.append(0x09)
            case UInt8(ascii: "r"): output.append(0x0D)
            case UInt8(ascii: "a"): output.append(0x07)
            case UInt8(ascii: "b"): output.append(0x08)
            case UInt8(ascii: "f"): output.append(0x0C)
            case UInt8(ascii: "v"): output.append(0x0B)
            default: output.append(escaped)
            }
        }
        return String(decoding: output, as: UTF8.self)
    }

    private static func stripGitPrefix(_ path: String) -> String? {
        if path == "/dev/null" { return nil }
        if path.hasPrefix("a/") || path.hasPrefix("b/") {
            return String(path.dropFirst(2))
        }
        return path
    }

    // MARK: - Hunks

    private static func parseHunks(_ lines: [String], fileIndex: Int) -> [DiffHunk] {
        var hunks: [DiffHunk] = []
        var index = 0

        while index < lines.count {
            guard lines[index].hasPrefix("@@ "), let ranges = DiffHunk.parseRanges(lines[index]) else {
                index += 1
                continue
            }
            let header = lines[index]
            index += 1

            var oldLine = ranges.old.start
            var newLine = ranges.new.start
            var diffLines: [DiffLine] = []
            let idPrefix = "\(fileIndex)-\(hunks.count)"

            while index < lines.count, !lines[index].hasPrefix("@@ ") {
                let raw = lines[index]
                index += 1
                guard let marker = raw.first else { continue }
                let text = String(raw.dropFirst())
                let lineID = "\(idPrefix)-\(diffLines.count)"
                switch marker {
                case " ":
                    diffLines.append(
                        DiffLine(
                            kind: .context, text: text, oldLineNumber: oldLine, newLineNumber: newLine, id: lineID)
                    )
                    oldLine += 1
                    newLine += 1

                case "-":
                    diffLines.append(
                        DiffLine(kind: .deletion, text: text, oldLineNumber: oldLine, newLineNumber: nil, id: lineID)
                    )
                    oldLine += 1

                case "+":
                    diffLines.append(
                        DiffLine(kind: .addition, text: text, oldLineNumber: nil, newLineNumber: newLine, id: lineID)
                    )
                    newLine += 1

                case "\\":
                    // "\ No newline at end of file" — a marker on the line it follows, not a row.
                    if let last = diffLines.indices.last { diffLines[last].hasNoNewlineAtEnd = true }

                default:
                    continue
                }
            }

            hunks.append(DiffHunk(header: header, lines: diffLines, id: idPrefix))
        }

        return hunks
    }
}
