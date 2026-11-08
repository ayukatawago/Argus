import Foundation

/// The OpenAI processing tier a price applies to. `ArgusConfig.CodexPriceTier` mirrors this
/// (`Monitors` may only import `ArgusSupport`).
public enum CodexPriceTier: String, CaseIterable, Sendable {
    case standard
    case fast
}

extension CodexModelRate {
    private struct Entry {
        let model: String
        let standard: CodexModelRate
        let fast: CodexModelRate

        init(_ model: String, _ standard: CodexModelRate, _ fast: CodexModelRate) {
            self.model = model
            self.standard = standard
            self.fast = fast
        }
    }

    /// Built-in list prices (USD per 1M tokens) from
    /// https://developers.openai.com/api/docs/pricing, keyed by exact model ID — columns are fresh
    /// input / cached input / cache write / output. Fast mode (formerly "Priority") is 2x Standard
    /// for these models; Batch/Flex, Ultrafast and data-residency uplifts are not modeled.
    private static let defaults: [Entry] = [
        Entry("gpt-6-astra", rate(10, 1, 12.5, 50), rate(20, 2, 25, 100)),
        Entry("gpt-6.1-sol", rate(2, 0.1, 2.5, 10), rate(4, 0.2, 5, 20)),
        Entry("gpt-6.1-terra", rate(1, 0.05, 1.25, 5), rate(2, 0.1, 2.5, 10)),
        Entry("gpt-6-luna", rate(0.1, 0.01, 0.125, 0.5), rate(0.2, 0.02, 0.25, 1)),
    ]

    /// Model IDs that have a built-in price, in the order the pricing page lists them — Settings
    /// shows a row for each even before Codex has used it.
    public static let knownModels = defaults.map(\.model)

    private static func rate(_ input: Double, _ cached: Double, _ write: Double, _ output: Double) -> CodexModelRate {
        CodexModelRate(
            inputPerMillion: input, cachedInputPerMillion: cached,
            cacheWritePerMillion: write, outputPerMillion: output)
    }

    /// The built-in rate for `model` at `tier`, or `nil` for a model not on the table (the caller
    /// shows "—" and the user can set a price by hand).
    public static func defaultRate(forModel model: String, tier: CodexPriceTier) -> CodexModelRate? {
        guard let entry = defaults.first(where: { $0.model == model }) else { return nil }
        return tier == .fast ? entry.fast : entry.standard
    }
}
