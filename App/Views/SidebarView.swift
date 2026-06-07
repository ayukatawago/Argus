import AppKit
import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: WorkspaceStore
    @Binding var selectedWorktreeID: String?
    let activeTerminalIDs: Set<String>
    @ObservedObject var agentBus: AgentStateBus

    var body: some View {
        List(selection: $selectedWorktreeID) {
            if store.repos.isEmpty {
                Text("No git repos found")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            else {
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
                            isSelected: selectedWorktreeID == worktree.id,
                            agentState: agentBus.state(for: worktree.id)
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
    let isActive: Bool
    let isSelected: Bool
    let agentState: AgentState
    let onHide: () -> Void
    @State private var isHovered = false

    init(
        worktree: GitWorktree,
        isActive: Bool = false,
        isSelected: Bool = false,
        agentState: AgentState = .idle,
        onHide: @escaping () -> Void
    ) {
        self.worktree = worktree
        self.isActive = isActive
        self.isSelected = isSelected
        self.agentState = agentState
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
            AgentStateBackground(agentState: agentState, isActive: isActive, isSelected: isSelected)
        )
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
        case .done: Color.green.opacity(0.8)
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
                    .strokeBorder(Color.green.opacity(0.55), lineWidth: 1.5)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
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
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
        }
        else if isActive && !isSelected {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.1))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
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
