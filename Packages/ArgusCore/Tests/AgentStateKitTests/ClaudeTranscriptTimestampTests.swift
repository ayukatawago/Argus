import ArgusSupport
import Foundation
import Testing

@testable import AgentStateKit

@Suite("ClaudeTranscriptParser timestamps and header scans")
struct ClaudeTranscriptTimestampTests {
    private func line(type: String = "user", stamp: String) -> String {
        #"{"type":"\#(type)","message":{"role":"user","content":"hi"},"timestamp":"\#(stamp)"}"#
    }

    @Test("newest activity is chosen by instant, not by string order")
    func newestByInstant() {
        // Lexically "…:00Z" > "…:00.500Z" (because 'Z' > '.'), but the fractional one is later.
        let tail = [line(stamp: "2026-01-01T00:00:00Z"), line(stamp: "2026-01-01T00:00:00.500Z")].joined(
            separator: "\n")
        let scan = ClaudeTranscriptParser.scan(tail: tail)
        #expect(scan.lastActivity == ISO8601Timestamp.parse("2026-01-01T00:00:00.500Z"))
    }

    @Test("a +09:00 offset is compared as the instant it denotes")
    func offsetsCompareAsInstants() {
        // 2026-01-01T09:30+09:00 is 00:30Z — earlier than 01:00Z although it sorts after it as text.
        let tail = [line(stamp: "2026-01-01T01:00:00Z"), line(stamp: "2026-01-01T09:30:00+09:00")].joined(
            separator: "\n")
        #expect(ClaudeTranscriptParser.scan(tail: tail).lastActivity == ISO8601Timestamp.parse("2026-01-01T01:00:00Z"))
    }

    @Test("a nested timestamp key before the real one does not hijack the line's activity time")
    func nestedTimestampIgnored() {
        let nested =
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","input":{"timestamp":"1999-01-01T00:00:00Z"}}]},"timestamp":"2026-01-01T00:00:00Z"}"#
        #expect(
            ClaudeTranscriptParser.scan(tail: nested).lastActivity == ISO8601Timestamp.parse("2026-01-01T00:00:00Z"))
    }

    @Test("a nested timestamp key after the real one is ignored too")
    func nestedTimestampAfterIgnored() {
        let nested =
            #"{"type":"user","timestamp":"2026-01-01T00:00:00Z","toolUseResult":{"timestamp":"2030-01-01T00:00:00Z"}}"#
        #expect(
            ClaudeTranscriptParser.scan(tail: nested).lastActivity == ISO8601Timestamp.parse("2026-01-01T00:00:00Z"))
    }

    @Test("extractCwd decodes an escaped quote in the path")
    func cwdWithQuote() {
        let header = #"{"type":"mode"}"# + "\n" + #"{"cwd":"/Users/me/we\"ird","sessionId":"s"}"#
        #expect(ClaudeTranscriptParser.extractCwd(from: header) == #"/Users/me/we"ird"#)
    }

    @Test("extractEntrypoint reads the value")
    func entrypoint() {
        #expect(ClaudeTranscriptParser.extractEntrypoint(from: #"{"entrypoint":"sdk-cli"}"#) == "sdk-cli")
    }

    @Test("Codex extractCwd/extractThreadSource decode escapes")
    func codexHeader() {
        let header = #"{"payload":{"cwd":"/a/\"b","thread_source":"subagent"}}"#
        #expect(CodexSessionParser.extractCwd(from: header) == #"/a/"b"#)
        #expect(CodexSessionParser.extractThreadSource(from: header) == "subagent")
    }
}
