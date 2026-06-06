import AppKit
import GhosttyKit
import os

/// Owns the singleton `ghostty_app_t` and wires its runtime callbacks.
/// Only `GhosttyBridge` may import `GhosttyKit` — all other modules use this type.
@MainActor
final class GhosttyApp: ObservableObject {
    static let logger = Logger(subsystem: "com.kotty.app", category: "GhosttyApp")

    enum Readiness { case loading, ready, failed }

    @Published private(set) var readiness: Readiness = .loading

    private(set) var app: ghostty_app_t?

    init() {
        if ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) != GHOSTTY_SUCCESS {
            Self.logger.critical("ghostty_init failed")
            readiness = .failed
            return
        }

        guard let config = ghostty_config_new() else {
            Self.logger.critical("ghostty_config_new failed")
            readiness = .failed
            return
        }
        ghostty_config_load_default_files(config)
        ghostty_config_load_cli_args(config)
        ghostty_config_load_recursive_files(config)
        ghostty_config_finalize(config)
        defer { ghostty_config_free(config) }

        var runtimeCfg = Self.makeRuntimeConfig(owner: self)

        guard let newApp = ghostty_app_new(&runtimeCfg, config) else {
            Self.logger.critical("ghostty_app_new failed")
            readiness = .failed
            return
        }
        app = newApp
        ghostty_app_set_focus(newApp, NSApp.isActive)
        subscribeToAppFocusNotifications()
        readiness = .ready
    }

    isolated deinit {
        NotificationCenter.default.removeObserver(self)
        if let app { ghostty_app_free(app) }
    }

    // MARK: - Internal

    func tick() {
        guard let app else { return }
        ghostty_app_tick(app)
    }

    // MARK: - Private helpers

    private static func makeRuntimeConfig(owner: GhosttyApp) -> ghostty_runtime_config_s {
        ghostty_runtime_config_s(
            userdata: Unmanaged.passUnretained(owner).toOpaque(),
            supports_selection_clipboard: false,
            wakeup_cb: { userdata in
                guard let userdata else { return }
                let app = Unmanaged<GhosttyApp>.fromOpaque(userdata).takeUnretainedValue()
                DispatchQueue.main.async { app.tick() }
            },
            action_cb: { app, target, action in
                guard let app else { return false }
                return GhosttyApp.handleAction(app, target: target, action: action)
            },
            read_clipboard_cb: { userdata, loc, state in
                GhosttyApp.readClipboard(userdata, location: loc, state: state)
            },
            confirm_read_clipboard_cb: { userdata, _, state, _ in
                guard let userdata, let state else { return }
                let view = Unmanaged<SurfaceView>.fromOpaque(userdata).takeUnretainedValue()
                guard let surface = view.surface else { return }
                "".withCString { ghostty_surface_complete_clipboard_request(surface, $0, state, true) }
            },
            write_clipboard_cb: { _, _, content, len, _ in
                GhosttyApp.writeClipboard(content: content, len: len)
            },
            close_surface_cb: { userdata, _ in
                guard let userdata else { return }
                let view = Unmanaged<SurfaceView>.fromOpaque(userdata).takeUnretainedValue()
                DispatchQueue.main.async { view.closeSurface() }
            }
        )
    }

    private func subscribeToAppFocusNotifications() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(appDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil)
    }

    @objc private func appDidBecomeActive(_: Notification) {
        guard let app else { return }
        ghostty_app_set_focus(app, true)
    }

    @objc private func appDidResignActive(_: Notification) {
        guard let app else { return }
        ghostty_app_set_focus(app, false)
    }

    // MARK: - Runtime callbacks

    private static func handleAction(
        _ app: ghostty_app_t,
        target: ghostty_target_s,
        action: ghostty_action_s
    ) -> Bool {
        switch action.tag {
        case GHOSTTY_ACTION_QUIT:
            DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
            return true

        case GHOSTTY_ACTION_SET_TITLE:
            guard target.tag == GHOSTTY_TARGET_SURFACE,
                let surface = target.target.surface,
                let userdata = ghostty_surface_userdata(surface)
            else { return false }
            let view = Unmanaged<SurfaceView>.fromOpaque(userdata).takeUnretainedValue()
            let title = action.action.set_title.title.map { String(cString: $0) } ?? ""
            DispatchQueue.main.async { view.title = title }
            return true

        default:
            return false
        }
    }

    private static func readClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        location: ghostty_clipboard_e,
        state: UnsafeMutableRawPointer?
    ) {
        guard let userdata else { return }
        let view = Unmanaged<SurfaceView>.fromOpaque(userdata).takeUnretainedValue()
        guard let surface = view.surface else { return }
        let str = NSPasteboard.general.string(forType: .string) ?? ""
        str.withCString { ptr in
            ghostty_surface_complete_clipboard_request(surface, ptr, state, false)
        }
    }

    private static func writeClipboard(
        content: UnsafePointer<ghostty_clipboard_content_s>?,
        len: Int
    ) {
        guard let content, len > 0 else { return }
        for idx in 0..<len {
            let item = content[idx]
            guard let mime = item.mime.map({ String(cString: $0) }),
                mime == "text/plain",
                let data = item.data.map({ String(cString: $0) })
            else { continue }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(data, forType: .string)
            break
        }
    }
}
