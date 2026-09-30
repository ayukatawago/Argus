import Foundation

/// Reads a JSON-Lines file in bounded-memory chunks, yielding each complete line to `body` as a
/// `String`. Complements `JSONLTailer`, which streams newly-appended lines from a live-growing
/// file; this reads a whole file once, front to back — the shape a usage-report scan over
/// potentially tens-of-megabyte Codex rollouts needs, where `String(contentsOf:)` would spike
/// memory proportional to file size for no benefit (the caller only ever wants one line at a time).
public enum JSONLFileReader {
    /// - Parameter chunkSize: bytes read per `FileHandle` call. Large enough that a day's worth of
    ///   rollout (tens of MB here) needs only a handful of reads; small enough to keep peak memory
    ///   bounded regardless of file size.
    public static func forEachLine(
        at url: URL, chunkSize: Int = 1 << 20, _ body: (String) throws -> Void
    ) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        // Carries an unterminated trailing fragment across chunk boundaries — a chunk edge is a
        // byte-count cutoff, not a line boundary, so the last "line" in a chunk is frequently a
        // partial one that must be glued to the start of the next chunk before decoding.
        var pending = Data()
        // swiftlint:disable optional_data_string_conversion
        while true {
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty { break }
            pending.append(chunk)

            // Cut at the last newline in the buffer, not the whole thing: cutting on `\n` can never
            // split a UTF-8 multibyte sequence (a newline byte never occurs inside one), so the
            // "complete" half below always decodes losslessly (`String(decoding:as:)` never fails —
            // deliberately used over the failable `String(bytes:encoding:)` for that reason). Mirrors
            // ClaudeTranscriptParser.splitAtLastNewline's rationale.
            guard let newlineIndex = pending.lastIndex(of: 0x0A) else { continue }
            let completeEnd = pending.index(after: newlineIndex)
            let complete = pending[pending.startIndex..<completeEnd]
            pending = Data(pending[completeEnd...])

            for line in complete.split(separator: 0x0A, omittingEmptySubsequences: true) {
                try body(String(decoding: line, as: UTF8.self))
            }
        }

        if !pending.isEmpty {
            try body(String(decoding: pending, as: UTF8.self))
        }
        // swiftlint:enable optional_data_string_conversion
    }
}
