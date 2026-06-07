import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Fires before state restoration — wipe any saved window state so crash-recovery
        // replays don't create extra surfaces on the next launch.
        guard let bundleID = Bundle.main.bundleIdentifier,
            let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
        else { return }
        let savedStateURL = libraryURL
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
    }
}
