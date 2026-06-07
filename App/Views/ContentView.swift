import GhosttyTerminal
import SwiftUI

struct ContentView: View {
    @StateObject private var terminal = TerminalController()

    var body: some View {
        TerminalSurfaceView(context: terminal.terminalState)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { terminal.start() }
    }
}
