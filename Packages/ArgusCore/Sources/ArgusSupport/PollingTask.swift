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
    ///   picks up changes on the next cycle without restarting the task. `async` rather than a
    ///   plain `@Sendable () -> UInt64` specifically so a caller can read `@MainActor`-isolated
    ///   state (as the config store is) without ArgusSupport itself needing to know about
    ///   `@MainActor` — a synchronous closure still converts to this type automatically.
    public static func repeating(
        priority: TaskPriority? = nil,
        order: Order = .actThenSleep,
        interval: @escaping @Sendable () async -> UInt64,
        action: @escaping @Sendable () async -> Void
    ) -> Task<Void, Never> {
        Task(priority: priority) {
            while !Task.isCancelled {
                switch order {
                case .actThenSleep:
                    await action()
                    try? await Task.sleep(nanoseconds: await interval())

                case .sleepThenAct:
                    try? await Task.sleep(nanoseconds: await interval())
                    await action()
                }
            }
        }
    }
}
