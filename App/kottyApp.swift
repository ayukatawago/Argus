import AppKit
import SwiftUI

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

            // Ctrl+B enters leader mode. A second Ctrl+B while in leader mode
            // passes the keystroke through (useful for nested tmux).
            if modifiers == [.control] && char == "b" {
                if self.awaitingLeader {
                    self.awaitingLeader = false
                    self.leaderTimer?.invalidate()
                    return event
                }
                self.awaitingLeader = true
                self.leaderTimer?.invalidate()
                self.leaderTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
                    self?.awaitingLeader = false
                }
                return nil
            }

            // Leader sequences (no modifier required on the second key)
            if self.awaitingLeader && modifiers.isEmpty {
                self.awaitingLeader = false
                self.leaderTimer?.invalidate()
                let nc = NotificationCenter.default
                switch char {
                case "h": nc.post(name: .focusShellPane, object: nil);         return nil
                case "l": nc.post(name: .focusAgentPane, object: nil);         return nil
                case "j": nc.post(name: .selectNextWorktree, object: nil);     return nil
                case "k": nc.post(name: .selectPreviousWorktree, object: nil); return nil
                case "g": nc.post(name: .openLazygit, object: nil);            return nil
                case "r": nc.post(name: .refreshWorkspace, object: nil);       return nil
                default: break
                }
            }

            // ⌘⇧G as a direct shortcut for lazygit (keeps the menu item working)
            if modifiers == [.command, .shift] && char == "g" {
                NotificationCenter.default.post(name: .openLazygit, object: nil)
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
            }
        }
    }

}
