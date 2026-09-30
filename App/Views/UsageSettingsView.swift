import ArgusConfigKit
import SwiftUI

/// Settings → Usage: per-model USD prices for the toolbar's Codex usage chip/popover, plus the
/// scan's refresh interval and lookback window. Codex records no pricing data of its own (see
/// CLAUDE.md's Codex usage monitor section), so every rate here starts at zero until set by hand.
struct UsageSettingsView: View {
    @Binding var config: ArgusConfig
    @ObservedObject var usageStore: CodexUsageStore
    @State private var newModelName = ""

    /// Every model with a configured price, plus every model the scan has actually seen — so a
    /// model used only yesterday (outside a very short scan window) still gets a row, and a
    /// manually pre-priced model shows up before Codex ever reports using it.
    private var modelNames: [String] {
        Set(config.codexUsage.modelPrices.keys).union(usageStore.detectedModels).sorted()
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
            Text("Codex Usage")
                .font(.headline)
            Text(
                "Prices are USD per 1M tokens. Cost = (input − cached) × input rate"
                    + " + cached × cached rate + output × output rate."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(
                "Reasoning tokens are already counted inside output; cache-write tokens are"
                    + " already counted inside the uncached input portion."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var priceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Model Prices")
                .font(.headline)
            if !modelNames.isEmpty {
                priceList
            } else {
                Text("No Codex models detected yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            addModelRow
        }
    }

    private var priceList: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Model").frame(width: 130, alignment: .leading)
                Text("Input").frame(width: 70, alignment: .trailing)
                Text("Cached").frame(width: 70, alignment: .trailing)
                Text("Output").frame(width: 70, alignment: .trailing)
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
                .frame(width: 130, alignment: .leading)
            priceField(model: model, keyPath: \.inputPerMillion)
            priceField(model: model, keyPath: \.cachedInputPerMillion)
            priceField(model: model, keyPath: \.outputPerMillion)
            Button {
                config.codexUsage.modelPrices.removeValue(forKey: model)
            } label: {
                Image(systemName: "arrow.counterclockwise.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Reset to unpriced")
            .disabled(config.codexUsage.modelPrices[model] == nil)
        }
    }

    private func priceField(
        model: String, keyPath: WritableKeyPath<ArgusConfig.CodexModelPrice, Double>
    ) -> some View {
        TextField(
            "",
            value: Binding(
                get: { config.codexUsage.modelPrices[model]?[keyPath: keyPath] ?? 0 },
                set: { config.codexUsage.modelPrices[model, default: .init()][keyPath: keyPath] = $0 }
            ),
            format: .number.precision(.fractionLength(0...4))
        )
        .textFieldStyle(.roundedBorder)
        .multilineTextAlignment(.trailing)
        .frame(width: 70)
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
                if config.codexUsage.modelPrices[name] == nil {
                    config.codexUsage.modelPrices[name] = .init()
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
                    "\(Int(config.codexUsage.refreshIntervalSeconds))s",
                    value: $config.codexUsage.refreshIntervalSeconds,
                    in: 5...300,
                    step: 5
                )
                .frame(width: 100)
            }
            HStack {
                Text("Look back").frame(width: 130, alignment: .leading)
                Stepper(
                    "\(config.codexUsage.scanDayWindow) day"
                        + (config.codexUsage.scanDayWindow == 1 ? "" : "s"),
                    value: $config.codexUsage.scanDayWindow,
                    in: 1...30
                )
                .frame(width: 100)
            }
            Text(
                "A resumed Codex session keeps appending to its original day's rollout file, so"
                    + " today's total can include tokens from a session started before today."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
