import Foundation

/// One model's row in the Codex usage breakdown.
public struct CodexUsageRow: Equatable, Sendable {
    public let model: String
    public let usage: CodexTokenUsage
    /// Estimated USD cost, or `nil` when no price is configured for the model — shown as "—", never
    /// as a misleading "$0.00".
    public let cost: Double?
}

/// Today's Codex usage reduced to what the toolbar chip and its popover show. Both used to carry
/// their own copy of the price → rate → cost logic; this is the one place it lives.
public struct CodexUsageSummary: Equatable, Sendable {
    /// Most expensive priced model first, then priced before unpriced, then by token count.
    public let rows: [CodexUsageRow]
    public let totalUsage: CodexTokenUsage
    /// Sum of the priced models' costs; `nil` when no model has a price at all.
    public let totalCost: Double?

    public var totalTokens: Int { totalUsage.totalTokens }
    public var unpricedModelCount: Int { rows.filter { $0.cost == nil }.count }
    public var isEmpty: Bool { rows.isEmpty }

    public init(today: [String: CodexTokenUsage], rates: [String: CodexModelRate]) {
        let unsorted = today.map { model, usage -> CodexUsageRow in
            let rate = rates[model] ?? .unset
            return CodexUsageRow(
                model: model, usage: usage, cost: rate.isUnset ? nil : CodexUsageCost.cost(usage, rate: rate))
        }
        rows = unsorted.sorted(by: Self.isOrderedBefore)
        totalUsage = today.values.reduce(.zero, +)
        let priced = unsorted.compactMap(\.cost)
        totalCost = priced.isEmpty ? nil : priced.reduce(0, +)
    }

    private static func isOrderedBefore(_ lhs: CodexUsageRow, _ rhs: CodexUsageRow) -> Bool {
        if let leftCost = lhs.cost, let rightCost = rhs.cost, leftCost != rightCost { return leftCost > rightCost }
        if (lhs.cost == nil) != (rhs.cost == nil) { return lhs.cost != nil }
        if lhs.usage.totalTokens != rhs.usage.totalTokens { return lhs.usage.totalTokens > rhs.usage.totalTokens }
        return lhs.model < rhs.model  // deterministic when everything else ties
    }
}
