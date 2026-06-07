import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyEventMonitor: Any?

    func applicationDidFinishLaunching(_: Notification) {
        // Register ⌘⇧G via a local event monitor so it fires reliably even when
        // the terminal surface has keyboard focus and might swallow menu key equivalents.
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let onlyCommandShift =
                event.modifierFlags
                .intersection([.command, .shift, .option, .control]) == [.command, .shift]
            guard onlyCommandShift, event.charactersIgnoringModifiers?.lowercased() == "g" else {
                return event
            }
            NotificationCenter.default.post(name: .openLazygit, object: nil)
            return nil
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
                Divider()
                Button("Install Claude Code Hooks…") {
                    KottyApp.installHooks()
                }
            }
        }
    }

    private static func installHooks() {
        do {
            try HookInstaller.install()
            let alert = NSAlert()
            alert.messageText = "Hooks installed"
            alert.informativeText = "Claude Code hooks have been added to ~/.claude/settings.json."
            alert.alertStyle = .informational
            alert.runModal()
        }
        catch {
            NSAlert(error: error).runModal()
        }
    }
}
