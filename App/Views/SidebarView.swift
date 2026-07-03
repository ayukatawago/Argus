import SwiftUI
import UniformTypeIdentifiers

private struct WorktreeDeleteTarget {
    let worktree: GitWorktree
    let repo: GitRepo
}

struct SidebarView: View {
    @ObservedObject var store: WorkspaceStore
    @Binding var selectedWorktreeID: String?
    let activeTerminalIDs: Set<String>
    @ObservedObject var agentBus: AgentStateBus
    @ObservedObject var shellStateBus: ShellStateBus
    @ObservedObject var prMonitor: PRMonitorStore
    let onRelease: (String) -> Void
    @State private var dropTargetRepoID: String?
    @State private var showPickFolder = false
    @State private var showDeleteConfirmation = false
    @State private var deleteTarget: WorktreeDeleteTarget?
    @State private var showAddWorktree = false
    @State private var addWorktreeRepo: GitRepo?
    @State private var newBranchName = ""
    @State private var showAddWorktreeError = false
    @State private var addWorktreeError = ""

    var body: some View {
        repoList
            .frame(minWidth: 200)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(
                        action: { showPickFolder = true },
                        label: { Image(systemName: "plus") }
                    )
                    .help("Add repository or workspace folder")
                }
            }
            .alert(deleteDialogTitle, isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    if let target = deleteTarget { performDelete(target) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The working directory will be permanently removed, including any uncommitted changes.")
            }
            .alert("New Worktree", isPresented: $showAddWorktree) {
                TextField("feature-branch", text: $newBranchName)
                Button("Create") {
                    let branch = newBranchName.trimmingCharacters(in: .whitespaces)
                    let repo = addWorktreeRepo
                    newBranchName = ""
                    addWorktreeRepo = nil
                    guard !branch.isEmpty, let repo else { return }
                    Task { await createWorktree(branch: branch, in: repo) }
                }
                Button("Cancel", role: .cancel) { newBranchName = "" }
            } message: {
                Text("Enter a branch name for the new worktree.")
            }
            .alert("Could not create worktree", isPresented: $showAddWorktreeError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(addWorktreeError)
            }
            .fileImporter(isPresented: $showPickFolder, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result {
                    store.addRoot(url.path)
                }
            }
    }

    private var deleteDialogTitle: String {
        guard let target = deleteTarget else { return "Delete Worktree?" }
        let name = URL(fileURLWithPath: target.worktree.path).lastPathComponent
        return "Delete Worktree \"\(name)\"?"
    }

    private var repoList: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if store.repos.isEmpty {
                        Text("No folders found")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                            .padding()
                    } else {
                        ForEach(store.repos) { repo in
                            repoSection(for: repo, isDropTarget: dropTargetRepoID == repo.id)
                        }
                    }
                }
                .padding(.bottom, 4)
            }

            if !ArgusConfigStore.shared.config.github.token.isEmpty {
                Divider()
                PRMonitorView(store: prMonitor)
            }

            Divider()

            HStack(spacing: 0) {
                Button {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                } label: {
                    Image(systemName: "gear")
                        .imageScale(.medium)
                }
                .buttonStyle(.borderless)
                .help("Settings (⌘,)")
                .padding(8)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func repoSection(for repo: GitRepo, isDropTarget: Bool) -> some View {
        let hidden = repo.worktrees.filter { store.hiddenWorktreeIDs.contains($0.id) }
        let visible = repo.worktrees.filter { !store.hiddenWorktreeIDs.contains($0.id) }
        VStack(alignment: .leading, spacing: 0) {
            RepoHeader(
                name: repo.name,
                isGitRepo: repo.isGitRepo,
                hiddenCount: hidden.count,
                onAddWorktree: { addWorktree(for: repo) },
                onRemove: {
                    if repo.worktrees.map(\.id).contains(selectedWorktreeID ?? "") {
                        selectedWorktreeID = nil
                    }
                    store.removeRepo(mainPath: repo.mainPath)
                },
                onUnhide: { store.unhideWorktrees(repoID: repo.id) }
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 2)
            .contentShape(Rectangle())
            .draggable(repo.id) {
                Text(repo.name)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            worktreeRows(for: repo, visible: visible)
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .dropDestination(for: String.self) { items, _ in
            guard let draggedID = items.first,
                draggedID != repo.id,
                let fromIdx = store.repos.firstIndex(where: { $0.id == draggedID }),
                let toIdx = store.repos.firstIndex(where: { $0.id == repo.id })
            else { return false }
            store.moveRepo(fromIndex: fromIdx, toIndex: toIdx)
            return true
        } isTargeted: { nowTargeted in
            if nowTargeted {
                dropTargetRepoID = repo.id
            } else if dropTargetRepoID == repo.id {
                dropTargetRepoID = nil
            }
        }
        .overlay(alignment: .top) { dropIndicator(isTarget: isDropTarget) }
    }

    @ViewBuilder
    private func worktreeRows(for repo: GitRepo, visible: [GitWorktree]) -> some View {
        ForEach(visible) { worktree in
            let isActive = activeTerminalIDs.contains(worktree.id)
            WorktreeRow(
                worktree: worktree,
                isActive: isActive,
                isSelected: selectedWorktreeID == worktree.id,
                agentState: agentBus.state(for: worktree.id),
                agentType: agentBus.agentType(for: worktree.id),
                isShellBusy: shellStateBus.busyPaths.contains(worktree.id),
                onRelease: isActive ? { onRelease(worktree.id) } : nil,
                onDelete: worktree.isMain ? nil : { deleteWorktree(worktree, in: repo) },
                onHide: {
                    if selectedWorktreeID == worktree.id { selectedWorktreeID = nil }
                    store.hideWorktree(id: worktree.id)
                }
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 1)
            .contentShape(Rectangle())
            .onTapGesture { selectedWorktreeID = worktree.id }
        }
    }

    @ViewBuilder
    private func dropIndicator(isTarget: Bool) -> some View {
        if isTarget {
            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 2)
        }
    }

    private func deleteWorktree(_ worktree: GitWorktree, in repo: GitRepo) {
        deleteTarget = WorktreeDeleteTarget(worktree: worktree, repo: repo)
        showDeleteConfirmation = true
    }

    private func performDelete(_ target: WorktreeDeleteTarget) {
        let worktree = target.worktree
        let repo = target.repo
        if activeTerminalIDs.contains(worktree.id) { onRelease(worktree.id) }
        if selectedWorktreeID == worktree.id { selectedWorktreeID = nil }
        store.hideWorktree(id: worktree.id)
        Task {
            await Task.detached(priority: .userInitiated) {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                proc.arguments = ["-C", repo.mainPath, "worktree", "remove", "--force", worktree.path]
                proc.standardOutput = Pipe()
                proc.standardError = Pipe()
                try? proc.run()
                proc.waitUntilExit()
            }.value
            await store.refresh()
        }
    }

    private func addWorktree(for repo: GitRepo) {
        newBranchName = ""
        addWorktreeRepo = repo
        showAddWorktree = true
    }

    private func createWorktree(branch: String, in repo: GitRepo) async {
        let safeName = branch.replacingOccurrences(of: "/", with: "-")
        let parent = URL(fileURLWithPath: repo.mainPath).deletingLastPathComponent().path
        let newPath = (parent as NSString).appendingPathComponent(safeName)
        let exitCode = await Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            proc.arguments = ["-C", repo.mainPath, "worktree", "add", newPath, "-b", branch]
            proc.standardOutput = Pipe()
            proc.standardError = Pipe()
            guard (try? proc.run()) != nil else { return Int32(-1) }
            proc.waitUntilExit()
            return proc.terminationStatus
        }.value
        if exitCode != 0 {
            addWorktreeError = "Make sure the branch '\(branch)' does not already exist."
            showAddWorktreeError = true
        }
        await store.refresh()
    }
}

