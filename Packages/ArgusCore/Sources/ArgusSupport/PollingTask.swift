import Foundation

/// Replaces the `while !Task.isCancelled { ... ; sleep }` loop duplicated across PRMonitorStore,
/// DiskMonitorStore, DiskCleanupScanner, ShellStateBus, and CodexSessionWatcher.
public enum PollingTask {
    /// Whether `action` runs before or after each sleep. The call sites this replaces disagree:
    /// some do an immediate call outside the loop and then sleep-first inside it (`.sleepThenAct`
    /// — the loop only ever waits before acting again); others fold the first call into the loop
    /// itself (`.actThenSleep`).
    public enum Order: Sendable {
        case actThenSleep
        case sleepThenAct
    }

    /// Runs `action` repeatedly until the returned `Task` is cancelled.
    ///
    /// - Parameter interval: Called fresh before every sleep, not just once — a caller whose
    ///   interval comes from a live, mutable config (e.g. `ArgusConfigStore.shared.config...`)
    ///   picks up changes on the next cycle without restarting the task.
    public static func repeating(
        priority: TaskPriority? = nil,
        order: Order = .actThenSleep,
        interval: @escaping @Sendable () -> UInt64,
        action: @escaping @Sendable () async -> Void
    ) -> Task<Void, Never> {
        Task(priority: priority) {
            while !Task.isCancelled {
                switch order {
                case .actThenSleep:
                    await action()
                    try? await Task.sleep(nanoseconds: interval())

                case .sleepThenAct:
                    try? await Task.sleep(nanoseconds: interval())
                    await action()
                }
            }
        }
    }
}
