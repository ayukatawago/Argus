import ArgusConfigKit
import Monitors

extension CodexUsageSummary {
    /// Summary of `today` priced at the configured tier: the user's override for a model when set,
    /// else the built-in list price, else unpriced (shown as "—").
    init(today: [String: CodexTokenUsage], usage config: ArgusConfig.CodexUsage) {
        let overrides = config.prices(for: config.priceTier)
        let tier = CodexPriceTier(rawValue: config.priceTier.rawValue) ?? .standard
        var rates: [String: CodexModelRate] = [:]
        for model in today.keys {
            if let price = overrides[model] {
                let rate = CodexModelRate(price)
                if !rate.isUnset {
                    rates[model] = rate
                    continue
                }
            }
            rates[model] = CodexModelRate.defaultRate(forModel: model, tier: tier)
        }
        self.init(today: today, rates: rates)
    }
}

extension CodexModelRate {
    init(_ price: ArgusConfig.CodexModelPrice) {
        self.init(
            inputPerMillion: price.inputPerMillion,
            cachedInputPerMillion: price.cachedInputPerMillion,
            cacheWritePerMillion: price.cacheWritePerMillion,
            outputPerMillion: price.outputPerMillion)
    }
}
