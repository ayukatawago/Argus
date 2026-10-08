import Combine
import Foundation

/// Whether leader mode is active and its which-key HUD should be on screen. `AppDelegate` drives
/// it from its key monitor; `LeaderHUDView` observes it. The HUD only appears if leader mode is
/// still pending after `hudDelay`, so a fast leader+key chord never flashes it.
@MainActor
final class LeaderModeState: ObservableObject {
    static let shared = LeaderModeState()

    static let hudDelay: Duration = .milliseconds(300)

    @Published private(set) var showHUD = false
    private var hudTask: Task<Void, Never>?

    func begin() {
        hudTask?.cancel()
        hudTask = Task { [weak self] in
            try? await Task.sleep(for: Self.hudDelay)
            guard !Task.isCancelled else { return }
            self?.showHUD = true
        }
    }

    func end() {
        hudTask?.cancel()
        hudTask = nil
        showHUD = false
    }
}
