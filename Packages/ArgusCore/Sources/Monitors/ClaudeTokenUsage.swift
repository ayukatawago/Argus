import Foundation

/// One model's accumulated Claude Code token counts for some period (a day, in practice). Additive
/// so a day's total is built by summing one value per de-duplicated assistant message.
///
/// Unlike `CodexTokenUsage`, Claude's `input_tokens` already *excludes* cache reads and cache
/// writes, so the four input-side counts here are disjoint — there is nothing to subtract.
public struct ClaudeTokenUsage: Equatable, Sendable {
    public var inputTokens: Int
    public var cacheWrite5mTokens: Int
    public var cacheWrite1hTokens: Int
    public var cacheReadTokens: Int
    public var outputTokens: Int
    public var responseCount: Int

    public init(
        inputTokens: Int = 0,
        cacheWrite5mTokens: Int = 0,
        cacheWrite1hTokens: Int = 0,
        cacheReadTokens: Int = 0,
        outputTokens: Int = 0,
        responseCount: Int = 0
    ) {
        self.inputTokens = inputTokens
        self.cacheWrite5mTokens = cacheWrite5mTokens
        self.cacheWrite1hTokens = cacheWrite1hTokens
        self.cacheReadTokens = cacheReadTokens
        self.outputTokens = outputTokens
        self.responseCount = responseCount
    }

    public static let zero = ClaudeTokenUsage()

    public var cacheWriteTokens: Int { cacheWrite5mTokens.saturatingAdd(cacheWrite1hTokens) }

    /// Everything the model was sent for this request: fresh input plus both cache directions. This
    /// is what a prompt-size pricing tier (Haiku 5.5's 100K threshold) is judged against.
    public var promptTokens: Int { inputTokens.saturatingAdd(cacheReadTokens).saturatingAdd(cacheWriteTokens) }

    public var totalTokens: Int { promptTokens.saturatingAdd(outputTokens) }

    /// Saturating for the same reason as `CodexTokenUsage.+`: a corrupt line must not trap the app.
    public static func + (lhs: Self, rhs: Self) -> Self {
        ClaudeTokenUsage(
            inputTokens: lhs.inputTokens.saturatingAdd(rhs.inputTokens),
            cacheWrite5mTokens: lhs.cacheWrite5mTokens.saturatingAdd(rhs.cacheWrite5mTokens),
            cacheWrite1hTokens: lhs.cacheWrite1hTokens.saturatingAdd(rhs.cacheWrite1hTokens),
            cacheReadTokens: lhs.cacheReadTokens.saturatingAdd(rhs.cacheReadTokens),
            outputTokens: lhs.outputTokens.saturatingAdd(rhs.outputTokens),
            responseCount: lhs.responseCount.saturatingAdd(rhs.responseCount)
        )
    }

    public static func += (lhs: inout Self, rhs: Self) {
        lhs = lhs + rhs
    }
}
