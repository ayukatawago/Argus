import AgentStateKit
import ArgusConfigKit
import SwiftUI

struct RepoHeader: View {
    let name: String
    let isGitRepo: Bool
    let hiddenCount: Int
    /// This project's agent override (`nil` = follow the global default), for the context menu's
    /// checkmarks and the badge next to the repo name.
    var agentOverride: AgentSelection?
    let onAddWorktree: () -> Void
    let onRemove: () -> Void
    let onUnhide: () -> Void
    /// `nil` clears the override, restoring the global default.
    var onSelectAgent: (AgentSelection?) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 4) {
            Text(name)
                .font(.headline)
            if let agentOverride {
                Text(agentOverride.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
            }
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
        .contextMenu { if isGitRepo { agentMenu } }
    }

    @ViewBuilder
    private var agentMenu: some View {
        Menu("Agent") {
            Button {
                onSelectAgent(nil)
            } label: {
                agentMenuLabel("Use default", isSelected: agentOverride == nil)
            }
            ForEach(AgentSelection.allCases) { option in
                Button {
                    onSelectAgent(option)
                } label: {
                    agentMenuLabel(option.displayName, isSelected: agentOverride == option)
                }
            }
        }
    }

    private func agentMenuLabel(_ title: String, isSelected: Bool) -> some View {
        HStack {
            Text(title)
            if isSelected {
                Image(systemName: "checkmark")
            }
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
///
/// The running-state pulse and the shell-busy rotating border are both driven off the same
/// `TimelineView`, computing their look as a pure function of wall-clock time rather than
/// `@State` + `withAnimation(...repeatForever...)`. A state-driven pulse has to be torn down and
/// restarted every time this view's identity is rebuilt (e.g. a sidebar row disappearing and
/// reappearing during a worktree rescan) — each restart snapped the opacity because the old code
/// reset `pulse = false` outside of `withAnimation`. A time-derived value has no in-flight
/// animation to interrupt: whatever elapsed time this instance is built with, the opacity is
/// already correct.
struct AgentStateBackground: View {
    let agentState: AgentState
    let isActive: Bool
    let isSelected: Bool
    var agentType: AgentType = .claude
    var isShellBusy: Bool = false

    private var needsTicking: Bool { agentState == .running || isShellBusy }

    var body: some View {
        if needsTicking {
            TimelineView(.periodic(from: .now, by: 1.0 / 30)) { ctx in
                content(elapsed: ctx.date.timeIntervalSinceReferenceDate)
            }
        } else {
            content(elapsed: 0)
        }
    }

    @ViewBuilder
    private func content(elapsed: TimeInterval) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(fillColor(elapsed: elapsed))
            border(elapsed: elapsed)
        }
    }

    private func fillColor(elapsed: TimeInterval) -> Color {
        if agentState == .running {
            return agentColor(agentType).opacity(pulseOpacity(elapsed: elapsed))
        } else if isActive {
            return Color.accentColor.opacity(0.1)
        }
        return Color.clear
    }

    /// A 2.2s triangle wave eased with smoothstep, ranging 0.75 -> 0.35 -> 0.75 — matches the
    /// visual shape of the old `.easeInOut(duration: 1.1).repeatForever(autoreverses: true)`.
    private func pulseOpacity(elapsed: TimeInterval) -> Double {
        let period = 2.2
        let phase = elapsed.truncatingRemainder(dividingBy: period) / period
        let triangle = phase < 0.5 ? phase * 2 : (1 - phase) * 2
        let eased = triangle * triangle * (3 - 2 * triangle)
        return 0.75 - eased * 0.4
    }

    @ViewBuilder
    private func border(elapsed: TimeInterval) -> some View {
        if isShellBusy {
            let angle = elapsed.truncatingRemainder(dividingBy: 2.0) / 2.0 * 360.0
            let shellBorderColor: Color = isSelected ? .accentColor : .primary
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    AngularGradient(
                        colors: [
                            .clear, .clear, shellBorderColor.opacity(0.7),
                            shellBorderColor, .clear,
                        ],
                        center: .center,
                        startAngle: .degrees(angle),
                        endAngle: .degrees(angle + 360)
                    ),
                    lineWidth: 2
                )
        } else if let style = staticBorderStyle {
            RoundedRectangle(cornerRadius: 6).strokeBorder(style.color, lineWidth: style.lineWidth)
        }
    }

    /// The three static (non-animated) border cases collapsed into one computed value instead of
    /// separate `if/else` branches, so switching between them (or to no border) no longer changes
    /// the view's structural type.
    private var staticBorderStyle: (color: Color, lineWidth: CGFloat)? {
        if agentState == .done {
            return (Color.green.opacity(0.55), 1.5)
        } else if agentState == .waitingForApproval {
            return (Color.orange.opacity(0.7), 2)
        } else if isSelected {
            return (Color.accentColor, 2)
        }
        return nil
    }
}

// MARK: - Shimmer text

struct ShimmerText: View {
    let text: String
    let color: Color
    var isShimmering: Bool = true

    var body: some View {
        if isShimmering {
            TimelineView(.periodic(from: .now, by: 1.0 / 30)) { ctx in
                let elapsed = ctx.date.timeIntervalSinceReferenceDate
                let phase = CGFloat(elapsed.truncatingRemainder(dividingBy: 1.8) / 1.8)
                label.foregroundStyle(shimmerGradient(phase: phase))
            }
        } else {
            label.foregroundStyle(color)
        }
    }

    private var label: some View {
        Text(text)
            .lineLimit(1)
            .truncationMode(.middle)
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
