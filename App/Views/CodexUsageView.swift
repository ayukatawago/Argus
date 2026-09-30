import ArgusConfigKit
import Monitors
import SwiftUI

/// Per-model breakdown popover for the toolbar's Codex usage chip.
struct CodexUsageView: View {
    @ObservedObject var store: CodexUsageStore
    @EnvironmentObject private var configStore: ArgusConfigStore

    private var rows: [UsageRow] {
        let prices = configStore.config.codexUsage.modelPrices
        return store.today.map { model, usage in
            let rate =
                prices[model].map {
                    CodexModelRate(
                        inputPerMillion: $0.inputPerMillion,
                        cachedInputPerMillion: $0.cachedInputPerMillion,
                        outputPerMillion: $0.outputPerMillion)
                } ?? .unset
            let cost = rate.isUnset ? nil : CodexUsageCost.cost(usage, rate: rate)
            return UsageRow(model: model, usage: usage, cost: cost)
        }
        .sorted { lhs, rhs in
            if let leftCost = lhs.cost, let rightCost = rhs.cost, leftCost != rightCost {
                return leftCost > rightCost
            }
            if (lhs.cost == nil) != (rhs.cost == nil) { return lhs.cost != nil }
            return lhs.usage.totalTokens > rhs.usage.totalTokens
        }
    }

    private var totalTokens: Int { rows.reduce(0) { $0 + $1.usage.totalTokens } }
    private var totalCost: Double? {
        let priced = rows.compactMap(\.cost)
        return priced.isEmpty ? nil : priced.reduce(0, +)
    }
    private var unpricedModelCount: Int { rows.filter { $0.cost == nil }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if rows.isEmpty {
                Text("No Codex activity today.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                table
            }
            if unpricedModelCount > 0 {
                unpricedNotice
            }
        }
        .padding(14)
        .frame(minWidth: 360)
    }

    private var header: some View {
        HStack {
            Text("Codex usage — today")
                .font(.headline)
            Spacer()
            if let lastScan = store.lastScan {
                Text("as of \(lastScan.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var table: some View {
        VStack(alignment: .leading, spacing: 6) {
            columnHeaders
            Divider()
            ForEach(rows, id: \.model) { row in
                rowView(row)
            }
            Divider()
            totalRow
        }
    }

    private var columnHeaders: some View {
        HStack {
            Text("Model").frame(maxWidth: .infinity, alignment: .leading)
            Text("Tokens").frame(width: 70, alignment: .trailing)
            Text("Cost").frame(width: 70, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func rowView(_ row: UsageRow) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text(row.model).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(TokenCountFormatter.short(row.usage.totalTokens))
                    .monospacedDigit()
                    .frame(width: 70, alignment: .trailing)
                Text(CostFormatter.usd(row.cost))
                    .monospacedDigit()
                    .frame(width: 70, alignment: .trailing)
            }
            .font(.callout)
            Text(
                "in \(TokenCountFormatter.short(row.usage.uncachedInputTokens))"
                    + " · cached \(TokenCountFormatter.short(row.usage.cachedInputTokens))"
                    + " · out \(TokenCountFormatter.short(row.usage.outputTokens))"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private var totalRow: some View {
        HStack {
            Text("Total").bold()
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(TokenCountFormatter.short(totalTokens))
                .monospacedDigit()
                .bold()
                .frame(width: 70, alignment: .trailing)
            Text(CostFormatter.usd(totalCost))
                .monospacedDigit()
                .bold()
                .frame(width: 70, alignment: .trailing)
        }
        .font(.callout)
    }

    private var unpricedNotice: some View {
        HStack {
            Text(
                unpricedModelCount == 1
                    ? "1 model has no price set."
                    : "\(unpricedModelCount) models have no price set."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer()
            Button("Set prices…") {
                NotificationCenter.default.post(name: .openSettings, object: nil)
            }
            .font(.caption)
        }
    }

    private struct UsageRow {
        let model: String
        let usage: CodexTokenUsage
        let cost: Double?
    }
}
