import SwiftUI
import Workspaces

extension View {
    /// CLI-originated (`argus add`) request — track the repo, but don't select it: selecting spawns
    /// a shell and agent, which a URL must not trigger on its own.
    func onReceiveAddRepo(store: WorkspaceStore) -> some View {
        onReceive(NotificationCenter.default.publisher(for: .addRepoForPath)) { notification in
            guard let path = notification.userInfo?["path"] as? String else { return }
            store.addRepo(path)
        }
    }
}
