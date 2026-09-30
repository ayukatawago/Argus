import Foundation

/// USD price per 1M tokens for one model. A `Monitors`-local mirror of the equivalent
/// `ArgusConfigKit` config type — `Monitors` may only import `ArgusSupport` (see CONVENTIONS.md),
/// the same split `DiskUsage` has from `ArgusConfig.DiskMonitor`.
public struct CodexModelRate: Equatable, Sendable {
    public var inputPerMillion: Double
    public var cachedInputPerMillion: Double
    public var cacheWritePerMillion: Double
    public var outputPerMillion: Double

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

    public static let unset = CodexModelRate()

    /// True when no price has been configured for this model at all — the caller should show "—"
    /// rather than a (misleadingly precise-looking) "$0.00".
    public var isUnset: Bool {
        inputPerMillion == 0 && cachedInputPerMillion == 0 && cacheWritePerMillion == 0 && outputPerMillion == 0
    }
}

/// Estimated USD cost of one model's accumulated token usage.
public enum CodexUsageCost {
    /// `usage.inputTokens` includes both `usage.cachedInputTokens` (a cache read) and
    /// `usage.cacheWriteInputTokens` (a subset of the uncached remainder — writing a token to
    /// cache is itself billed, typically at a premium over the plain input rate). Each of the
    /// three input categories — fresh, cached-read, cache-write — is billed at its own rate
    /// exactly once; `CodexTokenUsage.freshInputTokens` is what's left after removing both.
    public static func cost(_ usage: CodexTokenUsage, rate: CodexModelRate) -> Double {
        let freshInput = Double(usage.freshInputTokens) / 1_000_000 * rate.inputPerMillion
        let cachedInput = Double(usage.cachedInputTokens) / 1_000_000 * rate.cachedInputPerMillion
        let cacheWrite = Double(usage.cacheWriteInputTokens) / 1_000_000 * rate.cacheWritePerMillion
        let output = Double(usage.outputTokens) / 1_000_000 * rate.outputPerMillion
        return freshInput + cachedInput + cacheWrite + output
    }
}
