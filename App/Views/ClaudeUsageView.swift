import ArgusConfigKit
import Monitors
import SwiftUI

/// Per-model breakdown popover for the toolbar's Claude usage chip. Same layout as `CodexUsageView`.
struct ClaudeUsageView: View {
    @ObservedObject var store: ClaudeUsageStore
    @EnvironmentObject private var configStore: ArgusConfigStore

    private var summary: ClaudeUsageSummary {
        ClaudeUsageSummary(today: store.today, prices: configStore.config.claudeUsage.modelPrices)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if summary.rows.isEmpty {
                Text("No Claude activity today.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                table
            }
            if summary.unpricedModelCount > 0 {
                unpricedNotice
            }
            Text("API-equivalent estimate at list prices — not what a Pro/Max subscription bills.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(minWidth: 380, maxWidth: 420)
    }

    private var header: some View {
        HStack {
            Text("Claude usage — today")
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
            ForEach(summary.rows, id: \.model) { row in
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

    private func rowView(_ row: ClaudeUsageRow) -> some View {
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
                "in \(TokenCountFormatter.short(row.usage.inputTokens))"
                    + " · cache read \(TokenCountFormatter.short(row.usage.cacheReadTokens))"
                    + " · write \(TokenCountFormatter.short(row.usage.cacheWriteTokens))"
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
            Text(TokenCountFormatter.short(summary.totalTokens))
                .monospacedDigit()
                .bold()
                .frame(width: 70, alignment: .trailing)
            Text(CostFormatter.usd(summary.totalCost))
                .monospacedDigit()
                .bold()
                .frame(width: 70, alignment: .trailing)
        }
        .font(.callout)
    }

    private var unpricedNotice: some View {
        HStack {
            Text(
                summary.unpricedModelCount == 1
                    ? "1 model has no known price."
                    : "\(summary.unpricedModelCount) models have no known price."
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
