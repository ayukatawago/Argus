import AgentStateKit
import SwiftUI
import Workspaces

struct WorktreeRow: View {
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
                .accessibilityLabel("Release terminal sessions")
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
                .accessibilityLabel("Delete worktree")
                .opacity(isHovered ? 1 : 0)
            }
            Button(action: onHide) {
                Image(systemName: "eye.slash")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Hide worktree")
            .accessibilityLabel("Hide worktree")
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

    private var worktreeName: some View {
        let name = URL(fileURLWithPath: worktree.path).lastPathComponent
        return ShimmerText(
            text: name,
            color: .primary,
            isShimmering: agentState == .running && agentType == .codex
        )
    }
}
