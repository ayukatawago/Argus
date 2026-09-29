import ArgusConfigKit
import SwiftUI

// MARK: - Root layout

enum SettingsCategory: String, CaseIterable, Identifiable {
    case agent = "Agent"
    case keyboard = "Keyboard"
    case github = "GitHub"
    case environment = "Environment"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .agent: "sparkles"
        case .keyboard: "keyboard"
        case .github: "network"
        case .environment: "terminal"
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

                case .environment:
                    EnvironmentSettingsView(config: $configStore.config)
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
            Text("The default agent tab opened for a newly selected worktree. The other agent's")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("tab can still be opened on demand from the agent pane's \"+\" button.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("A project can override this from its sidebar repo header's context menu.")
                .font(.caption)
                .foregroundStyle(.secondary)
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

// MARK: - Environment settings

struct EnvironmentSettingsView: View {
    @Binding var config: ArgusConfig
    @State private var newKey = ""
    @State private var newValue = ""

    private var sortedKeys: [String] { config.environmentVariables.keys.sorted() }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerSection
            if !sortedKeys.isEmpty {
                variableList
                Divider()
            }
            addRow
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Environment Variables")
                .font(.headline)
            Text(
                "Exported in every terminal and agent pane when a new session starts."
                    + " Reload existing panes with \(config.leaderKey)"
                    + " then \(config.keyBindings.reloadAgentPane)."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var variableList: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 150, alignment: .leading)
                Text("Value")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Divider()
            ForEach(sortedKeys, id: \.self) { key in
                HStack(spacing: 8) {
                    Text(key)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 150, alignment: .leading)
                    TextField(
                        "",
                        text: Binding(
                            get: { config.environmentVariables[key] ?? "" },
                            set: { config.environmentVariables[key] = $0 }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    Button {
                        config.environmentVariables.removeValue(forKey: key)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var addRow: some View {
        HStack(spacing: 8) {
            TextField("KEY", text: $newKey)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .frame(width: 150)
            TextField("value", text: $newValue)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            Button("Add") {
                let key = newKey.trimmingCharacters(in: .whitespaces)
                guard !key.isEmpty else { return }
                config.environmentVariables[key] = newValue
                newKey = ""
                newValue = ""
            }
            .disabled(newKey.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}
