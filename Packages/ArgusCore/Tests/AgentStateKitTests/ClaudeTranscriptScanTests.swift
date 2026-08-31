import Foundation
import Testing

@testable import AgentStateKit

/// Covers `ClaudeTranscriptParser.scan(tail:)` (state + activity-timestamp extraction),
/// `extractEntrypoint`, and `splitAtLastNewline` — split out of `ClaudeTranscriptParserTests` to
/// stay under SwiftLint's type_body_length limit.
@Suite("ClaudeTranscriptParser.scan")
struct ClaudeTranscriptScanTests {
    // MARK: - inferState additions: isMeta and the current CLI's system/local_command shape

    @Test("an isMeta user entry (e.g. a skill-loading notice) is not decisive")
    func metaUserEntryIsNotDecisive() {
        let tail = """
            {"type":"user","isMeta":true,"message":{"role":"user",\
            "content":"Base directory for this skill: /Users/taku/.claude/skills/foo"}}
            """
        #expect(ClaudeTranscriptParser.inferState(fromTail: tail) == nil)
    }

    @Test("an isMeta user entry appended after end_turn still resolves to done, not running")
    func metaUserEntryAfterEndTurnStillResolvesToDone() {
        let tail = """
            {"type":"assistant","message":{"stop_reason":"end_turn"}}
            {"type":"user","isMeta":true,"message":{"role":"user",\
            "content":"[Image: original 6360x3496, downscaled to 1512x832]"}}
            """
        #expect(ClaudeTranscriptParser.inferState(fromTail: tail) == "done")
    }

    @Test("the current CLI's system/local_command stdout echo maps to idle")
    func systemLocalCommandStdoutMapsToIdle() {
        let tail = """
            {"type":"system","subtype":"local_command",\
            "content":"<local-command-stdout>Compacted (ctrl+o to see full summary)</local-command-stdout>"}
            """
        #expect(ClaudeTranscriptParser.inferState(fromTail: tail) == "idle")
    }

    // MARK: - extractEntrypoint

    @Test("finds entrypoint on the first line that carries one, skipping earlier bookkeeping lines")
    func findsEntrypointSkippingBookkeepingLines() {
        let header = """
            {"type":"mode","mode":"normal","sessionId":"abc"}
            {"type":"file-history-snapshot","messageId":"1","snapshot":{}}
            {"type":"user","message":{"role":"user","content":"hi"},"cwd":"/Users/taku/app",\
            "entrypoint":"sdk-cli"}
            """
        #expect(ClaudeTranscriptParser.extractEntrypoint(from: header) == "sdk-cli")
    }

    @Test("returns nil when no line carries an entrypoint")
    func noEntrypointReturnsNil() {
        let header = #"{"type":"user","message":{"role":"user","content":"hi"},"cwd":"/Users/taku/app"}"#
        #expect(ClaudeTranscriptParser.extractEntrypoint(from: header) == nil)
    }

    // MARK: - scan

    @Test("scan returns the newest in-file timestamp even when the last lines carry none")
    func scanReturnsNewestTimestampPastUntimestampedTail() {
        let tail = """
            {"type":"assistant","timestamp":"2026-08-30T12:00:00.000Z","message":{"stop_reason":"end_turn"}}
            {"type":"last-prompt","lastPrompt":"go"}
            {"type":"ai-title","aiTitle":"Fix bug"}
            {"type":"mode","mode":"normal"}
            """
        let scan = ClaudeTranscriptParser.scan(tail: tail)
        #expect(scan.state == "done")
        #expect(scan.lastActivity == parseISO8601("2026-08-30T12:00:00.000Z"))
    }

    @Test("scan takes the max timestamp over the window, not the last line's, across the /compact reordering")
    func scanTakesMaxTimestampNotLastLines() {
        let tail = """
            {"type":"system","subtype":"compact_boundary","timestamp":"2026-08-30T12:00:00.000Z"}
            {"type":"user","isCompactSummary":true,"timestamp":"2026-08-30T12:00:01.500Z",\
            "message":{"role":"user","content":"continued from a previous conversation"}}
            {"type":"user","isMeta":true,"timestamp":"2026-08-30T12:00:00.200Z",\
            "message":{"role":"user","content":"<local-command-caveat>Caveat: …</local-command-caveat>"}}
            {"type":"user","timestamp":"2026-08-30T12:00:00.300Z",\
            "message":{"role":"user","content":"<command-name>/compact</command-name>"}}
            {"type":"system","subtype":"local_command","timestamp":"2026-08-30T12:00:00.400Z",\
            "content":"<local-command-stdout>Compacted (ctrl+o to see full summary)</local-command-stdout>"}
            """
        let scan = ClaudeTranscriptParser.scan(tail: tail)
        #expect(scan.state == "idle")
        #expect(scan.lastActivity == parseISO8601("2026-08-30T12:00:01.500Z"))
    }

