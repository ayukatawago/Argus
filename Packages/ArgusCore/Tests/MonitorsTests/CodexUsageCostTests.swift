import Testing

@testable import Monitors

@Suite("CodexUsageCost")
struct CodexUsageCostTests {
    @Test("uncached and cached input tokens are billed at their own separate rate")
    func cachedDiscountApplied() {
        let usage = CodexTokenUsage(inputTokens: 1_000_000, cachedInputTokens: 800_000, outputTokens: 0)
        let rate = CodexModelRate(inputPerMillion: 10, cachedInputPerMillion: 1, outputPerMillion: 0)
        // 200K uncached @ $10/M + 800K cached @ $1/M = $2.00 + $0.80
        #expect(CodexUsageCost.cost(usage, rate: rate) == 2.80)
    }

    @Test("output tokens are billed at the output rate")
    func outputBilledSeparately() {
        let usage = CodexTokenUsage(outputTokens: 500_000)
        let rate = CodexModelRate(outputPerMillion: 20)
        #expect(CodexUsageCost.cost(usage, rate: rate) == 10.0)
    }

    @Test("an unset rate costs zero")
    func unsetRateCostsZero() {
        let usage = CodexTokenUsage(inputTokens: 1_000_000, outputTokens: 1_000_000)
        #expect(CodexUsageCost.cost(usage, rate: .unset) == 0)
        #expect(CodexModelRate.unset.isUnset)
    }

    @Test("cachedInputTokens exceeding inputTokens clamps uncached to zero rather than going negative")
    func corruptCachedExceedingInputClampsToZero() {
        let usage = CodexTokenUsage(inputTokens: 100, cachedInputTokens: 500)
        #expect(usage.uncachedInputTokens == 0)
        let rate = CodexModelRate(inputPerMillion: 10, cachedInputPerMillion: 1, outputPerMillion: 0)
        // Only the (clamped) cached portion should be billed — 500 cached tokens @ $1/M.
        #expect(CodexUsageCost.cost(usage, rate: rate) == 500.0 / 1_000_000 * 1)
    }

    @Test("a rate with any nonzero field is not unset")
    func partiallySetRateIsNotUnset() {
        #expect(!CodexModelRate(inputPerMillion: 0.01).isUnset)
    }
}
