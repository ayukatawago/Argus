import AppKit
import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: WorkspaceStore
    @Binding var selectedWorktreeID: String?
    let activeTerminalIDs: Set<String>
    @ObservedObject var agentBus: AgentStateBus
    let onRelease: (String) -> Void
    @State private var dropTargetRepoID: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if store.repos.isEmpty {
                        Text("No git repos found")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                            .padding()
                    }
                    else {
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
        let name = URL(fileURLWithPath: worktree.path).lastPathComponent
        let confirm = NSAlert()
        confirm.messageText = "Delete Worktree \"\(name)\"?"
        confirm.informativeText = "The working directory will be removed. Committed work is safe in the repository."
        confirm.alertStyle = .warning
        confirm.addButton(withTitle: "Delete")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

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
                let forceAlert = NSAlert()
                forceAlert.messageText = "Worktree has uncommitted changes"
                forceAlert.informativeText = "Force delete will discard all uncommitted changes in \"\(name)\" permanently."
                forceAlert.alertStyle = .critical
                forceAlert.addButton(withTitle: "Force Delete")
                forceAlert.addButton(withTitle: "Cancel")
                guard forceAlert.runModal() == .alertFirstButtonReturn else {
                    await store.refresh()
                    return
                }
                await Task.detached(priority: .userInitiated) {
                    let proc = Process()
                    proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                    proc.arguments = ["-C", repo.mainPath, "worktree", "remove", "--force", worktree.path]
                    proc.standardOutput = Pipe()
                    proc.standardError = Pipe()
                    try? proc.run()
                    proc.waitUntilExit()
                }.value
            }

            await store.refresh()
        }
    }

    private func addWorktree(for repo: GitRepo) {
        let alert = NSAlert()
        alert.messageText = "New Worktree"
        alert.informativeText = "Enter a branch name for the new worktree."
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        textField.placeholderString = "feature-branch"
        alert.accessoryView = textField
        alert.layout()
        alert.window.initialFirstResponder = textField

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let branch = textField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !branch.isEmpty else { return }

        let safeName = branch.replacingOccurrences(of: "/", with: "-")
        let parent = URL(fileURLWithPath: repo.mainPath).deletingLastPathComponent().path
        let newPath = (parent as NSString).appendingPathComponent(safeName)

        Task {
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
                let errAlert = NSAlert()
                errAlert.messageText = "Could not create worktree"
                errAlert.informativeText = "Make sure the branch '\(branch)' does not already exist."
                errAlert.alertStyle = .warning
                errAlert.runModal()
            }
            await store.refresh()
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
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(dotColor.opacity(pulse ? 0.5 : 1.0))
            .frame(width: 8, height: 8)
            .onAppear { startPulseIfNeeded() }
            .onChange(of: state) { _, newState in
                withAnimation(.linear(duration: 0)) { pulse = false }
                if newState == .running { startPulseIfNeeded() }
            }
    }

    private var dotColor: Color {
        switch state {
        case .idle: Color.secondary.opacity(0.4)
        case .running: claudePeach
        case .waitingForApproval: Color(nsColor: .systemOrange)
        case .done: Color(nsColor: .systemGreen).opacity(0.8)
        }
    }

    private func startPulseIfNeeded() {
        guard state == .running else { return }
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
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
                    .strokeBorder(Color(nsColor: .systemGreen).opacity(0.55), lineWidth: 1.5)
            } else if agentState == .waitingForApproval {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color(nsColor: .systemOrange).opacity(0.7), lineWidth: 2)
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
        }
        else if isSelected {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.75))
        }
        else if isActive {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.1))
        }
        else {
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
