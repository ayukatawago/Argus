import SwiftUI

struct WorktreeContentView: View {
    let shellHost: TerminalHost
    let agentHost: TerminalHost

    var body: some View {
        HSplitView {
            TerminalHostView(host: shellHost).frame(minWidth: 200)
            TerminalHostView(host: agentHost).frame(minWidth: 200)
        }
    }
}

private struct TerminalHostView: NSViewRepresentable {
    let host: TerminalHost

    func makeNSView(context _: Context) -> TerminalHost { host }
    func updateNSView(_: TerminalHost, context _: Context) {}
}
