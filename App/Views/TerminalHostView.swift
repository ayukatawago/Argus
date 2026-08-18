import AppKit
import SwiftUI

/// Wraps a `TerminalHost` NSView unchanged, so SwiftUI can place it in a layout tree. Shared by
/// `WorktreeContentView`'s shell pane and `AgentPaneView`'s agent panes.
struct TerminalHostView: NSViewRepresentable {
    let host: TerminalHost

    func makeNSView(context _: Context) -> TerminalHost { host }
    func updateNSView(_: TerminalHost, context _: Context) {}
}
