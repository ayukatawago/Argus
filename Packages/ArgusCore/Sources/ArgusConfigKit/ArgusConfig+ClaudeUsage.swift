import Foundation

// File-level coding keys for the same one-level-nesting reason as `ArgusConfig+CodexUsage.swift`.
private enum ClaudeUsageCodingKeys: String, CodingKey {
    case refreshIntervalSeconds, modelPrices
}

private enum ClaudeModelPriceCodingKeys: String, CodingKey {
    case inputPerMillion, cacheWrite5mPerMillion, cacheWrite1hPerMillion, cacheReadPerMillion, outputPerMillion
}

extension ArgusConfig {
    /// Config for the toolbar's daily Claude token/cost usage chip. Unlike Codex, Anthropic
    /// publishes its prices, so the app ships built-in rates (`ClaudeModelRate.defaultRate`) and
    /// `modelPrices` holds only the user's *overrides* on top of them.
    public struct ClaudeUsage: Codable, Equatable, Sendable {
        public var refreshIntervalSeconds: Double = 30
        /// USD price per 1M tokens, keyed by the model name in a transcript's `message.model`
        /// (e.g. "claude-sonnet-5-5"). An absent or all-zero entry falls back to the built-in rate.
        public var modelPrices: [String: ClaudeModelPrice] = [:]

        public init() {}

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: ClaudeUsageCodingKeys.self)
            refreshIntervalSeconds =
                (try? container.decodeIfPresent(Double.self, forKey: .refreshIntervalSeconds)) ?? 30
            // Key-by-key so one hand-edited malformed entry drops only that model's override.
            if let pricesContainer = try? container.nestedContainer(keyedBy: RawStringKey.self, forKey: .modelPrices) {
                var prices: [String: ClaudeModelPrice] = [:]
                for key in pricesContainer.allKeys {
                    if let price = try? pricesContainer.decode(ClaudeModelPrice.self, forKey: key) {
                        prices[key.stringValue] = price
                    }
                }
                modelPrices = prices
            } else {
                modelPrices = [:]
            }
        }
    }

    /// One model's USD-per-1M-token prices. A sibling of `ClaudeUsage`, not nested inside it.
    public struct ClaudeModelPrice: Codable, Equatable, Sendable {
        public var inputPerMillion: Double = 0
        /// Cache write at the 5-minute TTL (1.25x input on every current model).
        public var cacheWrite5mPerMillion: Double = 0
        /// Cache write at the 1-hour TTL (2x input) — what current Claude Code versions use.
        public var cacheWrite1hPerMillion: Double = 0
        public var cacheReadPerMillion: Double = 0
        public var outputPerMillion: Double = 0

        public init(
            inputPerMillion: Double = 0,
            cacheWrite5mPerMillion: Double = 0,
            cacheWrite1hPerMillion: Double = 0,
            cacheReadPerMillion: Double = 0,
            outputPerMillion: Double = 0
        ) {
            self.inputPerMillion = inputPerMillion
            self.cacheWrite5mPerMillion = cacheWrite5mPerMillion
            self.cacheWrite1hPerMillion = cacheWrite1hPerMillion
            self.cacheReadPerMillion = cacheReadPerMillion
            self.outputPerMillion = outputPerMillion
        }

        // Each field decoded independently so a hand-edited entry with one rate set still decodes it.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: ClaudeModelPriceCodingKeys.self)
            func read(_ key: ClaudeModelPriceCodingKeys) -> Double {
                (try? container.decodeIfPresent(Double.self, forKey: key)) ?? 0
            }
            inputPerMillion = read(.inputPerMillion)
            cacheWrite5mPerMillion = read(.cacheWrite5mPerMillion)
            cacheWrite1hPerMillion = read(.cacheWrite1hPerMillion)
            cacheReadPerMillion = read(.cacheReadPerMillion)
            outputPerMillion = read(.outputPerMillion)
        }
    }
}
