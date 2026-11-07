import ArgusSupport
import Foundation
import Testing

@testable import Monitors

@Suite("ClaudeUsageParser")
struct ClaudeUsageParserTests {
    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()
    private static let day = ISO8601Timestamp.parse("2026-11-08T00:00:00Z") ?? Date()

    private func scan(_ lines: [String]) -> [Date: [String: ClaudeTokenUsage]] {
        ClaudeUsageParser.scanDaily(lines: lines, fallbackDay: Self.day, calendar: Self.utc)
    }

    @Test("content-block lines of one message are counted once, not once per block")
    func deduplicatesByMessageAndRequest() {
        let lines = [
            assistant(id: "m1", request: "r1", input: 2, write1h: 100, read: 1000, output: 50),
            assistant(id: "m1", request: "r1", input: 2, write1h: 100, read: 1000, output: 50),
            assistant(id: "m1", request: "r1", input: 2, write1h: 100, read: 1000, output: 50),
            assistant(id: "m2", request: "r2", input: 3, write1h: 0, read: 500, output: 10),
        ]
        let usage = scan(lines)[Self.day]?["claude-sonnet-5-5"]
        #expect(usage?.responseCount == 2)
        #expect(usage?.inputTokens == 5)
        #expect(usage?.cacheWrite1hTokens == 100)
        #expect(usage?.cacheReadTokens == 1500)
        #expect(usage?.outputTokens == 60)
    }

    @Test("the last line of a duplicated message wins")
    func lastDuplicateWins() {
        let lines = [
            assistant(id: "m1", request: "r1", input: 1, output: 5),
            assistant(id: "m1", request: "r1", input: 1, output: 90),
        ]
        #expect(scan(lines)[Self.day]?["claude-sonnet-5-5"]?.outputTokens == 90)
    }

    @Test("a line with neither id is counted rather than merged with its neighbours")
    func linesWithoutIDsAreEachCounted() {
        let lines = [
            assistant(id: nil, request: nil, input: 1, output: 1),
            assistant(id: nil, request: nil, input: 1, output: 1),
        ]
        #expect(scan(lines)[Self.day]?["claude-sonnet-5-5"]?.responseCount == 2)
    }

    @Test("a message replayed into a second file (resumed/forked session) is counted once overall")
    func deduplicatesAcrossFiles() {
        let shared = assistant(id: "m1", request: "r1", input: 4, output: 40)
        let fileA = ClaudeUsageParser.scanRecords(
            lines: [shared, assistant(id: "m2", request: "r2", input: 1, output: 1)],
            fallbackDay: Self.day, calendar: Self.utc)
        let fileB = ClaudeUsageParser.scanRecords(
            lines: [shared, assistant(id: "m3", request: "r3", input: 2, output: 2)],
            fallbackDay: Self.day, calendar: Self.utc)
        let usage = ClaudeUsageParser.aggregate([fileA, fileB])[Self.day]?["claude-sonnet-5-5"]
        #expect(usage?.responseCount == 3)
        #expect(usage?.inputTokens == 7)
        #expect(usage?.outputTokens == 43)
    }

    @Test("the 5m/1h cache-write split is kept")
    func keepsCacheWriteSplit() {
        let lines = [assistant(id: "m1", request: "r1", write5m: 30, write1h: 70)]
        let usage = scan(lines)[Self.day]?["claude-sonnet-5-5"]
        #expect(usage?.cacheWrite5mTokens == 30)
        #expect(usage?.cacheWrite1hTokens == 70)
    }

    @Test("without a cache_creation split, all written tokens count as 5-minute writes")
    func cacheWriteWithoutSplitFallsBackTo5m() {
        let line = """
            {"type":"assistant","timestamp":"2026-11-08T02:00:00.000Z","requestId":"r1",\
            "message":{"id":"m1","model":"claude-opus-4-5-20251101","usage":\
            {"input_tokens":1,"cache_creation_input_tokens":400,"cache_read_input_tokens":0,"output_tokens":1}}}
            """
        let usage = scan([line])[Self.day]?["claude-opus-4-5-20251101"]
        #expect(usage?.cacheWrite5mTokens == 400)
        #expect(usage?.cacheWrite1hTokens == 0)
    }