    @Test("scan returns lastActivity nil for a window of only untimestamped bookkeeping lines")
    func scanReturnsNilActivityForBookkeepingOnlyWindow() {
        let tail = """
            {"type":"mode","mode":"normal"}
            {"type":"permission-mode","permissionMode":"plan"}
            """
        let scan = ClaudeTranscriptParser.scan(tail: tail)
        #expect(scan.state == nil)
        #expect(scan.lastActivity == nil)
    }

    @Test("scan(tail:).state matches inferState(fromTail:) for a decisive tail")
    func scanStateDelegatesToInferState() {
        let tail = #"{"type":"assistant","message":{"stop_reason":"end_turn"}}"#
        #expect(ClaudeTranscriptParser.scan(tail: tail).state == ClaudeTranscriptParser.inferState(fromTail: tail))
    }

    @Test("an escaped timestamp field nested inside a tool_result's echoed text is not read as an entry timestamp")
    func escapedTimestampInsideToolResultIsNotReadAsEntryTimestamp() {
        let tail = """
            {"type":"user","timestamp":"2026-08-30T12:00:00.000Z","message":{"role":"user",\
            "content":[{"type":"tool_result","content":"log line: \\"timestamp\\":\\"2099-01-01T00:00:00.000Z\\""}]}}
            """
        #expect(ClaudeTranscriptParser.scan(tail: tail).lastActivity == parseISO8601("2026-08-30T12:00:00.000Z"))
    }

    @Test("a timestamp without fractional seconds still parses")
    func timestampWithoutFractionalSecondsParses() {
        let tail = #"{"type":"user","timestamp":"2026-08-30T12:00:00Z","message":{"role":"user","content":"hi"}}"#
        #expect(ClaudeTranscriptParser.scan(tail: tail).lastActivity == parseISO8601("2026-08-30T12:00:00Z"))
    }

    // MARK: - splitAtLastNewline

    @Test("data with no newline is entirely the remainder")
    func splitWithNoNewlineIsEntirelyRemainder() {
        let data = Data("no newline here".utf8)
        let (complete, remainder) = ClaudeTranscriptParser.splitAtLastNewline(data)
        #expect(complete.isEmpty)
        #expect(remainder == data)
    }

    @Test("data ending in a newline has an empty remainder")
    func splitEndingInNewlineHasEmptyRemainder() {
        let data = Data("one line\n".utf8)
        let (complete, remainder) = ClaudeTranscriptParser.splitAtLastNewline(data)
        #expect(complete == data)
        #expect(remainder.isEmpty)
    }

    @Test("a complete multi-byte line plus a partial trailing line round-trips intact through the remainder")
    func multiByteLinePlusPartialTrailingLineRoundTrips() {
        let completeLine = "{\"type\":\"user\",\"message\":{\"content\":\"あ\"}}\n"
        let partialTrailer = "{\"type\":\"user\",\"mess"
        let data = Data((completeLine + partialTrailer).utf8)
        let (complete, remainder) = ClaudeTranscriptParser.splitAtLastNewline(data)
        #expect(String(bytes: complete, encoding: .utf8) == completeLine)
        #expect(String(bytes: remainder, encoding: .utf8) == partialTrailer)
    }

    @Test("a decisive line split across two read windows is missed by the first and found once carried into the second")
    func decisiveLineSplitAcrossTwoWindowsIsDetectedOnceCarried() {
        let fullLine = Data((#"{"type":"assistant","message":{"stop_reason":"end_turn"}}"# + "\n").utf8)
        let splitPoint = fullLine.count - 10
        let firstWindow = Data(fullLine.prefix(splitPoint))
        let secondWindow = Data(fullLine.suffix(from: splitPoint))

        let (firstComplete, firstRemainder) = ClaudeTranscriptParser.splitAtLastNewline(firstWindow)
        #expect(firstComplete.isEmpty)
        #expect(ClaudeTranscriptParser.scan(tail: String(bytes: firstComplete, encoding: .utf8) ?? "").state == nil)

        let (secondComplete, secondRemainder) = ClaudeTranscriptParser.splitAtLastNewline(firstRemainder + secondWindow)
        #expect(secondRemainder.isEmpty)
        let secondText = String(bytes: secondComplete, encoding: .utf8) ?? ""
        #expect(ClaudeTranscriptParser.scan(tail: secondText).state == "done")
    }

    private func parseISO8601(_ value: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: value) { return date }
        let withoutFraction = ISO8601DateFormatter()
        withoutFraction.formatOptions = [.withInternetDateTime]
        return withoutFraction.date(from: value)
    }
}
