import ArgusConfigKit
import ArgusSupport
import SwiftUI
import UniformTypeIdentifiers
import Workspaces

/// Shown in the detail area while no worktree is selected: a hint about what to do next, plus a
/// first-run checklist (agent CLIs on the login-shell PATH, GitHub token) until dismissed.
struct WelcomeView: View {
    @ObservedObject var store: WorkspaceStore
    @EnvironmentObject var configStore: ArgusConfigStore
    @State private var foundExecutables: Set<String> = []
    @State private var isChecking = false
    @State private var showPickFolder = false

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Image(systemName: "sidebar.left")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(store.repos.isEmpty ? "Add a folder to get started" : "Select a worktree")
                    .font(.title3)
                Text(
                    store.repos.isEmpty
                        ? "Pick a git repository, or a folder containing several."
                        : "Choose one in the sidebar, or press ⌘K to search."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            if store.repos.isEmpty {
                Button("Add Folder…") { showPickFolder = true }
                    .buttonStyle(.borderedProminent)
            }
            if !configStore.config.onboardingDismissed {
                checklist
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fileImporter(isPresented: $showPickFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { store.addRoot(url.path) }
        }
        .task(id: commandsKey) { await resolveExecutables() }
    }

    private var steps: [OnboardingStep] {
        OnboardingChecklist.steps(config: configStore.config, foundExecutables: foundExecutables)
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Setup").font(.headline)
                Spacer()
                if isChecking { ProgressView().controlSize(.small) }
                Button("Recheck") { Task { await resolveExecutables() } }
                    .buttonStyle(.link)
                Button("Dismiss") {
                    configStore.config.onboardingDismissed = true
                    configStore.save()
                }
                .buttonStyle(.link)
            }
            ForEach(steps) { step in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: icon(for: step))
                        .foregroundStyle(tint(for: step))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                        Text(step.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(step.isComplete ? "Done" : (step.isRequired ? "Needs attention" : "Optional"))
            }
            Button("Open Settings") { NotificationCenter.default.post(name: .openSettings, object: nil) }
                .buttonStyle(.link)
        }
        .padding(16)
        .frame(maxWidth: 440, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }

    private func icon(for step: OnboardingStep) -> String {
        if step.isComplete { return "checkmark.circle.fill" }
        return step.isRequired ? "xmark.circle.fill" : "circle"
    }

    private func tint(for step: OnboardingStep) -> Color {
        if step.isComplete { return .green }
        return step.isRequired ? .orange : .secondary
    }

    /// Re-run the PATH lookup whenever the configured launch commands change.
    private var commandsKey: String {
        OnboardingChecklist.executablesToResolve(config: configStore.config).joined(separator: "\n")
    }

    private func resolveExecutables() async {
        isChecking = true
        defer { isChecking = false }
        var found = Set<String>()
        for executable in OnboardingChecklist.executablesToResolve(config: configStore.config)
        where await Self.canResolve(executable) {
            found.insert(executable)
        }
        foundExecutables = found
    }

    /// Asks the login shell (as `WorktreePane` does when it launches an agent), so a PATH set up in
    /// the user's shell profile is honored rather than this app's own minimal environment.
    private static func canResolve(_ executable: String) async -> Bool {
        if executable.hasPrefix("/") { return FileManager.default.isExecutableFile(atPath: executable) }
        let result = await ProcessRunner.run(
            LoginShell.current, ["-l", "-c", "command -v \(ShellQuote.quote(executable))"], timeout: 5)
        return result.succeeded
    }
}
