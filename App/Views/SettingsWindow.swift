import SwiftUI

// MARK: - Root layout

enum SettingsCategory: String, CaseIterable, Identifiable {
    case agent = "Agent"
    case keyboard = "Keyboard"
    case github = "GitHub"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .agent: "sparkles"
        case .keyboard: "keyboard"
        case .github: "network"
        }
    }
}

struct SettingsRootView: View {
    @EnvironmentObject private var configStore: ArgusConfigStore
    @State private var selected: SettingsCategory = .agent

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
                case .agent:
                    AgentSettingsView(config: $configStore.config)
                        .onChange(of: configStore.config) { _, _ in configStore.save() }

                case .keyboard:
                    KeyboardSettingsView(config: $configStore.config)
                        .onChange(of: configStore.config) { _, _ in configStore.save() }

                case .github:
                    GitHubSettingsView(config: $configStore.config)
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

// MARK: - Agent settings

struct AgentSettingsView: View {
    @Binding var config: ArgusConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            agentSection
            Divider()
            commandsSection
        }
    }

    private var agentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI Agent")
                .font(.headline)
            Picker("Agent", selection: $config.agent) {
                ForEach(AgentSelection.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 180)
        }
    }

    private var commandsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Commands")
                .font(.headline)
            commandRow("Claude Code", command: $config.claudeCommand)
            commandRow("Codex", command: $config.codexCommand)
            Text(
                "Reload existing panes with"
                    + " \(config.leaderKey) then \(config.keyBindings.reloadAgentPane)."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func commandRow(_ label: String, command: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline)
            TextField("", text: command)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
        }
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

// MARK: - GitHub settings

struct GitHubSettingsView: View {
    @Binding var config: ArgusConfig
    @State private var isDetecting = false
    @State private var detectError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            connectionSection
            Divider()
            refreshSection
        }
    }

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("GitHub Connection")
                .font(.headline)
            settingRow("API Base URL") {
                TextField("https://api.github.com", text: $config.github.apiBaseURL)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 240)
            }
            Text("For github.com use https://api.github.com. For GHE use https://{host}/api/v3.")
                .font(.caption)
                .foregroundStyle(.secondary)
            settingRow("Token") {
                SecureField("ghp_…", text: $config.github.token)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 240)
            }
            if let error = detectError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var refreshSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Refresh")
                .font(.headline)
            settingRow("Interval") {
                Slider(value: $config.github.refreshIntervalSeconds, in: 60...1800, step: 60)
                    .frame(width: 160)
                Text(formatInterval(config.github.refreshIntervalSeconds))
                    .monospacedDigit()
                    .frame(width: 55, alignment: .leading)
            }
        }
    }

    private func settingRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center) {
            Text(label)
                .frame(width: 100, alignment: .leading)
            content()
        }
    }

    private func formatInterval(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        return minutes == 1 ? "1 min" : "\(minutes) min"
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
