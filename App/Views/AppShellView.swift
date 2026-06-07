import GhosttyTerminal
import SwiftUI

struct AppShellView: View {
    @StateObject private var store = WorkspaceStore()
    @StateObject private var terminal = TerminalController()
    @State private var selectedWorktreeID: String?

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store, selectedWorktreeID: $selectedWorktreeID)
        } detail: {
            TerminalSurfaceView(context: terminal.terminalState)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            store.load()
            terminal.start()
        }
        .onChange(of: selectedWorktreeID) { _, newID in
            guard let id = newID,
                  let worktree = store.repos.flatMap(\.worktrees).first(where: { $0.id == id })
            else { return }
            terminal.restart(workingDirectory: worktree.path)
        }
    }
}
