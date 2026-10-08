import AgentStateKit
import SwiftUI
import Workspaces

/// Visible (non-hidden) worktree IDs grouped by what their agent is doing.
struct AgentCounts {
    var waiting = Set<String>()
    var done = Set<String>()
    var running = 0

    @MainActor
    init(store: WorkspaceStore, agentBus: AgentStateBus) {
        for worktree in store.repos.flatMap(\.worktrees) where !store.hiddenWorktreeIDs.contains(worktree.id) {
            switch agentBus.worktreeState(for: worktree.id).state {
            case .waitingForApproval: waiting.insert(worktree.id)
            case .done: done.insert(worktree.id)
            case .running: running += 1
            case .idle: break
            }
        }
    }

    var needsAttention: Set<String> { waiting.union(done) }

    var isEmpty: Bool { waiting.isEmpty && done.isEmpty && running == 0 }

    var summary: String {
        [
            waiting.isEmpty ? nil : "\(waiting.count) waiting",
            done.isEmpty ? nil : "\(done.count) done",
            running == 0 ? nil : "\(running) running",
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}

/// The sidebar's filter field, "needs attention" toggle and agent summary line.
struct SidebarFilterBar: View {
    @Binding var query: String
    @Binding var attentionOnly: Bool
    let counts: AgentCounts
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        let isFiltering = !query.isEmpty || attentionOnly
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).imageScale(.small)
                TextField("Filter worktrees", text: $query)
                    .textFieldStyle(.plain)
                    .focused(isFocused)
                    .onExitCommand {
                        query = ""
                        isFocused.wrappedValue = false
                    }
                if isFiltering {
                    Button {
                        query = ""
                        attentionOnly = false
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Clear filter")
                    .accessibilityLabel("Clear filter")
                }
                Button {
                    attentionOnly.toggle()
                } label: {
                    Image(systemName: attentionOnly ? "bell.badge.fill" : "bell")
                        .foregroundStyle(attentionOnly ? Color.orange : Color.secondary)
                }
                .buttonStyle(.borderless)
                .help("Only show worktrees that need attention")
                .accessibilityLabel("Only show worktrees that need attention")
                .accessibilityValue(attentionOnly ? "On" : "Off")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
            if !counts.isEmpty {
                Text(counts.summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .onReceive(NotificationCenter.default.publisher(for: .focusSidebarFilter)) { _ in
            isFocused.wrappedValue = true
        }
    }
}
