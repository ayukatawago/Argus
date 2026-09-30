import ArgusSupport
import Foundation
import Testing

@testable import Monitors

@Suite("CodexUsageParser")
struct CodexUsageParserTests {
    private static let utc = Calendar(identifier: .gregorian).withUTC()
    private static let day = ISO8601Timestamp.parse("2026-09-30T00:00:00Z") ?? Date()

    @Test("a usage record joins its model via turn_id")
    func joinsViaTurnID() {
        let lines = [
            turnContext(turnID: "t1", model: "gpt-6-luna"),
            usageRecord(turnID: "t1", rootTurnID: "t1", timestamp: "2026-09-30T02:00:00Z", input: 100, output: 10),
        ]
        let result = CodexUsageParser.scanDaily(lines: lines, fallbackDay: Self.day, calendar: Self.utc)
        #expect(result[Self.day]?["gpt-6-luna"]?.inputTokens == 100)
        #expect(result[Self.day]?["gpt-6-luna"]?.outputTokens == 10)
    }

    @Test("falls back to root_turn_id when turn_id has no matching turn_context")
    func fallsBackToRootTurnID() {
        let lines = [
            turnContext(turnID: "root1", model: "gpt-6-sol"),
            usageRecord(turnID: "sub1", rootTurnID: "root1", timestamp: "2026-09-30T02:00:00Z", input: 50, output: 5),
        ]
        let result = CodexUsageParser.scanDaily(lines: lines, fallbackDay: Self.day, calendar: Self.utc)
        #expect(result[Self.day]?["gpt-6-sol"]?.inputTokens == 50)
    }

    @Test("a record with no matching turn_context is bucketed under unknownModel, not dropped")
    func unmatchedRecordFallsBackToUnknown() {
        let lines = [
            usageRecord(turnID: "ghost", rootTurnID: "ghost", timestamp: "2026-09-30T02:00:00Z", input: 7, output: 1)
        ]
        let result = CodexUsageParser.scanDaily(lines: lines, fallbackDay: Self.day, calendar: Self.utc)
        #expect(result[Self.day]?[CodexUsageParser.unknownModel]?.inputTokens == 7)
    }

    @Test("two models in one file accumulate into separate buckets")
    func twoModelsAccumulateSeparately() {
        let lines = [
            turnContext(turnID: "t1", model: "gpt-6-luna"),
            turnContext(turnID: "t2", model: "gpt-6-sol"),
            usageRecord(turnID: "t1", rootTurnID: "t1", timestamp: "2026-09-30T02:00:00Z", input: 100, output: 10),
            usageRecord(turnID: "t2", rootTurnID: "t2", timestamp: "2026-09-30T02:05:00Z", input: 200, output: 20),
            usageRecord(turnID: "t1", rootTurnID: "t1", timestamp: "2026-09-30T02:10:00Z", input: 50, output: 5),
        ]
        let result = CodexUsageParser.scanDaily(lines: lines, fallbackDay: Self.day, calendar: Self.utc)
        #expect(result[Self.day]?["gpt-6-luna"]?.inputTokens == 150)
        #expect(result[Self.day]?["gpt-6-luna"]?.responseCount == 2)
        #expect(result[Self.day]?["gpt-6-sol"]?.inputTokens == 200)
    }

    @Test("records on either side of local midnight land in different day buckets")
    func splitsAcrossLocalDayBoundary() {
        // Asia/Tokyo is UTC+9, so 14:50Z and 15:10Z on the same UTC date fall either side of
        // local midnight — this must key off the caller's calendar, not the raw UTC date.
        guard let tokyo = TimeZone(identifier: "Asia/Tokyo") else {
            Issue.record("Asia/Tokyo timezone unavailable")
            return
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tokyo

        let lines = [
            turnContext(turnID: "t1", model: "gpt-6-luna"),
            usageRecord(turnID: "t1", rootTurnID: "t1", timestamp: "2026-09-29T14:50:00Z", input: 1, output: 0),
            usageRecord(turnID: "t1", rootTurnID: "t1", timestamp: "2026-09-29T15:10:00Z", input: 2, output: 0),
        ]
        let result = CodexUsageParser.scanDaily(lines: lines, fallbackDay: Self.day, calendar: calendar)
        #expect(result.count == 2)
        let totals = result.values.flatMap { $0.values.map(\.inputTokens) }.sorted()
        #expect(totals == [1, 2])
    }

    @Test("a record with an unparseable timestamp buckets under fallbackDay")
    func unparseableTimestampUsesFallbackDay() {
        let lines = [
            turnContext(turnID: "t1", model: "gpt-6-luna"),
            usageRecord(turnID: "t1", rootTurnID: "t1", timestamp: "not-a-date", input: 3, output: 0),
        ]
        let result = CodexUsageParser.scanDaily(lines: lines, fallbackDay: Self.day, calendar: Self.utc)
        #expect(result[Self.day]?["gpt-6-luna"]?.inputTokens == 3)
    }

    @Test("summed usage across records equals the file's own thread_token_usage total")
    func summedUsageMatchesThreadTotal() {
        let lines = [
            turnContext(turnID: "t1", model: "gpt-6-luna"),
            usageRecord(turnID: "t1", rootTurnID: "t1", timestamp: "2026-09-30T02:00:00Z", input: 21_895, output: 236),
            usageRecord(turnID: "t1", rootTurnID: "t1", timestamp: "2026-09-30T02:05:00Z", input: 58_204, output: 500),
        ]
        let result = CodexUsageParser.scanDaily(lines: lines, fallbackDay: Self.day, calendar: Self.utc)
        #expect(result[Self.day]?["gpt-6-luna"]?.inputTokens == 80_099)
        #expect(result[Self.day]?["gpt-6-luna"]?.outputTokens == 736)
    }

    @Test("a non-JSON or truncated line is skipped without aborting the scan")
    func malformedLineIsSkipped() {
        let lines = [
            turnContext(turnID: "t1", model: "gpt-6-luna"),
            "{\"type\":\"token_usage_record\",\"payload\":{\"truncated",
            usageRecord(turnID: "t1", rootTurnID: "t1", timestamp: "2026-09-30T02:00:00Z", input: 9, output: 1),
        ]
        let result = CodexUsageParser.scanDaily(lines: lines, fallbackDay: Self.day, calendar: Self.utc)
        #expect(result[Self.day]?["gpt-6-luna"]?.inputTokens == 9)
        #expect(result[Self.day]?["gpt-6-luna"]?.responseCount == 1)
    }

    // MARK: - Fixture builders (real rollout line shapes, trimmed to what the parser reads)

    private func turnContext(turnID: String, model: String) -> String {
        """
        {"timestamp":"2026-09-30T02:12:36.002Z","type":"turn_context",\
        "payload":{"turn_id":"\(turnID)","model":"\(model)"}}
        """
    }

    private func usageRecord(turnID: String, rootTurnID: String, timestamp: String, input: Int, output: Int) -> String {
        """
        {"timestamp":"\(timestamp)","type":"token_usage_record",\
        "payload":{"turn_id":"\(turnID)","root_turn_id":"\(rootTurnID)",\
        "usage":{"input_tokens":\(input),"cached_input_tokens":0,"cache_write_input_tokens":0,\
        "output_tokens":\(output),"reasoning_output_tokens":0,"total_tokens":\(input + output)}}}
        """
    }
}

extension Calendar {
    fileprivate func withUTC() -> Calendar {
        var copy = self
        copy.timeZone = TimeZone(identifier: "UTC") ?? .current
        return copy
    }
}
