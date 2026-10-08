import Foundation

/// Incremental line splitter for an append-only JSON-Lines file.
///
/// Owns the three things every JSONL consumer otherwise re-implements: a byte offset, a `carry`
/// buffer for an unterminated trailing fragment, and detection of a file that was truncated or
/// replaced out from under it. It only ever yields *complete* lines (terminated by `\n`) — a write
/// that lands mid-line is held back until its newline arrives, rather than surfacing as two broken
/// halves. Cutting at `\n` can never split a UTF-8 multibyte sequence (a newline byte never occurs
/// inside one), so every yielded line is a whole number of codepoints.
public struct JSONLCursor: Sendable {
    /// Bytes consumed from the file so far (including any held in `carry`).
    public private(set) var offset: UInt64
    private var carry = Data()
    private var fileID: UInt64?
    /// True while discarding the tail of a line that outgrew `maxCarryBytes`, until its newline.
    private var skippingOversizedLine = false
    private let maxCarryBytes: Int

    /// - Parameters:
    ///   - offset: where to start reading (e.g. the file's current size to ignore existing history).
    ///   - maxCarryBytes: cap on an unterminated line; a longer one is dropped whole rather than
    ///     buffered without bound.
    public init(offset: UInt64 = 0, maxCarryBytes: Int = 4 << 20) {
        self.offset = offset
        self.maxCarryBytes = maxCarryBytes
    }

    /// Feeds raw bytes and returns the complete, non-empty lines they finish (without the `\n`).
    public mutating func ingest(_ data: Data) -> [Data] {
        var lines: [Data] = []
        var remaining = data[...]
        while let newline = remaining.firstIndex(of: 0x0A) {
            let head = remaining[remaining.startIndex..<newline]
            remaining = remaining[remaining.index(after: newline)...]
            if skippingOversizedLine {
                skippingOversizedLine = false
                continue
            }
            let line = carry + head
            carry = Data()
            if !line.isEmpty, line.count <= maxCarryBytes { lines.append(line) }
        }
        guard !skippingOversizedLine else { return lines }
        if carry.count + remaining.count > maxCarryBytes {
            carry = Data()
            skippingOversizedLine = true
        } else {
            carry.append(contentsOf: remaining)
        }
        return lines
    }

    /// Returns the buffered unterminated fragment as a final line, for readers that reach EOF.
    public mutating func finish() -> Data? {
        defer { carry = Data() }
        return carry.isEmpty ? nil : carry
    }

    /// Forgets the offset and any buffered fragment — the file was truncated or replaced.
    public mutating func reset() {
        offset = 0
        carry = Data()
        skippingOversizedLine = false
    }

    /// Reads whatever the file at `path` has gained since the last call. Returns `[]` when the file
    /// is missing or hasn't grown. A file that shrank, or whose inode changed (rotation by rename),
    /// is re-read from the start.
    public mutating func poll(path: String) -> [Data] {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
            let size = (attributes[.size] as? NSNumber)?.uint64Value
        else {
            reset()
            fileID = nil
            return []
        }
        let currentID = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        if size < offset || (fileID != nil && currentID != fileID) { reset() }
        fileID = currentID
        guard size > offset, let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return [] }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: offset)) != nil, let chunk = try? handle.readToEnd(), !chunk.isEmpty else {
            return []
        }
        // Advance by what was actually read, not the stat'd size: the file may have grown in between.
        offset += UInt64(chunk.count)
        return ingest(chunk)
    }
}
