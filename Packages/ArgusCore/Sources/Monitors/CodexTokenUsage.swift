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

    public static func + (lhs: Self, rhs: Self) -> Self {
        CodexTokenUsage(
            inputTokens: lhs.inputTokens + rhs.inputTokens,
            cachedInputTokens: lhs.cachedInputTokens + rhs.cachedInputTokens,
            cacheWriteInputTokens: lhs.cacheWriteInputTokens + rhs.cacheWriteInputTokens,
            outputTokens: lhs.outputTokens + rhs.outputTokens,
            reasoningOutputTokens: lhs.reasoningOutputTokens + rhs.reasoningOutputTokens,
            totalTokens: lhs.totalTokens + rhs.totalTokens,
            responseCount: lhs.responseCount + rhs.responseCount
        )
    }

    public static func += (lhs: inout Self, rhs: Self) {
        lhs = lhs + rhs
    }
}
