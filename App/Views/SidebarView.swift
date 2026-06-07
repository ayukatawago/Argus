import AppKit
import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: WorkspaceStore
    @Binding var selectedWorktreeID: String?
    let activeTerminalIDs: Set<String>

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
                    .selectionDisabled()
                    ForEach(visible) { worktree in
                        WorktreeRow(
                            worktree: worktree,
                            isActive: activeTerminalIDs.contains(worktree.id),
                            isSelected: selectedWorktreeID == worktree.id
                        ) {
                            if selectedWorktreeID == worktree.id { selectedWorktreeID = nil }
                            store.hideWorktree(id: worktree.id)
                        }
                        .tag(worktree.id)
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
                .font(.headline)
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
                    .imageScale(.medium)
            }
            .buttonStyle(.borderless)
            .help("Remove repository")
        }
    }
}

private struct WorktreeRow: View {
    let worktree: GitWorktree
    let sessionName: String?
    let isActive: Bool
    let isSelected: Bool
    let onHide: () -> Void
    @State private var isHovered = false

    init(
        worktree: GitWorktree,
        sessionName: String? = nil,
        isActive: Bool = false,
        isSelected: Bool = false,
        onHide: @escaping () -> Void
    ) {
        self.worktree = worktree
        self.sessionName = sessionName
        self.isActive = isActive
        self.isSelected = isSelected
        self.onHide = onHide
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(URL(fileURLWithPath: worktree.path).lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(worktree.branch ?? " ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .opacity(worktree.branch == nil ? 0 : 1)
                Text(sessionName ?? " ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .opacity(sessionName == nil ? 0 : 1)
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
        .padding(.vertical, 4)
        .onHover { isHovered = $0 }
        .listRowBackground(
            isActive && !isSelected ? Color.accentColor.opacity(0.1) : Color.clear
        )
    }
}
