import AppKit

extension NSScreen {
    /// The visible frame a popup window should be sized and centred against: the key window's
    /// screen, else the main window's, else the primary display. Falls back to a plain 1440×900
    /// rectangle when no display is attached at all (e.g. mid display-reconfiguration), where
    /// indexing `NSScreen.screens[0]` — what each popup did before — would trap.
    @MainActor
    static var popupVisibleFrame: CGRect {
        let screen = NSApp.keyWindow?.screen ?? NSApp.mainWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first
        return screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }
}
