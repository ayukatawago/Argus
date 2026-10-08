import ArgusSupport
import Foundation
import Testing

@testable import Monitors

@Suite("CodexUsageParser edge cases")
struct CodexUsageParserEdgeCaseTests {
    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()
    private static let fallback = utc.startOfDay(for: Date(timeIntervalSince1970: 1_790_000_000))

    private func day(_ iso: String) -> Date {
        Self.utc.startOfDay(for: ISO8601Timestamp.parse(iso) ?? .distantPast)
    }

    private func turnContext(_ turnID: String, model: String) -> String {
        #"{"timestamp":"2026-09-30T02:00:00Z","type":"turn_context","payload":{"turn_id":"\#(turnID)","model":"\#(model)"}}"#
    }

    private func record(
        turn: String = "t1", timestamp: String = "2026-09-30T02:00:00Z", usage: String = #""input_tokens":10"#,
        type: String = "token_usage_record"
    ) -> String {
        #"{"timestamp":"\#(timestamp)","type":"\#(type)","payload":{"turn_id":"\#(turn)","usage":{\#(usage)}}}"#
    }

    private func scan(_ lines: [String]) -> [Date: [String: CodexTokenUsage]] {
        CodexUsageParser.scanDaily(lines: lines, fallbackDay: Self.fallback, calendar: Self.utc)
    }

    @Test("a turn_context that arrives after its usage record still supplies the model")
    func contextAfterRecord() {
        let result = scan([record(), turnContext("t1", model: "gpt-late")])
        #expect(result[day("2026-09-30T00:00:00Z")]?["gpt-late"]?.inputTokens == 10)
    }

    @Test("when a turn_id appears in two turn_context lines, the last one wins")
    func duplicateTurnID() {
        let result = scan([turnContext("t1", model: "first"), turnContext("t1", model: "second"), record()])
        #expect(result.values.first?["second"]?.inputTokens == 10)
        #expect(result.values.first?["first"] == nil)
    }

    @Test(
        "fractional seconds of any common width, and numeric offsets, resolve to the right day",
        arguments: [
            "2026-09-30T02:00:00.123Z",
            "2026-09-30T02:00:00.123456Z",
            "2026-09-30T02:00:00.123456789Z",
            "2026-09-30T11:00:00+09:00",
        ])
    func timestampForms(_ stamp: String) {
        let result = scan([turnContext("t1", model: "m"), record(timestamp: stamp)])
        #expect(result[day("2026-09-30T00:00:00Z")]?["m"]?.inputTokens == 10)
    }

    @Test("a +09:00 timestamp is bucketed by its instant, not its wall-clock date")
    func offsetCrossesDay() {
        // 2026-10-01T05:00+09:00 == 2026-09-30T20:00Z, so it belongs to 30 Sept in a UTC calendar.
        let result = scan([turnContext("t1", model: "m"), record(timestamp: "2026-10-01T05:00:00+09:00")])
        #expect(result[day("2026-09-30T00:00:00Z")]?["m"]?.inputTokens == 10)
    }

    @Test("a record with no timestamp falls back to the supplied day")
    func missingTimestamp() {
        let line = #"{"type":"token_usage_record","payload":{"turn_id":"t1","usage":{"input_tokens":4}}}"#
        let result = scan([line])
        #expect(result[Self.fallback]?[CodexUsageParser.unknownModel]?.inputTokens == 4)
    }

    @Test("a line that merely mentions token_usage_record but has another type is ignored")
    func wrongTypeIgnored() {
        #expect(scan([record(type: "response_item")]).isEmpty)
    }

    @Test("booleans, negatives, fractions and out-of-range numbers are not token counts")
    func invalidCounts() {
        let usage =
            #""input_tokens":true,"cached_input_tokens":-5,"output_tokens":1.5,"total_tokens":1e30,"reasoning_output_tokens":7"#
        let total = scan([turnContext("t1", model: "m"), record(usage: usage)]).values.first?["m"]
        #expect(total?.inputTokens == 0)
        #expect(total?.cachedInputTokens == 0)
        #expect(total?.outputTokens == 0)
        #expect(total?.totalTokens == 0)
        #expect(total?.reasoningOutputTokens == 7)
        #expect(total?.responseCount == 1)
    }

    @Test("adding usages saturates instead of trapping on overflow")
    func saturatingAddition() {
        let big = CodexTokenUsage(
            inputTokens: .max, cachedInputTokens: 0, cacheWriteInputTokens: 0, outputTokens: 0,
            reasoningOutputTokens: 0, totalTokens: .max, responseCount: 1)
        let sum = big + big
        #expect(sum.inputTokens == .max)
        #expect(sum.totalTokens == .max)
        #expect(sum.responseCount == 2)
    }

    @Test("du output with a negative or overflowing size never traps or goes negative")
    func diskUsageClamps() {
        #expect(DiskUsageParser.bytes(fromDuOutput: "-4\t/x\n") == 0)
        #expect(DiskUsageParser.bytes(fromDuOutput: "9223372036854775807\t/x\n") == .max)
        #expect(DiskUsageParser.bytes(fromDuOutput: "12\t/x\n") == 12_288)
        #expect(DiskUsageParser.bytes(fromDuOutput: "garbage") == 0)
    }
}
