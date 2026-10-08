import AppKit
import SwiftUI

extension Notification.Name {
    static let openDiskStatus = Notification.Name("argus.openDiskStatus")
    static let diskSpaceLow = Notification.Name("argus.diskSpaceLow")
}

/// Floating popup showing disk usage and cleanup candidates.
/// Created fresh on each open; destroyed when the user closes it.
@MainActor
final class DiskStatusWindow: NSObject, NSWindowDelegate, ObservableObject {
    private var window: NSWindow?

    func open(store: DiskMonitorStore, scanner: DiskCleanupScanner) {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let screenFrame = NSScreen.popupVisibleFrame
        let size = CGSize(width: 560, height: 540)
        let origin = NSPoint(x: screenFrame.midX - size.width / 2, y: screenFrame.midY - size.height / 2)
        let win = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Disk Space"
        win.level = .floating
        win.isReleasedWhenClosed = false
        win.contentView = NSHostingView(rootView: DiskStatusView(store: store, scanner: scanner))
        win.delegate = self
        win.makeKeyAndOrderFront(nil)
        window = win
    }

    func windowWillClose(_: Notification) {
        window = nil
    }
}
