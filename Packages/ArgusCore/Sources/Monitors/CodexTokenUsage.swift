import Foundation

/// One model's accumulated token counts for some period (a day, in practice). Additive so a
/// day's total is built by summing one value per `token_usage_record` line.
public struct CodexTokenUsage: Equatable, Sendable {
    public var inputTokens: Int
    public var cachedInputTokens: Int
    public var cacheWriteInputTokens: Int
    public var outputTokens: Int
    public var reasoningOutputTokens: Int
    public var totalTokens: Int
    public var responseCount: Int

    public init(
        inputTokens: Int = 0,
        cachedInputTokens: Int = 0,
        cacheWriteInputTokens: Int = 0,
        outputTokens: Int = 0,
        reasoningOutputTokens: Int = 0,
        totalTokens: Int = 0,
        responseCount: Int = 0
    ) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.cacheWriteInputTokens = cacheWriteInputTokens
        self.outputTokens = outputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.totalTokens = totalTokens
        self.responseCount = responseCount
    }

    public static let zero = CodexTokenUsage()

    /// Codex's `input_tokens` is inclusive of `cached_input_tokens` — this is the full-price
    /// remainder. Clamped rather than allowed to go negative: this reads a foreign process's
    /// output, and a malformed/future record with `cached > input` should degrade to "no discount"
    /// rather than produce a nonsensical negative token count.
    public var uncachedInputTokens: Int { max(0, inputTokens - cachedInputTokens) }

    /// The portion of `uncachedInputTokens` that is neither a cache read nor a cache write — the
    /// genuinely new tokens billed at the plain input rate. `cacheWriteInputTokens` is itself a
    /// subset of `uncachedInputTokens` (a token being written to cache was, by definition, not
    /// already a cache hit), so without this split every cache-write token would otherwise be
    /// billed twice: once here and once at the cache-write rate. Clamped for the same reason as
    /// `uncachedInputTokens`.
    public var freshInputTokens: Int { max(0, uncachedInputTokens - cacheWriteInputTokens) }

    /// Saturating: a corrupt rollout line carrying an absurd count must not trap the whole app on
    /// overflow, and clamping at `Int.max` keeps the daily total visibly wrong rather than fatal.
    public static func + (lhs: Self, rhs: Self) -> Self {
        CodexTokenUsage(
            inputTokens: lhs.inputTokens.saturatingAdd(rhs.inputTokens),
            cachedInputTokens: lhs.cachedInputTokens.saturatingAdd(rhs.cachedInputTokens),
            cacheWriteInputTokens: lhs.cacheWriteInputTokens.saturatingAdd(rhs.cacheWriteInputTokens),
            outputTokens: lhs.outputTokens.saturatingAdd(rhs.outputTokens),
            reasoningOutputTokens: lhs.reasoningOutputTokens.saturatingAdd(rhs.reasoningOutputTokens),
            totalTokens: lhs.totalTokens.saturatingAdd(rhs.totalTokens),
            responseCount: lhs.responseCount.saturatingAdd(rhs.responseCount)
        )
    }

    public static func += (lhs: inout Self, rhs: Self) {
        lhs = lhs + rhs
    }
}

extension Int {
    fileprivate func saturatingAdd(_ other: Int) -> Int {
        let (sum, overflow) = addingReportingOverflow(other)
        return overflow ? (other < 0 ? .min : .max) : sum
    }
}
