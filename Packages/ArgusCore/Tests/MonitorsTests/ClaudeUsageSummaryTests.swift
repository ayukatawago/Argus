import Testing

@testable import Monitors

@Suite("ClaudeUsageSummary")
struct ClaudeUsageSummaryTests {
    private func usage(input: Int = 0, output: Int = 0) -> ClaudeTokenUsage {
        ClaudeTokenUsage(inputTokens: input, outputTokens: output, responseCount: 1)
    }

    @Test("no activity gives an empty summary with no cost")
    func empty() {
        let summary = ClaudeUsageSummary(today: [:], overrides: [:])
        #expect(summary.isEmpty)
        #expect(summary.totalTokens == 0)
        #expect(summary.totalCost == nil)
        #expect(summary.unpricedModelCount == 0)
    }

    @Test("a known model is priced from the built-in table with no configuration")
    func defaultsApply() {
        // Sonnet 5.5: $2 in / $10 out per million.
        let summary = ClaudeUsageSummary(
            today: ["claude-sonnet-5-5": usage(input: 1_000_000, output: 1_000_000)], overrides: [:])
        #expect(summary.totalCost == 12)
        #expect(summary.unpricedModelCount == 0)
    }

    @Test("a user override beats the built-in rate")
    func overrideWins() {
        let override = ClaudeModelRate(inputPerMillion: 100, outputPerMillion: 100)
        let summary = ClaudeUsageSummary(
            today: ["claude-sonnet-5-5": usage(input: 1_000_000)], overrides: ["claude-sonnet-5-5": override])
        #expect(summary.totalCost == 100)
    }

    @Test("an all-zero override is ignored and the built-in rate still applies")
    func unsetOverrideFallsBack() {
        let summary = ClaudeUsageSummary(
            today: ["claude-sonnet-5-5": usage(input: 1_000_000)], overrides: ["claude-sonnet-5-5": .unset])
        #expect(summary.totalCost == 2)
    }

    @Test("an unknown model with no override is unpriced, and the total skips it")
    func unknownModelUnpriced() {
        let summary = ClaudeUsageSummary(
            today: ["claude-sonnet-5-5": usage(input: 1_000_000), "mystery": usage(input: 5_000_000)], overrides: [:])
        #expect(summary.unpricedModelCount == 1)
        #expect(summary.totalCost == 2)
        #expect(summary.rows.map(\.model) == ["claude-sonnet-5-5", "mystery"])
        #expect(summary.rows.last?.cost == nil)
    }

    @Test("an unknown model priced by override becomes priced")
    func overridePricesUnknown() {
        let override = ClaudeModelRate(inputPerMillion: 1)
        let summary = ClaudeUsageSummary(today: ["mystery": usage(input: 1_000_000)], overrides: ["mystery": override])
        #expect(summary.totalCost == 1)
        #expect(summary.unpricedModelCount == 0)
    }

    @Test("rows are ordered most expensive first")
    func ordering() {
        let summary = ClaudeUsageSummary(
            today: [
                "claude-haiku-4-5": usage(input: 1_000_000),
                "claude-opus-4-1": usage(input: 1_000_000),
            ], overrides: [:])
        #expect(summary.rows.map(\.model) == ["claude-opus-4-1", "claude-haiku-4-5"])
    }
}
