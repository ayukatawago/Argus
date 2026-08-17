import ArgusConfigKit
import SwiftUI

// MARK: - Keyboard settings

struct KeyboardSettingsView: View {
    @Binding var config: ArgusConfig
    @State private var newPopupName = ""
    @State private var newPopupKey = ""
    @State private var newPopupCommand = ""

    private let leaderOptions = ["ctrl+b", "ctrl+a", "ctrl+x", "ctrl+space"]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            leaderSection
            Divider()
            bindingsSection
            Divider()
            popupShortcutsSection
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
                bindingRow("Focus pane left", key: $config.keyBindings.focusPaneLeft)
                bindingRow("Focus pane right", key: $config.keyBindings.focusPaneRight)
                bindingRow("Next worktree", key: $config.keyBindings.selectNextWorktree)
                bindingRow("Previous worktree", key: $config.keyBindings.selectPreviousWorktree)
                bindingRow("Open nvim", key: $config.keyBindings.openNvim)
                bindingRow("Refresh workspace", key: $config.keyBindings.refreshWorkspace)
                bindingRow("Open markdown preview", key: $config.keyBindings.openMarkdownPreview)
                bindingRow("Open settings", key: $config.keyBindings.openSettings)
                bindingRow("Reload agent pane", key: $config.keyBindings.reloadAgentPane)
                bindingRow("Open disk status", key: $config.keyBindings.openDiskStatus)
                bindingRow("Open diff review", key: $config.keyBindings.openDiffReview)
                bindingRow("New terminal tab", key: $config.keyBindings.newTerminalTab)
                bindingRow("Next terminal tab", key: $config.keyBindings.nextTerminalTab)
                bindingRow("Previous terminal tab", key: $config.keyBindings.previousTerminalTab)
                bindingRow("Close terminal tab", key: $config.keyBindings.closeTerminalTab)
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

    private var popupShortcutsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Popup Terminals")
                .font(.headline)
            Text("Press \(config.leaderKey), then the key, to open a floating terminal running the command.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !config.popupShortcuts.isEmpty {
                popupShortcutList
            }
            addPopupShortcutRow
        }
    }

    private var popupShortcutList: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Name").frame(width: 90, alignment: .leading)
                Text("Key").frame(width: 36, alignment: .leading)
                Text("Command").frame(maxWidth: .infinity, alignment: .leading)
                Text("Size").frame(width: 70, alignment: .leading)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Divider()
            ForEach($config.popupShortcuts) { $shortcut in
                HStack(spacing: 8) {
                    TextField("", text: $shortcut.name)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                    SingleCharField(value: $shortcut.key)
                    TextField("", text: $shortcut.command)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity)
                    Stepper(
                        "\(shortcut.sizePercent)%",
                        value: $shortcut.sizePercent,
                        in: 30...100,
                        step: 5
                    )
                    .frame(width: 70)
                    Button {
                        config.popupShortcuts.removeAll { $0.id == shortcut.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var addPopupShortcutRow: some View {
        HStack(spacing: 8) {
            TextField("name", text: $newPopupName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
            SingleCharField(value: $newPopupKey)
            TextField("command", text: $newPopupCommand)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity)
            Button("Add") {
                let name = newPopupName.trimmingCharacters(in: .whitespaces)
                let key = newPopupKey.trimmingCharacters(in: .whitespaces)
                let command = newPopupCommand.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty, !key.isEmpty, !command.isEmpty else { return }
                config.popupShortcuts.append(
                    ArgusConfig.PopupShortcut(
                        id: UUID().uuidString,
                        name: name,
                        key: key,
                        command: command,
                        sizePercent: 80
                    )
                )
                newPopupName = ""
                newPopupKey = ""
                newPopupCommand = ""
            }
            .disabled(
                newPopupName.trimmingCharacters(in: .whitespaces).isEmpty
                    || newPopupKey.trimmingCharacters(in: .whitespaces).isEmpty
                    || newPopupCommand.trimmingCharacters(in: .whitespaces).isEmpty
            )
        }
    }
}

// MARK: - Single-character text field

struct SingleCharField: View {
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
