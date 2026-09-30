import Foundation

// Dynamic string-keyed CodingKey for decoding `modelPrices` entry-by-entry. A file-local twin of
// the `RawStringKey` in ArgusConfig.swift, which is file-private (Swift's `private` is file-scoped).
private struct ModelPriceKey: CodingKey {
    let stringValue: String
    init(_ string: String) { self.stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    var intValue: Int? { nil }
    init?(intValue: Int) { nil }
}

// `CodexUsage`/`CodexModelPrice` are each already one level deep (nested in `extension ArgusConfig`),
// so their CodingKeys live as file-level enums rather than nested ones — a second nesting level
// would trip SwiftLint's one-level type-nesting limit, the same reason `KeyBindings` reads its
// fields through the file-level `RawStringKey` instead of a nested `CodingKeys`.
private enum CodexUsageCodingKeys: String, CodingKey {
    case refreshIntervalSeconds, scanDayWindow, modelPrices
}

private enum CodexModelPriceCodingKeys: String, CodingKey {
    case inputPerMillion, cachedInputPerMillion, cacheWritePerMillion, outputPerMillion
}

extension ArgusConfig {
    /// Config for the toolbar's daily Codex token/cost usage chip. Kept in its own file rather than
    /// growing the already-large `ArgusConfig.swift`.
    public struct CodexUsage: Codable, Equatable, Sendable {
        public var refreshIntervalSeconds: Double = 30
        /// How many day-directories under `~/.codex/sessions/` to scan. Wider than "just today"
        /// because `codex resume` keeps appending to a session's *original* day's rollout file
        /// indefinitely — a 1-day window would miss tokens from any session resumed more than a day
        /// past its creation, even though those tokens can still land in today's bucket.
        public var scanDayWindow: Int = 7
        /// USD price per 1M tokens, keyed by the model name Codex's `turn_context.model` reports
        /// (e.g. "gpt-6-luna"). Codex records no cost/pricing data itself — see CLAUDE.md's Codex
        /// usage monitor section — so this must be filled in by hand.
        public var modelPrices: [String: CodexModelPrice] = [:]

        public init() {}

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodexUsageCodingKeys.self)
            refreshIntervalSeconds =
                (try? container.decodeIfPresent(Double.self, forKey: .refreshIntervalSeconds)) ?? 30
            scanDayWindow = (try? container.decodeIfPresent(Int.self, forKey: .scanDayWindow)) ?? 7
            // Decoded value-by-value rather than as a whole `[String: CodexModelPrice]` so one
            // hand-edited malformed entry drops just that model's price instead of failing the
            // whole dictionary decode and resetting every configured price to empty — same
            // defensive intent as `ArgusConfig.projectAgents`, adapted for a struct-valued
            // dictionary (that one gets away with a raw-string intermediate decode; a price entry
            // has no such single-scalar fallback, so this decodes key-by-key instead).
            if let pricesContainer = try? container.nestedContainer(keyedBy: ModelPriceKey.self, forKey: .modelPrices) {
                var prices: [String: CodexModelPrice] = [:]
                for key in pricesContainer.allKeys {
                    if let price = try? pricesContainer.decode(CodexModelPrice.self, forKey: key) {
                        prices[key.stringValue] = price
                    }
                }
                modelPrices = prices
            } else {
                modelPrices = [:]
            }
        }
    }

    /// One model's USD-per-1M-token prices. A sibling of `CodexUsage`, not nested inside it —
    /// same one-level-nesting workaround as `AgentDisplayPatternOverrides`/`AgentDisplayPatterns`.
    public struct CodexModelPrice: Codable, Equatable, Sendable {
        public var inputPerMillion: Double = 0
        public var cachedInputPerMillion: Double = 0
        /// USD per 1M tokens written to cache — a separate, usually-premium rate over
        /// `inputPerMillion` (e.g. 1.25x on some models): writing a prefix to cache for later reuse
        /// is itself billed, distinct from both a plain fresh input token and a cached-read one.
        public var cacheWritePerMillion: Double = 0
        public var outputPerMillion: Double = 0

        public init(
            inputPerMillion: Double = 0,
            cachedInputPerMillion: Double = 0,
            cacheWritePerMillion: Double = 0,
            outputPerMillion: Double = 0
        ) {
            self.inputPerMillion = inputPerMillion
            self.cachedInputPerMillion = cachedInputPerMillion
            self.cacheWritePerMillion = cacheWritePerMillion
            self.outputPerMillion = outputPerMillion
        }

        // Each field decoded independently and defaulted rather than relying on synthesized
        // Decodable (which would require all four keys present): the Settings UI only ever writes
        // complete quadruples, but a hand-edited config with just one rate set should still decode
        // that rate rather than dropping the whole entry via CodexUsage's per-key `try?`.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodexModelPriceCodingKeys.self)
            inputPerMillion = (try? container.decodeIfPresent(Double.self, forKey: .inputPerMillion)) ?? 0
            cachedInputPerMillion =
                (try? container.decodeIfPresent(Double.self, forKey: .cachedInputPerMillion)) ?? 0
            cacheWritePerMillion =
                (try? container.decodeIfPresent(Double.self, forKey: .cacheWritePerMillion)) ?? 0
            outputPerMillion = (try? container.decodeIfPresent(Double.self, forKey: .outputPerMillion)) ?? 0
        }
    }
}
