import Testing

@testable import Monitors

@Suite("ClaudeUsageCost")
struct ClaudeUsageCostTests {
    @Test("each of the five token kinds is billed at its own rate, with nothing subtracted")
    func costMath() {
        let usage = ClaudeTokenUsage(
            inputTokens: 1_000_000, cacheWrite5mTokens: 1_000_000, cacheWrite1hTokens: 1_000_000,
            cacheReadTokens: 1_000_000, outputTokens: 1_000_000, responseCount: 1)
        let rate = ClaudeModelRate(
            inputPerMillion: 1, cacheWrite5mPerMillion: 2, cacheWrite1hPerMillion: 3,
            cacheReadPerMillion: 4, outputPerMillion: 5)
        #expect(ClaudeUsageCost.cost(usage, rate: rate) == 15)
    }

    @Test("a realistic Sonnet 5.5 request prices out to the published rates")
    func sonnet55Example() throws {
        let usage = ClaudeTokenUsage(
            inputTokens: 2, cacheWrite1hTokens: 7_581, cacheReadTokens: 96_669, outputTokens: 1_355)
        let rate = try #require(ClaudeModelRate.defaultRate(forModel: "claude-sonnet-5-5"))
        // $2 input, $4 1h cache write, $0.10 cache read, $10 output, all per million.
        let input: Double = 2 * 2.0
        let write: Double = 7_581 * 4.0
        let read: Double = 96_669 * 0.1
        let output: Double = 1_355 * 10.0
        let expected: Double = (input + write + read + output) / 1_000_000
        #expect(abs(ClaudeUsageCost.cost(usage, rate: rate) - expected) < 1e-12)
    }

    @Test("a dated model ID matches its undated prefix")
    func datedIDMatches() {
        #expect(ClaudeModelRate.defaultRate(forModel: "claude-opus-4-5-20251101")?.inputPerMillion == 5)
        #expect(ClaudeModelRate.defaultRate(forModel: "claude-sonnet-4-6-20260101")?.outputPerMillion == 15)
    }

    @Test("the longest matching prefix wins, so Opus 5.5 is never read as Opus 5")
    func longestPrefixWins() {
        #expect(ClaudeModelRate.defaultRate(forModel: "claude-opus-5-5")?.inputPerMillion == 4)
        #expect(ClaudeModelRate.defaultRate(forModel: "claude-opus-5")?.inputPerMillion == 5)
        #expect(ClaudeModelRate.defaultRate(forModel: "claude-opus-4-1-20250805")?.inputPerMillion == 15)
        #expect(ClaudeModelRate.defaultRate(forModel: "claude-opus-4-8")?.inputPerMillion == 5)
        #expect(ClaudeModelRate.defaultRate(forModel: "claude-sonnet-5-5")?.inputPerMillion == 2)
    }

    @Test("cache-read rates follow each model's published multiplier")
    func cacheReadRates() {
        #expect(ClaudeModelRate.defaultRate(forModel: "claude-fable-5-1")?.cacheReadPerMillion == 0.25)
        #expect(ClaudeModelRate.defaultRate(forModel: "claude-fable-5")?.cacheReadPerMillion == 1)
        #expect(ClaudeModelRate.defaultRate(forModel: "claude-opus-5-5")?.cacheReadPerMillion == 0.2)
        #expect(ClaudeModelRate.defaultRate(forModel: "claude-haiku-4-5")?.cacheReadPerMillion == 0.1)
    }

    @Test("the Haiku 5.5 long-context suffix selects the higher tier; other models ignore it")
    func haikuLongContextTier() {
        let base = ClaudeModelRate.defaultRate(forModel: "claude-haiku-5-5")
        let long = ClaudeModelRate.defaultRate(forModel: "claude-haiku-5-5" + ClaudeUsageParser.longContextSuffix)
        #expect(base?.inputPerMillion == 0.1)
        #expect(long?.inputPerMillion == 0.5)
        #expect(long?.outputPerMillion == 2.5)
    }

    @Test("both Haiku 5.5 settings rows resolve to a built-in rate, the long tier priced higher")
    func haiku55SettingsRowsArePriced() throws {
        #expect(ClaudeModelRate.haiku55Models.count == 2)
        let rates = try ClaudeModelRate.haiku55Models.map { try #require(ClaudeModelRate.defaultRate(forModel: $0)) }
        #expect(rates[0].outputPerMillion == 0.5)
        #expect(rates[1].outputPerMillion == 2.5)
    }

    @Test("an unrecognized model has no built-in rate")
    func unknownModel() {
        #expect(ClaudeModelRate.defaultRate(forModel: "gpt-6-luna") == nil)
        #expect(ClaudeModelRate.defaultRate(forModel: "") == nil)
    }
}
