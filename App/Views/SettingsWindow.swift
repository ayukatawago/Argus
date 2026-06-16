import SwiftUI

// MARK: - Root layout

enum SettingsCategory: String, CaseIterable, Identifiable {
    case keyboard = "Keyboard"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .keyboard: "keyboard"
        }
    }
}

struct SettingsRootView: View {
    @EnvironmentObject private var configStore: ArgusConfigStore
    @State private var selected: SettingsCategory = .keyboard

    var body: some View {
        HStack(spacing: 0) {
            navColumn
            Divider()
            contentColumn
        }
    }

    private var navColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsCategory.allCases) { cat in
                navRow(cat)
            }
            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .frame(width: 150)
        .background(.windowBackground)
    }

    private var contentColumn: some View {
        ScrollView {
            Group {
                switch selected {
                case .keyboard:
                    KeyboardSettingsView(config: $configStore.config)
                        .onChange(of: configStore.config) { _, _ in configStore.save() }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func navRow(_ cat: SettingsCategory) -> some View {
        Button(
            action: { selected = cat },
            label: {
                Label(cat.rawValue, systemImage: cat.icon)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(selected == cat ? Color.accentColor.opacity(0.2) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
        )
        .buttonStyle(.plain)
    }
}

// MARK: - Keyboard settings

struct KeyboardSettingsView: View {
    @Binding var config: ArgusConfig

    private let leaderOptions = ["ctrl+b", "ctrl+a", "ctrl+x", "ctrl+space"]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            leaderSection
            Divider()
            bindingsSection
        }
    }

    private var leaderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Leader Key")
                .font(.headline)
            settingRow("Key combo") {
                Picker("", selection: $config.leaderKey) {
                    ForEach(leaderOptions, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 130)
            }
            settingRow("Timeout") {
                Slider(value: $config.leaderTimeoutSeconds, in: 0.5...3.0, step: 0.1)
                    .frame(width: 120)
                Text(String(format: "%.1f s", config.leaderTimeoutSeconds))
                    .monospacedDigit()
                    .frame(width: 40, alignment: .leading)
            }
        }
    }

    private var bindingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Key Bindings")
                .font(.headline)
            VStack(spacing: 4) {
                bindingRow("Focus shell pane", key: $config.keyBindings.focusShellPane)
                bindingRow("Focus agent pane", key: $config.keyBindings.focusAgentPane)
                bindingRow("Next worktree", key: $config.keyBindings.selectNextWorktree)
                bindingRow("Previous worktree", key: $config.keyBindings.selectPreviousWorktree)
                bindingRow("Open lazygit", key: $config.keyBindings.openLazygit)
                bindingRow("Open nvim", key: $config.keyBindings.openNvim)
                bindingRow("Refresh workspace", key: $config.keyBindings.refreshWorkspace)
                bindingRow("Open markdown preview", key: $config.keyBindings.openMarkdownPreview)
                bindingRow("Open settings", key: $config.keyBindings.openSettings)
            }
            Text("Press \(config.leaderKey), then the key shown.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func settingRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .frame(width: 100, alignment: .leading)
            content()
        }
    }

    private func bindingRow(_ label: String, key: Binding<String>) -> some View {
        HStack {
            Text(label)
                .frame(maxWidth: .infinity, alignment: .leading)
            SingleCharField(value: key)
        }
    }
}

// MARK: - Single-character text field

private struct SingleCharField: View {
    @Binding var value: String

    var body: some View {
        TextField("", text: $value)
            .multilineTextAlignment(.center)
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .frame(width: 36)
            .onChange(of: value) { _, newValue in
                if newValue.count > 1 { value = String(newValue.suffix(1)) }
            }
    }
}
