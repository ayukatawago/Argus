import Foundation

/// One line of the first-run checklist.
public struct OnboardingStep: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let isComplete: Bool
    /// A required step blocks "ready"; an optional one is only a nudge (e.g. the GitHub token).
    public let isRequired: Bool
}

/// Pure rules for the first-run checklist, kept free of process spawning so they're testable:
/// the caller resolves which executables the login shell can find and passes that in.
public enum OnboardingChecklist {
    /// The executable a launch command starts with — the first whitespace-separated token that
    /// isn't a leading `VAR=value` assignment. `nil` for a blank command.
    public static func executable(fromCommand command: String) -> String? {
        command.split(whereSeparator: \.isWhitespace)
            .first { !$0.contains("=") || $0.hasPrefix("/") || $0.hasPrefix("./") }
            .map(String.init)
    }

    /// Every executable name worth resolving for `config`, so the caller can look them all up in
    /// one pass.
    public static func executablesToResolve(config: ArgusConfig) -> [String] {
        AgentSelection.allCases.compactMap { executable(fromCommand: config.launchCommand(for: $0)) }
    }

    public static func steps(config: ArgusConfig, foundExecutables: Set<String>) -> [OnboardingStep] {
        let agentSteps = AgentSelection.allCases.map { agent -> OnboardingStep in
            let executable = executable(fromCommand: config.launchCommand(for: agent))
            let found = executable.map(foundExecutables.contains) ?? false
            let detail =
                found
                ? "Found `\(executable ?? "")` on your login-shell PATH."
                : "Could not find `\(executable ?? "(no command set)")` on your login-shell PATH. "
                    + "Install it, or change the launch command in Settings → Agent."
            return OnboardingStep(
                id: "agent-\(agent.rawValue)",
                title: "\(agent.displayName) CLI",
                detail: detail,
                isComplete: found,
                isRequired: agent == config.agent
            )
        }
        let hasToken = !config.github.token.isEmpty
        let token = OnboardingStep(
            id: "github-token",
            title: "GitHub token",
            detail: hasToken
                ? "PR monitor is enabled."
                : "Optional. Add a token in Settings → GitHub to show your pull requests in the sidebar.",
            isComplete: hasToken,
            isRequired: false
        )
        return agentSteps + [token]
    }

    /// True when every required step is complete.
    public static func isReady(_ steps: [OnboardingStep]) -> Bool {
        steps.allSatisfy { !$0.isRequired || $0.isComplete }
    }
}
