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

        // The cursor carries an unterminated trailing fragment across chunk boundaries — a chunk edge
        // is a byte-count cutoff, not a line boundary. Lines are cut at `\n`, which can never split a
        // UTF-8 multibyte sequence, so `String(decoding:as:)` below is lossless (and, unlike the
        // failable `String(bytes:encoding:)`, never fails).
        var cursor = JSONLCursor(maxCarryBytes: .max)
        // swiftlint:disable optional_data_string_conversion
        while true {
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty { break }
            for line in cursor.ingest(chunk) {
                try body(String(decoding: line, as: UTF8.self))
            }
        }

        if let last = cursor.finish() {
            try body(String(decoding: last, as: UTF8.self))
        }
        // swiftlint:enable optional_data_string_conversion
    }
}
