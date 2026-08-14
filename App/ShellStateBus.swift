import AgentStateKit
import ArgusSupport
import Foundation

/// Tracks which shell panes have a command running and publishes the set of busy
/// worktree paths.  Fish shell users get an event-driven path via preexec/postexec
/// hooks installed to ~/.config/fish/conf.d/argus.fish; other shells fall back to
/// polling tmux every 400 ms.
@MainActor
final class ShellStateBus: ObservableObject {
    @Published private(set) var busyPaths: Set<String> = []

    private var pollTask: Task<Void, Never>?
    private var activePaths: Set<String> = []

    private static let shellNames: Set<String> = [
        "bash", "zsh", "fish", "sh", "dash", "ksh", "tcsh", "csh",
    ]

    func updateActivePaths(_ paths: Set<String>) {
        activePaths = paths
        busyPaths = busyPaths.filter { paths.contains($0) }
    }

    func start() {
        guard pollTask == nil else { return }
        if WorktreeHookManager.isFishShell {
            try? FileManager.default.removeItem(atPath: HookIPC.shellEventLogPath)
            pollTask = Task { [weak self] in await self?.tailShellEvents() }
        } else {
            pollTask = PollingTask.repeating(
                order: .actThenSleep,
                interval: { 400_000_000 },
                action: { [weak self] in await self?.poll() }
            )
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        busyPaths = []
    }

    // MARK: - Fish: tail shell event log

    private func tailShellEvents() async {
        for await lineData in JSONLTailer(path: HookIPC.shellEventLogPath).lines() {
            guard let payload = try? JSONDecoder().decode(HookPayload.self, from: lineData) else { continue }
            applyShellEvent(payload)
        }
    }

    private func applyShellEvent(_ payload: HookPayload) {
        let path = payload.worktreePath
        if payload.state == "running" {
            busyPaths.insert(path)
        } else {
            busyPaths.remove(path)
        }
        busyPaths = busyPaths.filter { activePaths.contains($0) }
    }

    // MARK: - Non-fish: tmux polling

    private func poll() async {
        let paths = activePaths
        guard !paths.isEmpty else { busyPaths = []; return }
        let tmux = WorktreePane.tmuxExecutable
        let result = await ProcessRunner.run(
            tmux, ["list-panes", "-a", "-F", "#{session_name}|#{pane_current_command}"])
        let output = result.standardOutput

        var sessionToCommand: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "|", maxSplits: 1)
            if parts.count == 2 {
                sessionToCommand[String(parts[0])] = String(parts[1])
            }
        }

        var newBusy: Set<String> = []
        for path in paths {
            let session = WorktreePane.sessionName("s", path: path)
            if let cmd = sessionToCommand[session], !ShellStateBus.shellNames.contains(cmd) {
                newBusy.insert(path)
            }
        }
        busyPaths = newBusy
    }
}
