import Foundation

/// Formats a token count as a compact human-scale string: `"812"`, `"12.3K"`, `"85.6M"`, `"1.24B"`.
public enum TokenCountFormatter {
    public static func short(_ count: Int) -> String {
        let value = Double(count)
        switch abs(value) {
        case ..<1_000:
            return String(count)

        case ..<1_000_000:
            return format(value / 1_000, suffix: "K")

        case ..<1_000_000_000:
            return format(value / 1_000_000, suffix: "M")

        default:
            return format(value / 1_000_000_000, suffix: "B")
        }
    }

    /// One decimal place under 100, two under 10 — keeps three significant figures without
    /// crowding the toolbar chip at the larger end ("85.6M", not "85.600M").
    private static func format(_ scaled: Double, suffix: String) -> String {
        let decimals = abs(scaled) < 10 ? 2 : 1
        return String(format: "%.\(decimals)f%@", scaled, suffix)
    }
}

/// Formats an estimated USD cost.
public enum CostFormatter {
    /// `nil` distinguishes "no price configured" (caller shows "—") from an actual zero cost.
    public static func usd(_ amount: Double?) -> String {
        guard let amount else { return "—" }
        if amount > 0 && amount < 0.01 { return "<$0.01" }
        return String(format: "$%.2f", amount)
    }
}
