import Foundation
import Testing

@testable import ArgusSupport

private struct TimeoutError: Error {}

/// Collects lines yielded by a JSONLTailer from a background Task, with a poll-based wait so
/// tests don't need their own ad-hoc sleep-and-hope.
private actor LineCollector {
    private(set) var lines: [Data] = []

    func add(_ data: Data) {
        lines.append(data)
    }

    func waitForCount(_ count: Int, timeoutNanoseconds: UInt64 = 2_000_000_000) async throws -> [Data] {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while lines.count < count {
            guard DispatchTime.now().uptimeNanoseconds < deadline else { throw TimeoutError() }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        return lines
    }
}

@Suite("JSONLTailer")
struct JSONLTailerTests {
    // A short poll interval keeps these tests fast without being so short they're flaky.
    private static let testPollIntervalNanoseconds: UInt64 = 5_000_000

    @Test("an appended line is emitted")
    func appendedLineIsEmitted() async throws {
        let path = try Self.makeEmptyFile()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let collector = LineCollector()
        let task = Self.startCollecting(path: path, into: collector)
        defer { task.cancel() }

        try Self.append("hello\n", to: path)

        let lines = try await collector.waitForCount(1)
        #expect(String(data: lines[0], encoding: .utf8) == "hello")
    }

    @Test("multiple lines written at once are each emitted separately")
    func multipleLinesInOneWrite() async throws {
        let path = try Self.makeEmptyFile()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let collector = LineCollector()
        let task = Self.startCollecting(path: path, into: collector)
        defer { task.cancel() }

        try Self.append("one\ntwo\nthree\n", to: path)

        let lines = try await collector.waitForCount(3)
        #expect(lines.map { String(data: $0, encoding: .utf8) } == ["one", "two", "three"])
    }

    @Test("a line written in two halves is held until its newline arrives, then emitted whole")
    func partialLineIsBufferedUntilNewline() async throws {
        let path = try Self.makeEmptyFile()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let collector = LineCollector()
        let task = Self.startCollecting(path: path, into: collector)
        defer { task.cancel() }

        try Self.append("partial", to: path)
        try await Task.sleep(nanoseconds: 40_000_000)
        #expect(await collector.lines.isEmpty)

        try Self.append(" line\n", to: path)
        let lines = try await collector.waitForCount(1)
        #expect(String(data: lines[0], encoding: .utf8) == "partial line")
    }

    @Test("truncating the file resets the read offset to zero")
    func truncationResetsOffset() async throws {
        let path = try Self.makeEmptyFile()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let collector = LineCollector()
        let task = Self.startCollecting(path: path, into: collector)
        defer { task.cancel() }

        try Self.append("before\n", to: path)
        _ = try await collector.waitForCount(1)

        // Simulate log rotation/truncation, then write a line shorter than the prior offset —
        // if the offset weren't reset, this would look like "no new bytes" forever.
        try Data().write(to: URL(fileURLWithPath: path))
        try Self.append("after\n", to: path)

        let lines = try await collector.waitForCount(2)
        #expect(String(data: lines[1], encoding: .utf8) == "after")
    }

    @Test("a line containing invalid UTF-8 is dropped on its own; its neighbours survive")
    func invalidUTF8DropsOnlyThatLine() async throws {
        let path = try Self.makeEmptyFile()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let collector = LineCollector()
        let task = Self.startCollecting(path: path, into: collector)
        defer { task.cancel() }

        // 0xFF is never valid UTF-8, anywhere in a byte stream.
        var data = Data("before\n".utf8)
        data.append(contentsOf: [0x62, 0xFF, 0x0A])
        data.append(Data("after\n".utf8))
        try Self.appendData(data, to: path)

        let lines = try await collector.waitForCount(2)
        #expect(lines.map { String(data: $0, encoding: .utf8) } == ["before", "after"])
    }

    // MARK: - Helpers

    private static func startCollecting(path: String, into collector: LineCollector) -> Task<Void, Never> {
        Task {
            for await line in JSONLTailer(path: path, pollIntervalNanoseconds: testPollIntervalNanoseconds).lines() {
                await collector.add(line)
            }
        }
    }

    private static func makeEmptyFile() throws -> String {
        let path =
            FileManager.default.temporaryDirectory
            .appendingPathComponent("jsonl-tailer-tests-\(UUID().uuidString).jsonl")
            .path
        FileManager.default.createFile(atPath: path, contents: nil)
        return path
    }

    private static func append(_ string: String, to path: String) throws {
        try appendData(Data(string.utf8), to: path)
    }

    private static func appendData(_ data: Data, to path: String) throws {
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }
}
