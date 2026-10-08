import ArgusConfigKit
import Monitors
import SwiftUI

/// Per-model breakdown popover for the toolbar's Codex usage chip.
struct CodexUsageView: View {
    @ObservedObject var store: CodexUsageStore
    @EnvironmentObject private var configStore: ArgusConfigStore

    private var summary: CodexUsageSummary {
        CodexUsageSummary(today: store.today, prices: configStore.config.codexUsage.modelPrices)
    }

    private var rows: [CodexUsageRow] { summary.rows }
    private var totalTokens: Int { summary.totalTokens }
    private var totalCost: Double? { summary.totalCost }
    private var unpricedModelCount: Int { summary.unpricedModelCount }

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

    private func rowView(_ row: CodexUsageRow) -> some View {
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
                "in \(TokenCountFormatter.short(row.usage.freshInputTokens))"
                    + " · cached \(TokenCountFormatter.short(row.usage.cachedInputTokens))"
                    + " · write \(TokenCountFormatter.short(row.usage.cacheWriteInputTokens))"
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
}
