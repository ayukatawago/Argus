import ArgusSupport
import Foundation
import Monitors

/// Publishes the tmux windows of the selected worktree's shell session as tabs, and drives the
/// tmux commands a tab bar issues. A tab is nothing but a tmux window index — this store is a
/// control surface and mirror over tmux, never a second source of truth. A window created from
/// inside tmux (`ctrl-b ctrl-b c`) appears here on the next poll; a tab created here is an
/// ordinary tmux window.
@MainActor
final class TerminalTabsStore: ObservableObject {
    @Published private(set) var windows: [TmuxWindow] = []

    private var session: String?
    private var worktreePath: String?
    private var pollTask: Task<Void, Never>?
    private var consecutiveFailures = 0
    /// Bumped by every action; a poll that started before the bump discards its result on
    /// completion instead of clobbering the action's optimistic update.
    private var actionGeneration = 0

    /// Switches the store to a different worktree (or none). Clears immediately so a poll for the
    /// previous worktree can never render alongside the new one's terminal.
    func setWorktree(path: String?) {
        guard worktreePath != path else { return }
        worktreePath = path
        session = path.map { WorktreePane.sessionName(for: .shell, path: $0) }
        consecutiveFailures = 0
        actionGeneration += 1
        if !windows.isEmpty { windows = [] }
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = PollingTask.repeating(
            order: .actThenSleep,
            interval: { 500_000_000 },
            action: { [weak self] in await self?.poll() }
        )
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Actions

    @discardableResult
    func select(index: Int) -> Task<Void, Never> {
        guard let session else { return Task {} }
        actionGeneration += 1
        if let currentIndex = windows.firstIndex(where: { $0.isActive }), currentIndex != index,
            let targetIndex = windows.firstIndex(where: { $0.index == index })
        {
            windows[currentIndex] = withActive(windows[currentIndex], false)
            windows[targetIndex] = withActive(windows[targetIndex], true)
        }
        return Task {
            _ = await ProcessRunner.run(WorktreePane.tmuxExecutable, ["select-window", "-t", "\(session):\(index)"])
            await self.poll()
        }
    }

    @discardableResult
    func newTab() -> Task<Void, Never> {
        guard let session, let worktreePath else { return Task {} }
        actionGeneration += 1
        let command = "\(WorktreePane.envExportPreamble())exec \(LoginShell.current) -l"
        return Task {
            _ = await ProcessRunner.run(
                WorktreePane.tmuxExecutable,
                ["new-window", "-a", "-t", "\(session):{end}", "-c", worktreePath, command]
            )
            await self.poll()
        }
    }

    @discardableResult
    func close(index: Int) -> Task<Void, Never> {
        guard let session, windows.count > 1 else { return Task {} }
        actionGeneration += 1
        if let removeAt = windows.firstIndex(where: { $0.index == index }) {
            windows.remove(at: removeAt)
        }
        return Task {
            _ = await ProcessRunner.run(WorktreePane.tmuxExecutable, ["kill-window", "-t", "\(session):\(index)"])
            await self.poll()
        }
    }

    /// Selects the tab `delta` positions away from the active one, wrapping around.
    @discardableResult
    func selectRelative(_ delta: Int) -> Task<Void, Never> {
        guard !windows.isEmpty, let currentIndex = windows.firstIndex(where: { $0.isActive }) else { return Task {} }
        let count = windows.count
        let nextPosition = ((currentIndex + delta) % count + count) % count
        return select(index: windows[nextPosition].index)
    }

    // MARK: - Polling

    private func poll() async {
        guard let session else { return }
        let generation = actionGeneration
        let result = await ProcessRunner.run(
            WorktreePane.tmuxExecutable, ["list-windows", "-t", session, "-F", TmuxWindowParser.listFormat])
        guard generation == actionGeneration else {
            // An action (or a worktree switch) started after this poll did; its own follow-up
            // poll (or the cleared state) is authoritative instead, not this now-stale result.
            return
        }
        if result.succeeded {
            consecutiveFailures = 0
            let next = TmuxWindowParser.parse(result.standardOutput)
            if next != windows { windows = next }
        } else {
            consecutiveFailures += 1
            if consecutiveFailures >= 3, !windows.isEmpty {
                windows = []
            }
        }
    }

    private func withActive(_ window: TmuxWindow, _ isActive: Bool) -> TmuxWindow {
        TmuxWindow(
            sessionName: window.sessionName, index: window.index, isActive: isActive,
            currentPath: window.currentPath)
    }
}
