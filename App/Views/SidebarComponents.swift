import SwiftUI

struct RepoHeader: View {
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

// MARK: - Agent state dot

struct AgentDot: View {
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
struct AgentStateBackground: View {
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

let claudePeach = Color(red: 222 / 255, green: 115 / 255, blue: 86 / 255)
