import ArgusConfigKit
import Monitors

extension CodexUsageSummary {
    /// Summary of `today` priced from the user's Settings → Usage rates.
    init(today: [String: CodexTokenUsage], prices: [String: ArgusConfig.CodexModelPrice]) {
        self.init(
            today: today,
            rates: prices.mapValues {
                CodexModelRate(
                    inputPerMillion: $0.inputPerMillion,
                    cachedInputPerMillion: $0.cachedInputPerMillion,
                    cacheWritePerMillion: $0.cacheWritePerMillion,
                    outputPerMillion: $0.outputPerMillion)
            })
    }
}