private struct WorktreeRow: View {
    let worktree: GitWorktree
    let isActive: Bool
    let isSelected: Bool
    let agentState: AgentState
    let agentType: AgentType
    let isShellBusy: Bool
    let onRelease: (() -> Void)?
    let onDelete: (() -> Void)?
    let onHide: () -> Void
    @State private var isHovered = false

    init(
        worktree: GitWorktree,
        isActive: Bool = false,
        isSelected: Bool = false,
        agentState: AgentState = .idle,
        agentType: AgentType = .claude,
        isShellBusy: Bool = false,
        onRelease: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onHide: @escaping () -> Void
    ) {
        self.worktree = worktree
        self.isActive = isActive
        self.isSelected = isSelected
        self.agentState = agentState
        self.agentType = agentType
        self.isShellBusy = isShellBusy
        self.onRelease = onRelease
        self.onDelete = onDelete
        self.onHide = onHide
    }

    var body: some View {
        HStack(spacing: 8) {
            AgentDot(state: agentState, agentType: agentType)
            VStack(alignment: .leading, spacing: 2) {
                worktreeName
                Text(worktree.branch ?? " ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .opacity(worktree.branch == nil ? 0 : 1)
            }
            Spacer()
            if let onRelease {
                Button(action: onRelease) {
                    Image(systemName: "xmark.circle")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Release terminal sessions")
                .opacity(isHovered ? 1 : 0)
            }
            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Delete worktree")
                .opacity(isHovered ? 1 : 0)
            }
            Button(action: onHide) {
                Image(systemName: "eye.slash")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Hide worktree")
            .opacity(isHovered ? 1 : 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            AgentStateBackground(
                agentState: agentState,
                isActive: isActive,
                isSelected: isSelected,
                agentType: agentType,
                isShellBusy: isShellBusy
            )
        )
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var worktreeName: some View {
        let name = URL(fileURLWithPath: worktree.path).lastPathComponent
        if agentState == .running && agentType == .codex {
            ShimmerText(text: name, color: .white)
        } else {
            Text(name)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
