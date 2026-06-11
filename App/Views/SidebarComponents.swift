import SwiftUI

struct RepoHeader: View {
    let name: String
    let isGitRepo: Bool
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
            if isGitRepo {
                Button(action: onAddWorktree) {
                    Image(systemName: "plus.circle")
                        .imageScale(.medium)
                }
                .buttonStyle(.borderless)
                .help("Add worktree")
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

// MARK: - Agent state dot

struct AgentDot: View {
    let state: AgentState
    var agentType: AgentType = .claude

    private let frames: [String] = ["·", "✢", "✳", "✶", "✽", "*", "✶", "+", "·"]

    var body: some View {
        Group {
            if state == .running && agentType == .claude {
                TimelineView(.periodic(from: .now, by: 0.12)) { context in
                    let idx = Int(context.date.timeIntervalSinceReferenceDate / 0.12) % frames.count
                    Text(frames[idx])
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(agentColor(agentType))
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
        case .running: agentColor(agentType)
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
    var agentType: AgentType = .claude
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
                .fill(agentColor(agentType).opacity(runningOpacity))
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

    private var runningOpacity: Double {
        pulse ? 0.35 : 0.75
    }
}

// MARK: - Shimmer text

struct ShimmerText: View {
    let text: String
    let color: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30)) { ctx in
            let elapsed = ctx.date.timeIntervalSinceReferenceDate
            let phase = CGFloat(elapsed.truncatingRemainder(dividingBy: 1.8) / 1.8)
            Text(text)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(shimmerGradient(phase: phase))
        }
    }

    private func shimmerGradient(phase: CGFloat) -> LinearGradient {
        func clamped(_ val: CGFloat) -> CGFloat { Swift.max(0, Swift.min(1, val)) }
        let bandWidth: CGFloat = 0.25
        let stops: [Gradient.Stop] = [
            .init(color: color.opacity(0.4), location: 0),
            .init(color: color.opacity(0.4), location: clamped(phase - bandWidth)),
            .init(color: color, location: clamped(phase)),
            .init(color: color.opacity(0.4), location: clamped(phase + bandWidth)),
            .init(color: color.opacity(0.4), location: 1),
        ]
        return LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
    }
}

// MARK: - Shared colors

let claudePeach = Color(red: 222 / 255, green: 115 / 255, blue: 86 / 255)
let codexAzure = Color(red: 43 / 255, green: 143 / 255, blue: 255 / 255)

func agentColor(_ type: AgentType) -> Color {
    switch type {
    case .claude: claudePeach
    case .codex: codexAzure
    }
}
