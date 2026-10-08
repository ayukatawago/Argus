import AppKit
import ArgusConfigKit
import SwiftUI

/// A parsed `argus://diff?workspace=...&from=...&to=...` request — see `AppDelegate.handleDiffRequest`.
/// Field names match `DiffReviewWindow.open(worktreePath:base:head:agent:)`; `from`/`to` are only
/// the URL's (and the CLI's) external vocabulary.
private struct DiffReviewRequest {
    let workspace: String
    let base: String
    let head: String
}

/// The `mode` of an `argus://capture?mode=...&output=...&duration=...` request — see
/// `AppDelegate.handleCaptureRequest`.
private enum CaptureMode: String {
    case screenshot
    case video
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set in `init()` — SwiftUI constructs the `@NSApplicationDelegateAdaptor`-owned delegate
    /// before evaluating any Scene/View, so this is reliably non-nil by the time `AppShellView`
    /// appears. Lets it signal readiness via a direct call (see `markAppShellReady`) instead of a
    /// `NotificationCenter` round trip, which would race `AppShellView.onAppear` against this
    /// class's own observer registration with no guaranteed ordering between them.
    static private(set) weak var current: AppDelegate?

    private var keyEventMonitor: Any?
    private var mouseEventMonitor: Any?
    private var awaitingLeader = false
    private var leaderTimer: Timer?

    override init() {
        super.init()
        AppDelegate.current = self
    }

    // MARK: - CLI-originated diff review (`argus diff` → `argus://diff`)

    /// Whether `AppShellView` has appeared (and so has its `.openDiffReviewForPath` subscription
    /// live) yet. A URL can arrive before that, in which case posting the notification would be
    /// silently dropped — so a request that arrives too early is buffered here and flushed by
    /// `markAppShellReady`.
    private var isAppShellReady = false
    private var pendingDiffReviewRequest: DiffReviewRequest?

