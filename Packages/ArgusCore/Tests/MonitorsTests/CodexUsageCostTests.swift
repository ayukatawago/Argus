import Testing

@testable import Monitors

@Suite("CodexUsageCost")
struct CodexUsageCostTests {
    @Test("fresh and cached-read input tokens are billed at their own separate rate")
    func cachedDiscountApplied() {
        let usage = CodexTokenUsage(inputTokens: 1_000_000, cachedInputTokens: 800_000, outputTokens: 0)
        let rate = CodexModelRate(inputPerMillion: 10, cachedInputPerMillion: 1, outputPerMillion: 0)
        // 200K fresh @ $10/M + 800K cached @ $1/M = $2.00 + $0.80
        #expect(CodexUsageCost.cost(usage, rate: rate) == 2.80)
    }

    @Test("cache-write tokens are billed at the write rate, not the input rate")
    func cacheWriteBilledAtWriteRate() {
        // 1M input, none of it a cache read, but 300K of it is a cache write — that 300K must be
        // billed at $5/M (write), and only the remaining 700K "fresh" at $10/M (input).
        let usage = CodexTokenUsage(inputTokens: 1_000_000, cacheWriteInputTokens: 300_000)
        let rate = CodexModelRate(inputPerMillion: 10, cacheWritePerMillion: 5)
        #expect(CodexUsageCost.cost(usage, rate: rate) == 7.0 + 1.5)
    }

    @Test("a cache-write token is billed exactly once, never also at the plain input rate")
    func cacheWriteNotDoubleCountedAsInput() {
        let usage = CodexTokenUsage(inputTokens: 100_000, cacheWriteInputTokens: 100_000)
        let allWriteRate = CodexModelRate(inputPerMillion: 10, cacheWritePerMillion: 5)
        // Entirely a cache write: cost must equal the write-rate billing alone, not
        // input-rate + write-rate for the same 100K tokens.
        #expect(CodexUsageCost.cost(usage, rate: allWriteRate) == 100_000.0 / 1_000_000 * 5)
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

    @Test("a rate with only cacheWritePerMillion set is not unset")
    func writeOnlyRateIsNotUnset() {
        #expect(!CodexModelRate(cacheWritePerMillion: 0.01).isUnset)
    }

    @Test("cachedInputTokens exceeding inputTokens clamps fresh input to zero rather than going negative")
    func corruptCachedExceedingInputClampsToZero() {
        let usage = CodexTokenUsage(inputTokens: 100, cachedInputTokens: 500)
        #expect(usage.freshInputTokens == 0)
        let rate = CodexModelRate(inputPerMillion: 10, cachedInputPerMillion: 1, outputPerMillion: 0)
        // Only the (clamped) cached portion should be billed — 500 cached tokens @ $1/M.
        #expect(CodexUsageCost.cost(usage, rate: rate) == 500.0 / 1_000_000 * 1)
    }

    @Test("cacheWriteInputTokens exceeding the uncached remainder clamps fresh input to zero")
    func corruptCacheWriteExceedingUncachedClampsToZero() {
        let usage = CodexTokenUsage(inputTokens: 100, cachedInputTokens: 20, cacheWriteInputTokens: 200)
        #expect(usage.uncachedInputTokens == 80)
        #expect(usage.freshInputTokens == 0)
    }

    @Test("a rate with any nonzero field is not unset")
    func partiallySetRateIsNotUnset() {
        #expect(!CodexModelRate(inputPerMillion: 0.01).isUnset)
    }
}
