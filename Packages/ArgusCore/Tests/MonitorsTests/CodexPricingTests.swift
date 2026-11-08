import Testing

@testable import Monitors

@Suite("CodexPricing")
struct CodexPricingTests {
    @Test("each listed model has a Standard and a Fast built-in rate, Fast at 2x")
    func tiers() throws {
        #expect(CodexModelRate.knownModels == ["gpt-6-astra", "gpt-6.1-sol", "gpt-6.1-terra", "gpt-6-luna"])
        for model in CodexModelRate.knownModels {
            let standard = try #require(CodexModelRate.defaultRate(forModel: model, tier: .standard))
            let fast = try #require(CodexModelRate.defaultRate(forModel: model, tier: .fast))
            #expect(fast.inputPerMillion == standard.inputPerMillion * 2)
            #expect(fast.cachedInputPerMillion == standard.cachedInputPerMillion * 2)
            #expect(fast.cacheWritePerMillion == standard.cacheWritePerMillion * 2)
            #expect(fast.outputPerMillion == standard.outputPerMillion * 2)
        }
    }

    @Test("published Standard prices for gpt-6-astra and gpt-6-luna")
    func standardValues() {
        #expect(
            CodexModelRate.defaultRate(forModel: "gpt-6-astra", tier: .standard)
                == CodexModelRate(
                    inputPerMillion: 10, cachedInputPerMillion: 1, cacheWritePerMillion: 12.5, outputPerMillion: 50))
        #expect(CodexModelRate.defaultRate(forModel: "gpt-6-luna", tier: .fast)?.outputPerMillion == 1)
    }

    @Test("an unknown model has no built-in rate")
    func unknown() {
        #expect(CodexModelRate.defaultRate(forModel: "gpt-6-nova", tier: .standard) == nil)
    }
}