    @Test("synthetic, non-assistant and unparseable lines are ignored")
    func ignoresNonUsageLines() {
        let lines = [
            assistant(id: "m1", request: "r1", model: "<synthetic>", input: 9, output: 9),
            #"{"type":"user","message":{"usage":{"input_tokens":5}}}"#,
            "not json but mentions \"usage\"",
            #"{"type":"summary"}"#,
        ]
        #expect(scan(lines).isEmpty)
    }

    @Test("two models accumulate into separate buckets")
    func twoModelsSeparate() {
        let lines = [
            assistant(id: "m1", request: "r1", model: "claude-opus-5-5", input: 10, output: 1),
            assistant(id: "m2", request: "r2", model: "claude-sonnet-5-5", input: 20, output: 2),
        ]
        let result = scan(lines)[Self.day]
        #expect(result?["claude-opus-5-5"]?.inputTokens == 10)
        #expect(result?["claude-sonnet-5-5"]?.inputTokens == 20)
    }

    @Test("records either side of local midnight land in different day buckets")
    func splitsAcrossLocalDayBoundary() throws {
        // Asia/Tokyo is UTC+9: 14:50Z and 15:10Z straddle local midnight.
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let lines = [
            assistant(id: "m1", request: "r1", timestamp: "2026-11-08T14:50:00.000Z", input: 1, output: 1),
            assistant(id: "m2", request: "r2", timestamp: "2026-11-08T15:10:00.000Z", input: 2, output: 2),
        ]
        let result = ClaudeUsageParser.scanDaily(lines: lines, fallbackDay: Self.day, calendar: tokyo)
        #expect(result.count == 2)
        #expect(result.values.map { $0["claude-sonnet-5-5"]?.inputTokens }.sorted { ($0 ?? 0) < ($1 ?? 0) } == [1, 2])
    }

    @Test("a Haiku 5.5 request over 100K prompt tokens is tagged with the long-context suffix")
    func tagsHaikuLongContext() {
        let lines = [
            assistant(id: "m1", request: "r1", model: "claude-haiku-5-5", input: 10, read: 150_000, output: 1),
            assistant(id: "m2", request: "r2", model: "claude-haiku-5-5", input: 10, read: 1_000, output: 1),
            assistant(id: "m3", request: "r3", model: "claude-sonnet-5-5", input: 10, read: 150_000, output: 1),
        ]
        let result = scan(lines)[Self.day]
        #expect(result?["claude-haiku-5-5" + ClaudeUsageParser.longContextSuffix]?.cacheReadTokens == 150_000)
        #expect(result?["claude-haiku-5-5"]?.cacheReadTokens == 1_000)
        // Only models with a prompt-size tier are ever tagged.
        #expect(result?["claude-sonnet-5-5"]?.cacheReadTokens == 150_000)
    }

    // MARK: - Fixtures

    private func assistant(
        id: String?, request: String?, model: String = "claude-sonnet-5-5",
        timestamp: String = "2026-11-08T02:00:00.000Z",
        input: Int = 0, write5m: Int = 0, write1h: Int = 0, read: Int = 0, output: Int = 0
    ) -> String {
        let idField = id.map { #""id":"\#($0)","# } ?? ""
        let requestField = request.map { #""requestId":"\#($0)","# } ?? ""
        return """
            {"type":"assistant","timestamp":"\(timestamp)",\(requestField)\
            "message":{\(idField)"model":"\(model)","usage":{"input_tokens":\(input),\
            "cache_creation_input_tokens":\(write5m + write1h),"cache_read_input_tokens":\(read),\
            "output_tokens":\(output),"cache_creation":{"ephemeral_5m_input_tokens":\(write5m),\
            "ephemeral_1h_input_tokens":\(write1h)}}}}
            """
    }
}
