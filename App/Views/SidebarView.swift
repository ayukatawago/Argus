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
    let onRelease: (String) -> Void
    @State private var dropTargetRepoID: String?
    @State private var showPickFolder = false
    @State private var showDeleteConfirmation = false
    @State private var deleteTarget: WorktreeDeleteTarget?
    @State private var showForceDeleteAlert = false
    @State private var forceDeleteTarget: WorktreeDeleteTarget?
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
                    Button(action: { showPickFolder = true }) {
                        Image(systemName: "plus")
                    }
                    .help("Add repository or workspace folder")
                }
            }
            .confirmationDialog(
                deleteDialogTitle,
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let target = deleteTarget { performDelete(target) }
                }
            } message: {
                Text("The working directory will be removed. Committed work is safe in the repository.")
            }
            .alert("Worktree has uncommitted changes", isPresented: $showForceDeleteAlert) {
                Button("Force Delete", role: .destructive) {
                    if let target = forceDeleteTarget { performForceDelete(target) }
                }
                Button("Cancel", role: .cancel) { Task { await store.refresh() } }
            } message: {
                let name = forceDeleteTarget.map {
                    URL(fileURLWithPath: $0.worktree.path).lastPathComponent
                } ?? ""
                Text("Force delete will discard all uncommitted changes in \"\(name)\" permanently.")
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
                        Text("No git repos found")
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
            .focusable()
            .onKeyPress(.upArrow) { navigateSelection(forward: false); return .handled }
            .onKeyPress(.downArrow) { navigateSelection(forward: true); return .handled }

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
            ForEach(visible) { worktree in
                let isActive = activeTerminalIDs.contains(worktree.id)
                WorktreeRow(
                    worktree: worktree,
                    isActive: isActive,
                    isSelected: selectedWorktreeID == worktree.id,
                    agentState: agentBus.state(for: worktree.id),
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
        .overlay(alignment: .top) {
            if isDropTarget {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
            }
        }
    }

    private func navigateSelection(forward: Bool) {
        let all = store.repos.flatMap(\.worktrees).filter { !store.hiddenWorktreeIDs.contains($0.id) }
        guard !all.isEmpty else { return }
        guard let current = selectedWorktreeID,
              let idx = all.firstIndex(where: { $0.id == current })
        else { selectedWorktreeID = all.first?.id; return }
        let next = forward ? (idx + 1) % all.count : (idx - 1 + all.count) % all.count
        selectedWorktreeID = all[next].id
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
        Task {
            let exitCode = await Task.detached(priority: .userInitiated) {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                proc.arguments = ["-C", repo.mainPath, "worktree", "remove", worktree.path]
                proc.standardOutput = Pipe()
                proc.standardError = Pipe()
                guard (try? proc.run()) != nil else { return Int32(-1) }
                proc.waitUntilExit()
                return proc.terminationStatus
            }.value
            if exitCode != 0 {
                forceDeleteTarget = WorktreeDeleteTarget(worktree: worktree, repo: repo)
                showForceDeleteAlert = true
            } else {
                await store.refresh()
            }
        }
    }

    private func performForceDelete(_ target: WorktreeDeleteTarget) {
        Task {
            await Task.detached(priority: .userInitiated) {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                proc.arguments = ["-C", target.repo.mainPath, "worktree", "remove", "--force", target.worktree.path]
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

private struct RepoHeader: View {
    let name: String
    let hiddenCount: Int
    let onAddWorktree: () -> Void
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
            Button(action: onAddWorktree) {
                Image(systemName: "plus.circle")
                    .imageScale(.medium)
            }
            .buttonStyle(.borderless)
            .help("Add worktree")
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
    let isActive: Bool
    let isSelected: Bool
    let agentState: AgentState
    let onRelease: (() -> Void)?
    let onDelete: (() -> Void)?
    let onHide: () -> Void
    @State private var isHovered = false

    init(
        worktree: GitWorktree,
        isActive: Bool = false,
        isSelected: Bool = false,
        agentState: AgentState = .idle,
        onRelease: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onHide: @escaping () -> Void
    ) {
        self.worktree = worktree
        self.isActive = isActive
        self.isSelected = isSelected
        self.agentState = agentState
        self.onRelease = onRelease
        self.onDelete = onDelete
        self.onHide = onHide
    }

    var body: some View {
        HStack(spacing: 8) {
            AgentDot(state: agentState)
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
            AgentStateBackground(agentState: agentState, isActive: isActive, isSelected: isSelected)
        )
        .onHover { isHovered = $0 }
    }
}

// MARK: - Agent state dot

private struct AgentDot: View {
    let state: AgentState

    private let frames: [String] = ["·", "✢", "✳", "✶", "✽", "*", "✶", "+", "·"]

    var body: some View {
        Group {
            if state == .running {
                TimelineView(.periodic(from: .now, by: 0.12)) { context in
                    let idx = Int(context.date.timeIntervalSinceReferenceDate / 0.12) % frames.count
                    Text(frames[idx])
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(claudePeach)
                        .frame(width: 10, height: 10)
                }
            } else {
                Circle()
                    .fill(dotColor)
                    .frame(width: 10, height: 10)
            }
        }
    }

    private var dotColor: Color {
        switch state {
        case .idle: Color.secondary.opacity(0.4)
        case .running: claudePeach
        case .waitingForApproval: Color.orange
        case .done: Color.green.opacity(0.8)
        }
    }
}

// MARK: - Row background

/// Provides the colored row background that reflects agent state.
private struct AgentStateBackground: View {
    let agentState: AgentState
    let isActive: Bool
    let isSelected: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            baseLayer
            if agentState == .done {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.green.opacity(0.55), lineWidth: 1.5)
            } else if agentState == .waitingForApproval {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.orange.opacity(0.7), lineWidth: 2)
            }
        }
        .onAppear { startPulseIfNeeded() }
        .onChange(of: agentState) { _, state in
            pulse = false
            if state == .running { startPulseIfNeeded() }
        }
    }

    @ViewBuilder
    private var baseLayer: some View {
        if agentState == .running {
            RoundedRectangle(cornerRadius: 6)
                .fill(claudePeach.opacity(pulse ? 0.35 : 0.75))
        } else if isSelected {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.75))
        } else if isActive {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.1))
        } else {
            Color.clear
        }
    }

    private func startPulseIfNeeded() {
        guard agentState == .running else { return }
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
    }
}

// MARK: - Shared color

private let claudePeach = Color(red: 222 / 255, green: 115 / 255, blue: 86 / 255)
