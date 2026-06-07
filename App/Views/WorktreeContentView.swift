import AppKit
import SwiftUI

/// Wraps the persistent TerminalHost NSView in SwiftUI.
/// All terminal switching is handled by TerminalHost.activate(id:) — this view
/// does nothing on update because the host manages its own subview visibility.
struct WorktreeContentView: NSViewRepresentable {
    let host: TerminalHost

    func makeNSView(context _: Context) -> TerminalHost { host }
    func updateNSView(_: TerminalHost, context _: Context) {}
}
