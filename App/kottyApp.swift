import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyEventMonitor: Any?
    private var mouseEventMonitor: Any?
    private var awaitingLeader = false
    private var leaderTimer: Timer?

    func applicationDidFinishLaunching(_: Notification) {
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
            let char = event.charactersIgnoringModifiers?.lowercased()

            let config = KottyConfigStore.shared.config

            // Leader key: enter leader mode, or pass through on double press (e.g. for nested tmux).
            if let (leaderMods, leaderChar) = Self.parseLeaderKey(config.leaderKey),
                modifiers == leaderMods, char == leaderChar
            {
                if self.awaitingLeader {
                    self.awaitingLeader = false
                    self.leaderTimer?.invalidate()
                    return event
                }
                self.awaitingLeader = true
                self.leaderTimer?.invalidate()
                self.leaderTimer = Timer.scheduledTimer(
                    withTimeInterval: config.leaderTimeoutSeconds,
                    repeats: false
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.awaitingLeader = false }
                }
                return nil
            }

            // Leader sequences (no modifier required on the second key)
            if self.awaitingLeader && modifiers.isEmpty {
                self.awaitingLeader = false
                self.leaderTimer?.invalidate()
                if let char, let name = Self.notificationMap(from: config.keyBindings)[char] {
                    NotificationCenter.default.post(name: name, object: nil)
                    return nil
                }
            }

            // ⌘⇧G as a direct shortcut for lazygit (keeps the menu item working)
            if modifiers == [.command, .shift] && char == "g" {
                NotificationCenter.default.post(name: .openLazygit, object: nil)
                return nil
            }

            // ⌘⇧N as a direct shortcut for nvim (keeps the menu item working)
            if modifiers == [.command, .shift] && char == "n" {
                NotificationCenter.default.post(name: .openNvim, object: nil)
                return nil
            }

            NotificationCenter.default.post(name: .workspaceInteracted, object: nil)
            return event
        }

        mouseEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            NotificationCenter.default.post(name: .workspaceInteracted, object: nil)
            return event
        }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Fires before state restoration — wipe any saved window state so crash-recovery
        // replays don't create extra surfaces on the next launch.
        guard let bundleID = Bundle.main.bundleIdentifier,
            let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
        else { return }
        let savedStateURL =
            libraryURL
            .appendingPathComponent("Saved Application State/\(bundleID).savedState")
        try? FileManager.default.removeItem(at: savedStateURL)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            sender.windows
                .first(where: { !($0 is NSPanel) })
                .map { $0.makeKeyAndOrderFront(nil) }
            sender.activate(ignoringOtherApps: true)
        }
        return false
    }

    // MARK: - Helpers

    private static func parseLeaderKey(_ key: String) -> (NSEvent.ModifierFlags, String)? {
        let parts = key.lowercased().split(separator: "+").map(String.init)
        guard let char = parts.last, !char.isEmpty else { return nil }
        var flags: NSEvent.ModifierFlags = []
        for part in parts.dropLast() {
            switch part {
            case "ctrl": flags.insert(.control)
            case "cmd", "command": flags.insert(.command)
            case "opt", "option", "alt": flags.insert(.option)
            case "shift": flags.insert(.shift)
            default: break
            }
        }
        return (flags, char)
    }

    private static func notificationMap(from bindings: KottyConfig.KeyBindings) -> [String: Notification.Name] {
        [
            bindings.focusShellPane: .focusShellPane,
            bindings.focusAgentPane: .focusAgentPane,
            bindings.selectNextWorktree: .selectNextWorktree,
            bindings.selectPreviousWorktree: .selectPreviousWorktree,
            bindings.openLazygit: .openLazygit,
            bindings.openNvim: .openNvim,
            bindings.refreshWorkspace: .refreshWorkspace,
            bindings.openMarkdownPreview: .openMarkdownPreview,
            bindings.openSettings: .openSettings,
            bindings.reloadAgentPane: .reloadAgentPane,
        ]
    }
}

@main
struct KottyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("kotty", id: "main") {
            ContentView()
        }
        .defaultSize(width: 1200, height: 800)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .windowArrangement) {
                Button("Open lazygit") {
                    NotificationCenter.default.post(name: .openLazygit, object: nil)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                Button("Open nvim") {
                    NotificationCenter.default.post(name: .openNvim, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }

        Window("Settings", id: "settings") {
            SettingsRootView()
                .environmentObject(KottyConfigStore.shared)
        }
        .defaultSize(width: 540, height: 460)
        .windowResizability(.contentMinSize)
    }
}
