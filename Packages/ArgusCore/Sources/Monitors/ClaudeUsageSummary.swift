import Foundation

/// One model's row in the Claude usage breakdown.
public struct ClaudeUsageRow: Equatable, Sendable {
    public let model: String
    public let usage: ClaudeTokenUsage
    /// Estimated USD cost, or `nil` when the model has neither a user price nor a built-in one —
    /// shown as "—", never as a misleading "$0.00".
    public let cost: Double?
}

/// Today's Claude usage reduced to what the toolbar chip and its popover show — the one place the
/// override → default rate → cost logic lives. Mirrors `CodexUsageSummary`.
public struct ClaudeUsageSummary: Equatable, Sendable {
    /// Most expensive priced model first, then priced before unpriced, then by token count.
    public let rows: [ClaudeUsageRow]
    public let totalUsage: ClaudeTokenUsage
    /// Sum of the priced models' costs; `nil` when no model could be priced at all.
    public let totalCost: Double?

    public var totalTokens: Int { totalUsage.totalTokens }
    public var unpricedModelCount: Int { rows.filter { $0.cost == nil }.count }
    public var isEmpty: Bool { rows.isEmpty }

    /// - Parameter overrides: the user's per-model rates. An unset (all-zero) override is ignored,
    ///   so "reset to default" and "never touched" behave the same.
    public init(today: [String: ClaudeTokenUsage], overrides: [String: ClaudeModelRate]) {
        let unsorted = today.map { model, usage -> ClaudeUsageRow in
            let override = overrides[model].flatMap { $0.isUnset ? nil : $0 }
            let rate = override ?? ClaudeModelRate.defaultRate(forModel: model)
            return ClaudeUsageRow(model: model, usage: usage, cost: rate.map { ClaudeUsageCost.cost(usage, rate: $0) })
        }
        rows = unsorted.sorted(by: Self.isOrderedBefore)
        totalUsage = today.values.reduce(.zero, +)
        let priced = unsorted.compactMap(\.cost)
        totalCost = priced.isEmpty ? nil : priced.reduce(0, +)
    }

    private static func isOrderedBefore(_ lhs: ClaudeUsageRow, _ rhs: ClaudeUsageRow) -> Bool {
        if let leftCost = lhs.cost, let rightCost = rhs.cost, leftCost != rightCost { return leftCost > rightCost }
        if (lhs.cost == nil) != (rhs.cost == nil) { return lhs.cost != nil }
        if lhs.usage.totalTokens != rhs.usage.totalTokens { return lhs.usage.totalTokens > rhs.usage.totalTokens }
        return lhs.model < rhs.model  // deterministic when everything else ties
    }
}
