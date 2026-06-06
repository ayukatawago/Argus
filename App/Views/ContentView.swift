import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var ghosttyApp: GhosttyApp

    var body: some View {
        Group {
            switch ghosttyApp.readiness {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .failed:
                Text("Failed to initialize terminal engine.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .ready:
                TerminalSurface()
            }
        }
    }
}