    /// Handles `argus://<subcommand>` URLs from `script/argus` (or any other `open`-based
    /// caller). `diff` and `capture` are implemented today; unrecognized hosts are ignored so
    /// future subcommands can be added without breaking older callers.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "argus" {
            switch url.host {
            case "diff": handleDiffRequest(url)
            case "capture": handleCaptureRequest(url)
            default: break
            }
        }
    }

    private func handleDiffRequest(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? { items.first(where: { $0.name == name })?.value }

        guard let workspace = value("workspace"), !workspace.isEmpty else { return }
        guard workspace.hasPrefix("/"), FileManager.default.fileExists(atPath: workspace) else {
            showInvalidWorkspaceAlert(path: workspace)
            return
        }

        let request = DiffReviewRequest(workspace: workspace, base: value("from") ?? "", head: value("to") ?? "HEAD")
        if isAppShellReady {
            postDiffReviewRequest(request)
        } else {
            pendingDiffReviewRequest = request
        }
    }

    /// Called by `AppShellView.onAppear` — flushes any `argus://diff` request that arrived before
    /// its `.openDiffReviewForPath` subscription existed to receive it.
    func markAppShellReady() {
        isAppShellReady = true
        guard let pending = pendingDiffReviewRequest else { return }
        pendingDiffReviewRequest = nil
        postDiffReviewRequest(pending)
    }

    private func postDiffReviewRequest(_ request: DiffReviewRequest) {
        NotificationCenter.default.post(
            name: .openDiffReviewForPath,
            object: nil,
            userInfo: ["workspace": request.workspace, "base": request.base, "head": request.head]
        )
    }

    /// A path that doesn't exist can't be diffed at all — surfaced here rather than left to the
    /// diff window, since there'd be nothing sensible to open it onto. A path that exists but
    /// isn't a git repo still opens the window and reports through its existing `loadError` UI.
    private func showInvalidWorkspaceAlert(path: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Can't open diff review"
        alert.informativeText = "\"\(path)\" isn't a valid absolute path."
        alert.runModal()
    }

    // MARK: - CLI-originated capture (`argus capture` → `argus://capture`)

    /// Unlike `handleDiffRequest`, this needs no app-shell-readiness gate: it targets Argus's own
    /// already-existing main window rather than opening new UI, and reports success/failure by
    /// writing to `output`/`output.error` on disk (`ScreenCaptureController`) rather than through
    /// a `NotificationCenter` round trip a SwiftUI view would need to be subscribed to receive.
    private func handleCaptureRequest(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? { items.first(where: { $0.name == name })?.value }

        guard let output = value("output"), output.hasPrefix("/") else { return }
        guard let mode = value("mode").flatMap(CaptureMode.init(rawValue:)) else { return }
        let duration = value("duration").flatMap(Double.init) ?? 10

        Task {
            switch mode {
            case .screenshot:
                await ScreenCaptureController.shared.captureScreenshot(outputPath: output)

            case .video:
                await ScreenCaptureController.shared.captureVideo(outputPath: output, duration: duration)
            }
        }
    }

    func applicationDidFinishLaunching(_: Notification) {
        installKeyEventMonitor()

        mouseEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            NotificationCenter.default.post(name: .workspaceInteracted, object: nil)
            return event
        }
    }

    private func installKeyEventMonitor() {
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
            let char = event.charactersIgnoringModifiers?.lowercased()

            let config = ArgusConfigStore.shared.config

            // Leader key: enter leader mode, or pass through on double press (e.g. for nested tmux).
            if let chord = LeaderKey.parse(config.leaderKey),
                modifiers == Self.modifierFlags(from: chord.modifiers), char == chord.character
            {
                if self.awaitingLeader {
                    self.endLeaderMode()
                    return event
                }
                self.awaitingLeader = true
                LeaderModeState.shared.begin()
                self.leaderTimer?.invalidate()
                self.leaderTimer = Timer.scheduledTimer(
                    withTimeInterval: config.leaderTimeoutSeconds,
                    repeats: false
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.endLeaderMode() }
                }
                return nil
            }

            // Leader sequences (no modifier required on the second key)
            if self.awaitingLeader && modifiers.isEmpty {
                self.endLeaderMode()
                switch char.flatMap({ LeaderActionCatalog.target(forKey: $0, config: config) }) {
                case .action(let action):
                    NotificationCenter.default.post(name: action.notificationName, object: nil)
                    return nil

                case .popup(let id):
                    NotificationCenter.default.post(name: .openPopupTerminal, object: id)
                    return nil

                case nil:
                    break
                }
            }

            // ⌘⇧N as a direct shortcut for nvim (keeps the menu item working)
            if modifiers == [.command, .shift] && char == "n" {
                NotificationCenter.default.post(name: .openNvim, object: nil)
                return nil
            }

            NotificationCenter.default.post(name: .workspaceInteracted, object: nil)
            return event
        }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Fires before state restoration — wipe any saved window state so crash-recovery
        // replays don't create extra surfaces on the next launch.
        guard let bundleID = Bundle.main.bundleIdentifier,
            let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
        else { return }
        let savedStateURL =
            libraryURL
            .appendingPathComponent("Saved Application State/\(bundleID).savedState")
        try? FileManager.default.removeItem(at: savedStateURL)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            sender.windows
                .first(where: { !($0 is NSPanel) })
                .map { $0.makeKeyAndOrderFront(nil) }
            sender.activate(ignoringOtherApps: true)
        }
        return false
    }

    // MARK: - Helpers

    private static func modifierFlags(from modifiers: Set<LeaderChord.Modifier>) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.control) { flags.insert(.control) }
        if modifiers.contains(.command) { flags.insert(.command) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        return flags
    }

    private func endLeaderMode() {
        awaitingLeader = false
        leaderTimer?.invalidate()
        LeaderModeState.shared.end()
    }
}

@main
struct ArgusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("Argus", id: "main") {
            ContentView()
                .environmentObject(ArgusConfigStore.shared)
                .environmentObject(CodexUsageStore.shared)
        }
        .defaultSize(width: 1200, height: 800)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .windowArrangement) {
                Button("Open nvim") {
                    NotificationCenter.default.post(name: .openNvim, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(after: .textEditing) {
                Button("Command Palette") {
                    NotificationCenter.default.post(name: .openCommandPalette, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command])
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }

        Window("Settings", id: "settings") {
            SettingsRootView()
                .environmentObject(ArgusConfigStore.shared)
                .environmentObject(CodexUsageStore.shared)
        }
        .defaultSize(width: 540, height: 460)
        .windowResizability(.contentMinSize)
    }
}
