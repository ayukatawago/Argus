import AgentStateKit
import AppKit
import ArgusConfigKit
import ArgusSupport
import SwiftUI
import UniformTypeIdentifiers
import Workspaces

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
    @EnvironmentObject var configStore: ArgusConfigStore
    let onRelease: (String) -> Void
    @State private var dropTargetRepoID: String?
    @State private var showPickFolder = false
    @State private var showDeleteConfirmation = false
    @State private var deleteTarget: WorktreeDeleteTarget?
    @State private var showAddWorktree = false
    @State private var addWorktreeRepo: GitRepo?
    @State private var newBranchName = ""
    @State private var showAddWorktreeError = false
    @State private var showDeleteError = false
    @State private var deleteError = ""
    @State private var addWorktreeError = ""
    @State private var filterQuery = ""
    @State private var attentionOnly = false
    @FocusState private var filterFocused: Bool

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
                    .accessibilityLabel("Add repository or workspace folder")
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
            .alert("Could not remove worktree", isPresented: $showDeleteError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteError)
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
        let counts = AgentCounts(store: store, agentBus: agentBus)
        let shownRepos = SidebarFilter.apply(
            repos: store.repos, query: filterQuery,
            attentionIDs: attentionOnly ? counts.needsAttention : nil)
        return VStack(spacing: 0) {
            if !store.repos.isEmpty {
                SidebarFilterBar(
                    query: $filterQuery, attentionOnly: $attentionOnly, counts: counts, isFocused: $filterFocused)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if store.repos.isEmpty {
                        SidebarEmptyState(onAddFolder: { showPickFolder = true })
                    } else if shownRepos.isEmpty {
                        Text(attentionOnly && filterQuery.isEmpty ? "No worktrees need attention" : "No matches")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                            .padding()
                    } else {
                        ForEach(shownRepos) { repo in
                            repoSection(for: repo, isDropTarget: dropTargetRepoID == repo.id)
                        }
                    }
                }
                .padding(.bottom, 4)
            }
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.upArrow) { moveSelection(forward: false, in: shownRepos) }
            .onKeyPress(.downArrow) { moveSelection(forward: true, in: shownRepos) }

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
                .accessibilityLabel("Settings")
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
            repoHeader(for: repo, hiddenCount: hidden.count)
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

    private func repoHeader(for repo: GitRepo, hiddenCount: Int) -> some View {
        RepoHeader(
            name: repo.name,
            isGitRepo: repo.isGitRepo,
            hiddenCount: hiddenCount,
            agentOverride: configStore.config.projectAgents[repo.mainPath],
            onAddWorktree: { addWorktree(for: repo) },
            onRemove: {
                if repo.worktrees.map(\.id).contains(selectedWorktreeID ?? "") {
                    selectedWorktreeID = nil
                }
                store.removeRepo(mainPath: repo.mainPath)
            },
            onUnhide: { store.unhideWorktrees(repoID: repo.id) },
            onSelectAgent: { selection in
                configStore.config.setAgent(selection, forProjectPath: repo.mainPath)
                configStore.save()
            }
        )
    }

    @ViewBuilder
    private func worktreeRows(for repo: GitRepo, visible: [GitWorktree]) -> some View {
        ForEach(visible) { worktree in
            let isActive = activeTerminalIDs.contains(worktree.id)
            let worktreeState = agentBus.worktreeState(for: worktree.id)
            WorktreeRow(
                worktree: worktree,
                isActive: isActive,
                isSelected: selectedWorktreeID == worktree.id,
                agentState: worktreeState.state,
                agentType: worktreeState.agent,
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
            .contextMenu { worktreeContextMenu(worktree, in: repo, isActive: isActive) }
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
            let result = await ProcessRunner.run(
                "/usr/bin/git", ["-C", repo.mainPath, "worktree", "remove", "--force", worktree.path], timeout: 10)
            // The row was hidden optimistically above. If git refused (a locked worktree, a path in
            // use), bring it back and say why, rather than leaving a worktree that still exists on
            // disk invisible in the sidebar.
            if !result.succeeded {
                store.unhideWorktree(id: worktree.id)
                let detail = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
                deleteError = detail.isEmpty ? "git could not remove \(worktree.path)." : detail
                showDeleteError = true
            }
            await store.refresh()
        }
    }

    private func addWorktree(for repo: GitRepo) {
        newBranchName = ""
        addWorktreeRepo = repo
        showAddWorktree = true
    }

    private func createWorktree(branch: String, in repo: GitRepo) async {
        guard let newPath = WorktreePathPlanner.path(forBranch: branch, repoMainPath: repo.mainPath) else {
            addWorktreeError = "'\(branch)' can't be used as a worktree folder name."
            showAddWorktreeError = true
            return
        }
        let result = await ProcessRunner.run(
            "/usr/bin/git", ["-C", repo.mainPath, "worktree", "add", newPath, "-b", branch], timeout: 10)
        if !result.succeeded {
            let detail = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            addWorktreeError =
                detail.isEmpty
                ? "Make sure the branch '\(branch)' does not already exist."
                : detail
            showAddWorktreeError = true
        }
        await store.refresh()
    }
}

extension SidebarView {
    @ViewBuilder
    private func worktreeContextMenu(_ worktree: GitWorktree, in repo: GitRepo, isActive: Bool) -> some View {
        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: worktree.path)])
        }
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(worktree.path, forType: .string)
        }
        Button("Open Diff Review") {
            selectedWorktreeID = worktree.id
            DispatchQueue.main.async { NotificationCenter.default.post(name: .openDiffReview, object: nil) }
        }
        Divider()
        if isActive {
            Button("Release Terminal Sessions") { onRelease(worktree.id) }
        }
        Button("Hide Worktree") {
            if selectedWorktreeID == worktree.id { selectedWorktreeID = nil }
            store.hideWorktree(id: worktree.id)
        }
        if !worktree.isMain {
            Button("Delete Worktree…", role: .destructive) { deleteWorktree(worktree, in: repo) }
        }
    }

    /// Up/down in the sidebar moves the selection through whatever worktrees are currently shown
    /// (after filtering, hidden ones excluded), wrapping at either end.
    private func moveSelection(forward: Bool, in repos: [GitRepo]) -> KeyPress.Result {
        let ids = repos.flatMap(\.worktrees).map(\.id).filter { !store.hiddenWorktreeIDs.contains($0) }
        guard let next = WorktreeNavigator.next(from: selectedWorktreeID, in: ids, forward: forward) else {
            return .ignored
        }
        selectedWorktreeID = next
        return .handled
    }
}
