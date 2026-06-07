import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: WorkspaceStore
    @Binding var selectedWorktreeID: String?

    var body: some View {
        List(selection: $selectedWorktreeID) {
            if store.repos.isEmpty {
                Text("No git repos found")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                ForEach(store.repos) { repo in
                    Section(repo.name) {
                        ForEach(repo.worktrees) { worktree in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.secondary.opacity(0.4))
                                    .frame(width: 8, height: 8)
                                Text(worktree.branch ?? "(detached)")
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .tag(worktree.id)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
    }
}
