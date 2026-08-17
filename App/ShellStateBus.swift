import AgentStateKit
import ArgusSupport
import Foundation
import Monitors

/// Tracks which shell panes have a command running and publishes the set of busy
/// worktree paths.  Fish shell users get an event-driven path via preexec/postexec
/// hooks installed to ~/.config/fish/conf.d/argus.fish; other shells fall back to
/// polling tmux every 400 ms.
@MainActor
final class ShellStateBus: ObservableObject {
    @Published private(set) var busyPaths: Set<String> = []

    private var pollTask: Task<Void, Never>?
    private var activePaths: Set<String> = []

    func updateActivePaths(_ paths: Set<String>) {
        activePaths = paths
        let filtered = busyPaths.filter { paths.contains($0) }
        if filtered != busyPaths { busyPaths = filtered }
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
        var next = busyPaths
        if payload.state == "running" {
            next.insert(path)
        } else {
            next.remove(path)
        }
        next = next.filter { activePaths.contains($0) }
        if next != busyPaths { busyPaths = next }
    }

    // MARK: - Non-fish: tmux polling

    private func poll() async {
        let paths = activePaths
        guard !paths.isEmpty else {
            if !busyPaths.isEmpty { busyPaths = [] }
            return
        }
        let tmux = WorktreePane.tmuxExecutable
        let result = await ProcessRunner.run(
            tmux, ["list-panes", "-a", "-F", "#{session_name}|#{pane_current_command}"])

        let pathBySession = Dictionary(
            paths.map { (WorktreePane.sessionName("s", path: $0), $0) }, uniquingKeysWith: { first, _ in first })
        let busySessions = TmuxPaneParser.busySessions(
            from: result.standardOutput, activeSessions: Set(pathBySession.keys))
        let next = Set(busySessions.compactMap { pathBySession[$0] })
        if next != busyPaths { busyPaths = next }
    }
}
