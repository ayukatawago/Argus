import Testing

@testable import Monitors

@Suite("DiskUsageParser")
struct DiskUsageParserTests {
    @Test("a normal du -sk line parses to bytes")
    func normalLine() {
        #expect(DiskUsageParser.bytes(fromDuOutput: "123456\t/some/path\n") == 123_456 * 1_024)
    }

    @Test("garbage output parses to zero")
    func garbageOutput() {
        #expect(DiskUsageParser.bytes(fromDuOutput: "not a number\t/some/path\n") == 0)
    }

    @Test("empty output parses to zero")
    func emptyOutput() {
        #expect(DiskUsageParser.bytes(fromDuOutput: "") == 0)
    }

    @Test("surrounding whitespace on the size field is trimmed")
    func trimsWhitespace() {
        #expect(DiskUsageParser.bytes(fromDuOutput: "  42  \t/some/path\n") == 42 * 1_024)
    }

    @Test("a zero size parses to zero bytes")
    func zeroSize() {
        #expect(DiskUsageParser.bytes(fromDuOutput: "0\t/empty/dir\n") == 0)
    }
}
