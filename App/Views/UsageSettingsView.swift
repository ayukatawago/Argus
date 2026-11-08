import ArgusConfigKit
import Monitors
import SwiftUI

/// Settings → Usage: per-model USD prices for the toolbar's Codex usage chip/popover, plus the
/// scan's refresh interval and lookback window. Codex records no pricing data of its own, so the
/// built-in OpenAI list prices (`CodexModelRate.defaultRate`) are shown per Standard/Fast tab; editing
/// a field stores an override for that model and tier only.
struct UsageSettingsView: View {
    @Binding var config: ArgusConfig
    @ObservedObject var usageStore: CodexUsageStore
    @State private var newModelName = ""

    /// Every model with a configured price, plus every model the scan has actually seen — so a
    /// model used only yesterday (outside a very short scan window) still gets a row, and a
    /// manually pre-priced model shows up before Codex ever reports using it.
    private var modelNames: [String] {
        Set(config.codexUsage.prices(for: tier).keys)
            .union(usageStore.detectedModels)
            .union(CodexModelRate.knownModels)
            .sorted()
    }

    private var tier: ArgusConfig.CodexPriceTier { config.codexUsage.priceTier }

    /// The override table the current tab edits.
    private var overridesPath: WritableKeyPath<ArgusConfig, [String: ArgusConfig.CodexModelPrice]> {
        tier == .fast ? \.codexUsage.fastModelPrices : \.codexUsage.modelPrices
    }

    /// The override if one is set, else the built-in rate for this tier, else all zeros.
    private func effectivePrice(_ model: String) -> ArgusConfig.CodexModelPrice {
        if let override = config[keyPath: overridesPath][model] { return override }
        let monitorsTier = CodexPriceTier(rawValue: tier.rawValue) ?? .standard
        guard let rate = CodexModelRate.defaultRate(forModel: model, tier: monitorsTier) else { return .init() }
        return .init(
            inputPerMillion: rate.inputPerMillion, cachedInputPerMillion: rate.cachedInputPerMillion,
            cacheWritePerMillion: rate.cacheWritePerMillion, outputPerMillion: rate.outputPerMillion)
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
                "Prices are USD per 1M tokens. Cost = fresh input × input rate"
                    + " + cached × cached rate + cache write × write rate + output × output rate."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(
                "\"Fresh input\" excludes both cache reads and cache writes — Codex reports"
                    + " cache-write tokens as part of input, so they're billed at the write rate"
                    + " instead of the input rate, not both. Reasoning tokens are already counted"
                    + " inside output."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var priceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Model Prices")
                .font(.headline)
            Picker("Tier", selection: $config.codexUsage.priceTier) {
                ForEach(ArgusConfig.CodexPriceTier.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 200)
            Text(
                "The selected tier is the one the toolbar chip and popover price with. Built-in list prices"
                    + " come from developers.openai.com/api/docs/pricing; edit a row to override it."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            priceList
            addModelRow
        }
    }

    private var priceList: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Model").frame(width: 130, alignment: .leading)
                Text("Input").frame(width: 70, alignment: .trailing)
                Text("Cached").frame(width: 70, alignment: .trailing)
                Text("Write").frame(width: 70, alignment: .trailing)
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
            priceField(model: model, keyPath: \.cacheWritePerMillion)
            priceField(model: model, keyPath: \.outputPerMillion)
            Button {
                config[keyPath: overridesPath].removeValue(forKey: model)
            } label: {
                Image(systemName: "arrow.counterclockwise.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Reset to the built-in price")
            .disabled(config[keyPath: overridesPath][model] == nil)
        }
    }

    private func priceField(
        model: String, keyPath: WritableKeyPath<ArgusConfig.CodexModelPrice, Double>
    ) -> some View {
        TextField(
            "",
            value: Binding(
                get: { effectivePrice(model)[keyPath: keyPath] },
                // Seeded from the effective rate so editing one field keeps the other three.
                set: {
                    var price = effectivePrice(model)
                    price[keyPath: keyPath] = $0
                    config[keyPath: overridesPath][model] = price
                }
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
                if config[keyPath: overridesPath][name] == nil {
                    config[keyPath: overridesPath][name] = effectivePrice(name)
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
