import AppKit
import SwiftUI

@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate, ObservableObject {
    private var window: NSWindow?

    func open() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = NSHostingController(rootView: SettingsRootView(configStore: KottyConfigStore.shared))
        let win = NSWindow(contentViewController: controller)
        win.title = "Settings"
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        win.setContentSize(NSSize(width: 640, height: 460))
        win.minSize = NSSize(width: 500, height: 360)
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = win
    }

    func windowWillClose(_: Notification) {
        window = nil
    }
}

// MARK: - Root layout

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case keyboard = "Keyboard"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .keyboard: "keyboard"
        }
    }
}

private struct SettingsRootView: View {
    @ObservedObject var configStore: KottyConfigStore
    @State private var selected: SettingsCategory = .keyboard

    var body: some View {
        HStack(spacing: 0) {
            navColumn
            Divider()
            contentColumn
        }
        .frame(minWidth: 500, minHeight: 360)
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
        .frame(width: 160)
        .background(Color(nsColor: .windowBackgroundColor))
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
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func navRow(_ cat: SettingsCategory) -> some View {
        Button(action: { selected = cat }) {
            Label(cat.rawValue, systemImage: cat.icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    selected == cat ? Color.accentColor.opacity(0.2) : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Keyboard section

private struct KeyboardSettingsView: View {
    @Binding var config: KottyConfig

    private let leaderOptions = ["ctrl+b", "ctrl+a", "ctrl+x", "ctrl+space"]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            leaderSection
            bindingsSection
        }
    }

    private var leaderSection: some View {
        SettingsSection(title: "Leader Key") {
            row("Key combo") {
                Picker("", selection: $config.leaderKey) {
                    ForEach(leaderOptions, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 130)
            }
            row("Timeout") {
                Slider(value: $config.leaderTimeoutSeconds, in: 0.5...3.0, step: 0.1)
                    .frame(width: 150)
                Text(String(format: "%.1f s", config.leaderTimeoutSeconds))
                    .monospacedDigit()
                    .frame(width: 42, alignment: .leading)
            }
        }
    }

    private var bindingsSection: some View {
        SettingsSection(title: "Key Bindings") {
            VStack(spacing: 6) {
                bindingRow("Focus shell pane", key: $config.keyBindings.focusShellPane)
                bindingRow("Focus agent pane", key: $config.keyBindings.focusAgentPane)
                bindingRow("Next worktree", key: $config.keyBindings.selectNextWorktree)
                bindingRow("Previous worktree", key: $config.keyBindings.selectPreviousWorktree)
                bindingRow("Open lazygit", key: $config.keyBindings.openLazygit)
                bindingRow("Refresh workspace", key: $config.keyBindings.refreshWorkspace)
                bindingRow("Open markdown preview", key: $config.keyBindings.openMarkdownPreview)
                bindingRow("Open settings", key: $config.keyBindings.openSettings)
            }
            Text("Each binding is activated with \(config.leaderKey) followed by the key.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .frame(width: 120, alignment: .leading)
            content()
        }
    }

    private func bindingRow(_ label: String, key: Binding<String>) -> some View {
        HStack {
            Text(label)
                .frame(width: 200, alignment: .leading)
            SingleCharField(value: key)
        }
    }
}

// MARK: - Reusable components

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
    }
}

private struct SingleCharField: View {
    @Binding var value: String

    var body: some View {
        TextField("", text: $value)
            .multilineTextAlignment(.center)
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .frame(width: 40)
            .onChange(of: value) { _, newValue in
                if newValue.count > 1 { value = String(newValue.suffix(1)) }
            }
    }
}
