import Foundation
import Testing

@testable import ArgusSupport

@Suite("JSONLCursor")
struct JSONLCursorTests {
    private func strings(_ lines: [Data]) -> [String] {
        lines.map { String(decoding: $0, as: UTF8.self) }
    }

    @Test("complete lines are yielded; blank lines are skipped")
    func yieldsCompleteLines() {
        var cursor = JSONLCursor()
        #expect(strings(cursor.ingest(Data("one\n\ntwo\n".utf8))) == ["one", "two"])
    }

    @Test("an unterminated fragment is held and joined with the next ingest")
    func carriesPartialLine() {
        var cursor = JSONLCursor()
        #expect(cursor.ingest(Data("par".utf8)).isEmpty)
        #expect(strings(cursor.ingest(Data("tial\nnext".utf8))) == ["partial"])
        #expect(strings(cursor.ingest(Data("\n".utf8))) == ["next"])
    }

    @Test("finish() flushes a trailing fragment once")
    func finishFlushes() {
        var cursor = JSONLCursor()
        _ = cursor.ingest(Data("a\ntail".utf8))
        #expect(cursor.finish().map { String(decoding: $0, as: UTF8.self) } == "tail")
        #expect(cursor.finish() == nil)
    }

    @Test("a multibyte codepoint split across two ingests decodes intact")
    func multibyteSplit() {
        var cursor = JSONLCursor()
        let bytes = Array("é\n".utf8)  // 0xC3 0xA9 0x0A
        #expect(cursor.ingest(Data(bytes[0..<1])).isEmpty)
        #expect(strings(cursor.ingest(Data(bytes[1...]))) == ["é"])
    }

    @Test("a line longer than the cap is dropped whole, and the next line is unaffected")
    func oversizedLineDropped() {
        var cursor = JSONLCursor(maxCarryBytes: 8)
        #expect(cursor.ingest(Data("0123456789".utf8)).isEmpty)
        #expect(cursor.ingest(Data("abcdef\nok\n".utf8)).map { String(decoding: $0, as: UTF8.self) } == ["ok"])
    }

    @Test("a single oversized line inside one ingest is dropped")
    func oversizedLineInOneIngest() {
        var cursor = JSONLCursor(maxCarryBytes: 4)
        #expect(strings(cursor.ingest(Data("toolongline\nok\n".utf8))) == ["ok"])
    }

    // MARK: - poll(path:)

    @Test("poll reads only newly appended lines")
    func pollIncremental() throws {
        let path = try makeFile("a\nb\n")
        defer { try? FileManager.default.removeItem(atPath: path) }
        var cursor = JSONLCursor()
        #expect(strings(cursor.poll(path: path)) == ["a", "b"])
        #expect(cursor.poll(path: path).isEmpty)
        try append("c\n", to: path)
        #expect(strings(cursor.poll(path: path)) == ["c"])
    }

    @Test("a starting offset skips existing history")
    func startOffset() throws {
        let path = try makeFile("old\n")
        defer { try? FileManager.default.removeItem(atPath: path) }
        var cursor = JSONLCursor(offset: 4)
        try append("new\n", to: path)
        #expect(strings(cursor.poll(path: path)) == ["new"])
    }

    @Test("truncate-and-regrow below the old offset restarts from the top")
    func truncation() throws {
        let path = try makeFile("long first line\n")
        defer { try? FileManager.default.removeItem(atPath: path) }
        var cursor = JSONLCursor()
        _ = cursor.poll(path: path)
        try Data("x\n".utf8).write(to: URL(fileURLWithPath: path))
        #expect(strings(cursor.poll(path: path)) == ["x"])
    }

    @Test("a file replaced by rename is re-read from the start even if it is larger")
    func replacedByRename() throws {
        let path = try makeFile("a\n")
        let replacement = path + ".new"
        defer {
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.removeItem(atPath: replacement)
        }
        var cursor = JSONLCursor()
        _ = cursor.poll(path: path)
        try Data("first\nsecond\nthird\n".utf8).write(to: URL(fileURLWithPath: replacement))
        _ = try FileManager.default.replaceItemAt(
            URL(fileURLWithPath: path), withItemAt: URL(fileURLWithPath: replacement))
        #expect(strings(cursor.poll(path: path)) == ["first", "second", "third"])
    }

    @Test("a missing file yields nothing and resets, so a recreated file is read from the start")
    func missingFile() throws {
        let path = try makeFile("a\n")
        var cursor = JSONLCursor()
        _ = cursor.poll(path: path)
        try FileManager.default.removeItem(atPath: path)
        #expect(cursor.poll(path: path).isEmpty)
        try Data("b\n".utf8).write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(strings(cursor.poll(path: path)) == ["b"])
    }

    // MARK: - Helpers

    private func makeFile(_ contents: String) throws -> String {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("jsonl-cursor-tests-\(UUID().uuidString).jsonl").path
        try Data(contents.utf8).write(to: URL(fileURLWithPath: path))
        return path
    }

    private func append(_ string: String, to path: String) throws {
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(string.utf8))
    }
}
