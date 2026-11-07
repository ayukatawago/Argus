import Foundation

/// USD price per 1M tokens for one Claude model. A `Monitors`-local mirror of the equivalent
/// `ArgusConfigKit` config type — `Monitors` may only import `ArgusSupport` (see CONVENTIONS.md).
public struct ClaudeModelRate: Equatable, Sendable {
    public var inputPerMillion: Double
    public var cacheWrite5mPerMillion: Double
    public var cacheWrite1hPerMillion: Double
    public var cacheReadPerMillion: Double
    public var outputPerMillion: Double

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

    public static let unset = ClaudeModelRate()

    /// True when nothing is priced at all — the caller shows "—" rather than a "$0.00".
    public var isUnset: Bool { self == .unset }
}

/// Estimated USD cost of one model's accumulated token usage.
public enum ClaudeUsageCost {
    /// Claude's four input-side counts are disjoint (see `ClaudeTokenUsage`), so each is simply
    /// multiplied by its own rate.
    public static func cost(_ usage: ClaudeTokenUsage, rate: ClaudeModelRate) -> Double {
        let input = Double(usage.inputTokens) / 1_000_000 * rate.inputPerMillion
        let write5m = Double(usage.cacheWrite5mTokens) / 1_000_000 * rate.cacheWrite5mPerMillion
        let write1h = Double(usage.cacheWrite1hTokens) / 1_000_000 * rate.cacheWrite1hPerMillion
        let read = Double(usage.cacheReadTokens) / 1_000_000 * rate.cacheReadPerMillion
        let output = Double(usage.outputTokens) / 1_000_000 * rate.outputPerMillion
        return input + write5m + write1h + read + output
    }
}

extension ClaudeModelRate {
    /// Built-in list prices from https://platform.claude.com/docs/ja/about-claude/pricing, keyed by
    /// model-ID prefix. Dated IDs (`claude-opus-4-5-20251101`) match their undated prefix; the
    /// longest matching prefix wins, so `claude-opus-5-5` is never read as `claude-opus-5`.
    ///
    /// These are list prices for standard-speed, global-endpoint, non-batch requests: fast mode
    /// (2x), US data residency (1.1x) and Batch (0.5x) are not applied.
    private static let defaults: [(prefix: String, rate: ClaudeModelRate)] = [
        ("claude-fable-5-1", rate(10, 12.5, 20, 0.25, 50)),
        ("claude-fable-5", rate(10, 12.5, 20, 1, 50)),
        ("claude-opus-5-5", rate(4, 5, 8, 0.2, 20)),
        ("claude-opus-5", rate(5, 6.25, 10, 0.5, 25)),
        ("claude-opus-4-8", rate(5, 6.25, 10, 0.5, 25)),
        ("claude-opus-4-7", rate(5, 6.25, 10, 0.5, 25)),
        ("claude-opus-4-6", rate(5, 6.25, 10, 0.5, 25)),
        ("claude-opus-4-5", rate(5, 6.25, 10, 0.5, 25)),
        ("claude-opus-4-1", rate(15, 18.75, 30, 1.5, 75)),
        ("claude-opus-4", rate(15, 18.75, 30, 1.5, 75)),
        ("claude-sonnet-5-5", rate(2, 2.5, 4, 0.1, 10)),
        ("claude-sonnet-5", rate(2, 2.5, 4, 0.2, 10)),
        ("claude-sonnet-4", rate(3, 3.75, 6, 0.3, 15)),
        ("claude-haiku-5-5", rate(0.1, 0.125, 0.2, 0.01, 0.5)),
        ("claude-haiku-4-5", rate(1, 1.25, 2, 0.1, 5)),
    ]

    /// The two price rows Haiku 5.5 is billed under — its base tier and the over-100K-prompt tier —
    /// as the parser names them. Settings lists these even on a day Haiku wasn't used, so the tier
    /// prices can be overridden before a long request ever shows up.
    public static let haiku55Models = ["claude-haiku-5-5", "claude-haiku-5-5" + ClaudeUsageParser.longContextSuffix]

    /// Haiku 5.5 requests whose prompt exceeds 100K tokens (`ClaudeUsageParser.longContextSuffix`).
    private static let haiku55LongContext = rate(0.5, 0.625, 1, 0.05, 2.5)

    private static func rate(
        _ input: Double, _ write5m: Double, _ write1h: Double, _ read: Double, _ output: Double
    ) -> ClaudeModelRate {
        ClaudeModelRate(
            inputPerMillion: input, cacheWrite5mPerMillion: write5m, cacheWrite1hPerMillion: write1h,
            cacheReadPerMillion: read, outputPerMillion: output)
    }

    /// The built-in rate for a model name as the parser reports it, or `nil` when unrecognized (the
    /// caller shows "—" and the user can set a price by hand).
    public static func defaultRate(forModel model: String) -> ClaudeModelRate? {
        let isLongContext = model.hasSuffix(ClaudeUsageParser.longContextSuffix)
        let name = isLongContext ? String(model.dropLast(ClaudeUsageParser.longContextSuffix.count)) : model
        guard let match = defaults.filter({ name.hasPrefix($0.prefix) }).max(by: { $0.prefix.count < $1.prefix.count })
        else { return nil }
        return isLongContext && match.prefix == "claude-haiku-5-5" ? haiku55LongContext : match.rate
    }
}
