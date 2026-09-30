import Foundation
import Testing

@testable import ArgusSupport

@Suite("JSONLFileReader")
struct JSONLFileReaderTests {
    @Test("every line is yielded in order")
    func yieldsEveryLine() throws {
        let url = try Self.write("one\ntwo\nthree\n")
        defer { try? FileManager.default.removeItem(at: url) }

        var lines: [String] = []
        try JSONLFileReader.forEachLine(at: url) { lines.append($0) }
        #expect(lines == ["one", "two", "three"])
    }

    @Test("a file with no trailing newline still yields its last line")
    func noTrailingNewline() throws {
        let url = try Self.write("one\ntwo")
        defer { try? FileManager.default.removeItem(at: url) }

        var lines: [String] = []
        try JSONLFileReader.forEachLine(at: url) { lines.append($0) }
        #expect(lines == ["one", "two"])
    }

    @Test("an empty file yields nothing")
    func emptyFile() throws {
        let url = try Self.write("")
        defer { try? FileManager.default.removeItem(at: url) }

        var lines: [String] = []
        try JSONLFileReader.forEachLine(at: url) { lines.append($0) }
        #expect(lines.isEmpty)
    }

    @Test("a line spanning a chunk boundary is reassembled whole")
    func lineSpanningChunkBoundary() throws {
        // "aaa\n" is 4 bytes; a chunk size of 4 lands the boundary exactly mid-way through the
        // next line, which must still be glued back together rather than yielded in two pieces.
        let content = "aaa\n" + String(repeating: "b", count: 10) + "\nccc\n"
        let url = try Self.write(content)
        defer { try? FileManager.default.removeItem(at: url) }

        var lines: [String] = []
        try JSONLFileReader.forEachLine(at: url, chunkSize: 4) { lines.append($0) }
        #expect(lines == ["aaa", String(repeating: "b", count: 10), "ccc"])
    }

    @Test("a multibyte UTF-8 codepoint split across a chunk boundary decodes intact")
    func multibyteCodepointSplitAcrossChunk() throws {
        // "é" (U+00E9) is 2 bytes in UTF-8; a chunk size landing between those two bytes would
        // corrupt it if the reader cut on byte count rather than on the last complete newline.
        let content = "café\nbar\n"
        let url = try Self.write(content)
        defer { try? FileManager.default.removeItem(at: url) }

        var lines: [String] = []
        try JSONLFileReader.forEachLine(at: url, chunkSize: 5) { lines.append($0) }
        #expect(lines == ["café", "bar"])
    }

    private static func write(_ string: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("jsonl-file-reader-tests-\(UUID().uuidString).jsonl")
        try Data(string.utf8).write(to: url)
        return url
    }
}
