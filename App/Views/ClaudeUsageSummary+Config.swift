import ArgusConfigKit
import Monitors

extension ClaudeUsageSummary {
    /// Summary of `today` priced from the built-in rates, with the user's Settings → Usage
    /// overrides layered on top.
    init(today: [String: ClaudeTokenUsage], prices: [String: ArgusConfig.ClaudeModelPrice]) {
        self.init(
            today: today,
            overrides: prices.mapValues {
                ClaudeModelRate(
                    inputPerMillion: $0.inputPerMillion,
                    cacheWrite5mPerMillion: $0.cacheWrite5mPerMillion,
                    cacheWrite1hPerMillion: $0.cacheWrite1hPerMillion,
                    cacheReadPerMillion: $0.cacheReadPerMillion,
                    outputPerMillion: $0.outputPerMillion)
            })
    }
}
