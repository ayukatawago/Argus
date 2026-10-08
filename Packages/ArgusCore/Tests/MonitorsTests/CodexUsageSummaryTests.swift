import Testing

@testable import Monitors

@Suite("CodexUsageSummary")
struct CodexUsageSummaryTests {
    private func usage(input: Int = 0, output: Int = 0) -> CodexTokenUsage {
        CodexTokenUsage(
            inputTokens: input, cachedInputTokens: 0, cacheWriteInputTokens: 0, outputTokens: output,
            reasoningOutputTokens: 0, totalTokens: input + output, responseCount: 1)
    }

    private let cheap = CodexModelRate(inputPerMillion: 1, outputPerMillion: 1)
    private let pricey = CodexModelRate(inputPerMillion: 10, outputPerMillion: 10)

    @Test("no activity gives an empty summary with no cost")
    func empty() {
        let summary = CodexUsageSummary(today: [:], rates: [:])
        #expect(summary.isEmpty)
        #expect(summary.totalTokens == 0)
        #expect(summary.totalCost == nil)
        #expect(summary.unpricedModelCount == 0)
    }

    @Test("a priced model gets a cost; the total is the sum across priced models")
    func costs() {
        let summary = CodexUsageSummary(
            today: ["a": usage(input: 1_000_000), "b": usage(output: 1_000_000)], rates: ["a": cheap, "b": pricey])
        #expect(summary.rows.map(\.model) == ["b", "a"])
        #expect(summary.rows.map(\.cost) == [10, 1])
        #expect(summary.totalCost == 11)
        #expect(summary.totalTokens == 2_000_000)
    }

    @Test("a model with no price (or an all-zero one) shows no cost and is counted as unpriced")
    func unpriced() {
        let summary = CodexUsageSummary(
            today: ["priced": usage(input: 1_000_000), "none": usage(input: 5_000_000), "zero": usage(input: 9)],
            rates: ["priced": cheap, "zero": .unset])
        #expect(summary.unpricedModelCount == 2)
        #expect(summary.rows.first?.model == "priced")
        #expect(summary.rows.first { $0.model == "none" }?.cost == nil)
        #expect(summary.totalCost == 1)
    }

    @Test("when nothing is priced there is no total cost, not 0")
    func nothingPriced() {
        let summary = CodexUsageSummary(today: ["a": usage(input: 100)], rates: [:])
        #expect(summary.totalCost == nil)
        #expect(summary.totalTokens == 100)
    }

    @Test("unpriced models sort after priced ones, larger usage first, ties broken by name")
    func ordering() {
        let summary = CodexUsageSummary(
            today: ["z": usage(input: 5), "y": usage(input: 5), "big": usage(input: 50), "priced": usage(input: 1)],
            rates: ["priced": cheap])
        #expect(summary.rows.map(\.model) == ["priced", "big", "y", "z"])
    }
}
