import AppKit
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
                    let hidden = repo.worktrees.filter { store.hiddenWorktreeIDs.contains($0.id) }
                    let visible = repo.worktrees.filter { !store.hiddenWorktreeIDs.contains($0.id) }
                    Section {
                        ForEach(visible) { worktree in
                            WorktreeRow(worktree: worktree) {
                                if selectedWorktreeID == worktree.id { selectedWorktreeID = nil }
                                store.hideWorktree(id: worktree.id)
                            }
                            .tag(worktree.id)
                        }
                    } header: {
                        RepoHeader(
                            name: repo.name,
                            hiddenCount: hidden.count,
                            onRemove: {
                                if repo.worktrees.map(\.id).contains(selectedWorktreeID ?? "") {
                                    selectedWorktreeID = nil
                                }
                                store.removeRepo(mainPath: repo.mainPath)
                            },
                            onUnhide: { store.unhideWorktrees(repoID: repo.id) }
                        )
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: pickFolder) {
                    Image(systemName: "plus")
                }
                .help("Add repository or workspace folder")
            }
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        panel.message = "Select a git repository or a folder containing repositories."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.addRoot(url.path)
    }
}

private struct RepoHeader: View {
    let name: String
    let hiddenCount: Int
    let onRemove: () -> Void
    let onUnhide: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(name)
            Spacer()
            if hiddenCount > 0 {
                Button(action: onUnhide) {
                    Image(systemName: "eye")
                        .imageScale(.small)
                }
                .buttonStyle(.borderless)
                .help("Unhide \(hiddenCount) worktree\(hiddenCount == 1 ? "" : "s")")
            }
            Button(action: onRemove) {
                Image(systemName: "minus.circle")
                    .imageScale(.small)
            }
            .buttonStyle(.borderless)
            .help("Remove repository")
        }
    }
}

private struct WorktreeRow: View {
    let worktree: GitWorktree
    let sessionName: String?
    let onHide: () -> Void
    @State private var isHovered = false

    init(worktree: GitWorktree, sessionName: String? = nil, onHide: @escaping () -> Void) {
        self.worktree = worktree
        self.sessionName = sessionName
        self.onHide = onHide
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(URL(fileURLWithPath: worktree.path).lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let branch = worktree.branch {
                    Text(branch)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let name = sessionName {
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            Button(action: onHide) {
                Image(systemName: "eye.slash")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .opacity(isHovered ? 1 : 0)
        }
        .onHover { isHovered = $0 }
    }
}
