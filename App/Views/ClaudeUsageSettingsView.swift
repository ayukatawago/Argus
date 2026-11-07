import ArgusConfigKit
import Monitors
import SwiftUI

/// Settings → Usage, Claude section: per-model USD prices for the toolbar's Claude usage chip.
/// Unlike Codex, Anthropic publishes its prices, so every recognized model already has a built-in
/// rate (`ClaudeModelRate.defaultRate`); each row shows the *effective* rate and editing a field
/// stores an override for that model only.
struct ClaudeUsageSettingsView: View {
    @Binding var config: ArgusConfig
    @ObservedObject var usageStore: ClaudeUsageStore
    @State private var newModelName = ""

    /// Every model with an override, every model seen today, and Haiku 5.5's two tiers — so an
    /// override for a model not used yet today (or an unrecognized one) still has a row, and Haiku
    /// 5.5's prices are always there to see and edit.
    private var modelNames: [String] {
        Set(config.claudeUsage.modelPrices.keys)
            .union(usageStore.detectedModels)
            .union(ClaudeModelRate.haiku55Models)
            .sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerSection
            Divider()
            priceSection
            Divider()
            scanSection
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Claude Usage")
                .font(.headline)
            Text(
                "Prices are USD per 1M tokens. Cost = input × input rate + cache writes × write rate"
                    + " + cache reads × read rate + output × output rate."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(
                "Built-in list prices are used for known models; edit a row to override it. This is an"
                    + " API-equivalent estimate — fast mode (2×), US data residency (1.1×) and Batch"
                    + " (0.5×) are not applied, and a Pro/Max subscription is not billed per token."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var priceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Model Prices")
                .font(.headline)
            priceList
            Text(
                "Haiku 5.5 is billed per request in two tiers: the \"(>100K)\" row applies to a request whose"
                    + " whole prompt (input + cache reads + cache writes) exceeds 100K tokens."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            addModelRow
        }
    }

    private var priceList: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Model").frame(width: 150, alignment: .leading)
                Text("Input").frame(width: 58, alignment: .trailing)
                Text("Write 5m").frame(width: 58, alignment: .trailing)
                Text("Write 1h").frame(width: 58, alignment: .trailing)
                Text("Read").frame(width: 58, alignment: .trailing)
                Text("Output").frame(width: 58, alignment: .trailing)
                Spacer().frame(width: 20)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Divider()
            ForEach(modelNames, id: \.self) { model in
                priceRow(model)
            }
        }
    }

    private func priceRow(_ model: String) -> some View {
        HStack(spacing: 8) {
            Text(model)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 150, alignment: .leading)
                .help(model)
            priceField(model: model, keyPath: \.inputPerMillion)
            priceField(model: model, keyPath: \.cacheWrite5mPerMillion)
            priceField(model: model, keyPath: \.cacheWrite1hPerMillion)
            priceField(model: model, keyPath: \.cacheReadPerMillion)
            priceField(model: model, keyPath: \.outputPerMillion)
            Button {
                config.claudeUsage.modelPrices.removeValue(forKey: model)
            } label: {
                Image(systemName: "arrow.counterclockwise.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Reset to the built-in price")
            .disabled(config.claudeUsage.modelPrices[model] == nil)
        }
    }

    /// The override if one exists, else the built-in rate, else all zeros (an unrecognized model).
    private func effectivePrice(_ model: String) -> ArgusConfig.ClaudeModelPrice {
        if let override = config.claudeUsage.modelPrices[model] { return override }
        guard let rate = ClaudeModelRate.defaultRate(forModel: model) else { return .init() }
        return .init(
            inputPerMillion: rate.inputPerMillion,
            cacheWrite5mPerMillion: rate.cacheWrite5mPerMillion,
            cacheWrite1hPerMillion: rate.cacheWrite1hPerMillion,
            cacheReadPerMillion: rate.cacheReadPerMillion,
            outputPerMillion: rate.outputPerMillion)
    }

    private func priceField(
        model: String, keyPath: WritableKeyPath<ArgusConfig.ClaudeModelPrice, Double>
    ) -> some View {
        TextField(
            "",
            value: Binding(
                get: { effectivePrice(model)[keyPath: keyPath] },
                // Seeded from the effective rate, so editing one field of a built-in price leaves
                // the other four at their built-in values rather than zeroing them.
                set: {
                    var price = effectivePrice(model)
                    price[keyPath: keyPath] = $0
                    config.claudeUsage.modelPrices[model] = price
                }
            ),
            format: .number.precision(.fractionLength(0...4))
        )
        .textFieldStyle(.roundedBorder)
        .multilineTextAlignment(.trailing)
        .frame(width: 58)
    }

    private var addModelRow: some View {
        HStack(spacing: 8) {
            TextField("model name", text: $newModelName)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .frame(width: 200)
            Button("Add") {
                let name = newModelName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                if config.claudeUsage.modelPrices[name] == nil {
                    config.claudeUsage.modelPrices[name] = effectivePrice(name)
                }
                newModelName = ""
            }
            .disabled(newModelName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var scanSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scan")
                .font(.headline)
            HStack {
                Text("Refresh every").frame(width: 130, alignment: .leading)
                Stepper(
                    "\(Int(config.claudeUsage.refreshIntervalSeconds))s",
                    value: $config.claudeUsage.refreshIntervalSeconds,
                    in: 5...300,
                    step: 5
                )
                .frame(width: 100)
            }
            Text(
                "Counts every Claude Code transcript touched today, including Task-subagent runs and"
                    + " headless diff-review runs, each message once."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
