import AppKit
import SwiftUI

/// Wraps a `TerminalHost` NSView unchanged, so SwiftUI can place it in a layout tree. Shared by
/// `WorktreeContentView`'s shell pane and `AgentPaneView`'s agent panes.
///
/// `updateNSView` is deliberately empty: `makeNSView` runs once per view *identity*, and if a
/// later render passes a different `host` into the same identity slot, SwiftUI won't call
/// `makeNSView` again — it calls this no-op instead, and the originally-mounted host stays on
/// screen forever. Any call site whose `host` can change over time (not just its properties, the
/// value itself) must force a fresh identity per host, e.g. `.id(role)` — see `AgentPaneView`.
struct TerminalHostView: NSViewRepresentable {
    let host: TerminalHost

    func makeNSView(context _: Context) -> TerminalHost { host }
    func updateNSView(_: TerminalHost, context _: Context) {}
}
