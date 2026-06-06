import AppKit
import GhosttyKit
import OSLog
import SwiftUI

// MARK: - SurfaceView (NSView)

/// One terminal pane. Hosts a `ghostty_surface_t` on a layer-backed NSView.
/// GhosttyKit drives Metal rendering; this class forwards input events and size changes.
@MainActor
final class SurfaceView: NSView {
    static let logger = Logger(subsystem: "com.kotty.app", category: "SurfaceView")

    @Published var title: String = ""

    private(set) var surface: ghostty_surface_t?
    // nonisolated(unsafe): @preconcurrency NSTextInputClient methods access this
    // from nonisolated context; AppKit guarantees main-thread-only calls.
    nonisolated(unsafe) var markedText = NSMutableAttributedString()

    override var acceptsFirstResponder: Bool { true }

    init(app: ghostty_app_t) {
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        wantsLayer = true

        var cfg = ghostty_surface_config_new()
        cfg.userdata = Unmanaged.passUnretained(self).toOpaque()
        cfg.platform_tag = GHOSTTY_PLATFORM_MACOS
        cfg.platform = ghostty_platform_u(
            macos: ghostty_platform_macos_s(nsview: Unmanaged.passUnretained(self).toOpaque())
        )
        cfg.scale_factor = Double(NSScreen.main?.backingScaleFactor ?? 2.0)

        guard let newSurface = ghostty_surface_new(app, &cfg) else {
            Self.logger.critical("ghostty_surface_new failed")
            return
        }
        surface = newSurface
        updateTrackingAreas()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    isolated deinit {
        if let surface { ghostty_surface_free(surface) }
    }

    func closeSurface() {
        window?.close()
    }

    // MARK: - Layout

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        notifySizeChange(newSize)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        notifySizeChange(frame.size)
    }

    private func notifySizeChange(_ size: CGSize) {
        guard let surface else { return }
        let scaled = convertToBacking(size)
        ghostty_surface_set_size(surface, UInt32(scaled.width), UInt32(scaled.height))
    }

    // MARK: - Focus

    override func becomeFirstResponder() -> Bool {
        let succeeded = super.becomeFirstResponder()
        if succeeded { surface.map { ghostty_surface_set_focus($0, true) } }
        return succeeded
    }

    override func resignFirstResponder() -> Bool {
        let succeeded = super.resignFirstResponder()
        if succeeded { surface.map { ghostty_surface_set_focus($0, false) } }
        return succeeded
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        guard let surface else {
            interpretKeyEvents([event])
            return
        }

        let action: ghostty_input_action_e = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
        var keyEvent = event.kottyKeyEvent(action)

        if let chars = event.kottyCharacters, !chars.isEmpty,
            let firstByte = chars.utf8.first, firstByte >= 0x20 {
            chars.withCString { ptr in
                keyEvent.text = ptr
                _ = ghostty_surface_key(surface, keyEvent)
            }
        } else {
            _ = ghostty_surface_key(surface, keyEvent)
        }
    }

    override func keyUp(with event: NSEvent) {
        guard let surface else { return }
        let keyEvent = event.kottyKeyEvent(GHOSTTY_ACTION_RELEASE)
        _ = ghostty_surface_key(surface, keyEvent)
    }

    override func flagsChanged(with event: NSEvent) {
        guard let surface else { return }
        let action: ghostty_input_action_e
        switch event.keyCode {
        case 0x38, 0x3C: action = event.modifierFlags.contains(.shift) ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE
        case 0x3B, 0x3E: action = event.modifierFlags.contains(.control) ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE
        case 0x3A, 0x3D: action = event.modifierFlags.contains(.option) ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE
        case 0x37, 0x36: action = event.modifierFlags.contains(.command) ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE
        default: action = GHOSTTY_ACTION_PRESS
        }
        let keyEvent = event.kottyKeyEvent(action)
        _ = ghostty_surface_key(surface, keyEvent)
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        guard let surface else { return }
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, kottyMods(event))
    }

    override func mouseUp(with event: NSEvent) {
        guard let surface else { return }
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, kottyMods(event))
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let surface else { return super.rightMouseDown(with: event) }
        if !ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT, kottyMods(event)) {
            super.rightMouseDown(with: event)
        }
    }

    override func rightMouseUp(with event: NSEvent) {
        guard let surface else { return super.rightMouseUp(with: event) }
        if !ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT, kottyMods(event)) {
            super.rightMouseUp(with: event)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        guard let surface else { return }
        let pos = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(surface, pos.x, frame.height - pos.y, kottyMods(event))
    }

    override func mouseDragged(with event: NSEvent) { mouseMoved(with: event) }
    override func rightMouseDragged(with event: NSEvent) { mouseMoved(with: event) }

    override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }
        var deltaX = event.scrollingDeltaX
        var deltaY = event.scrollingDeltaY
        if event.hasPreciseScrollingDeltas { deltaX *= 2; deltaY *= 2 }
        let scrollMods: ghostty_input_scroll_mods_t = event.hasPreciseScrollingDeltas ? 0b0000_0001 : 0
        ghostty_surface_mouse_scroll(surface, deltaX, deltaY, scrollMods)
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited],
                owner: self,
                userInfo: nil))
    }

    // MARK: - Helpers

    private func kottyMods(_ event: NSEvent) -> ghostty_input_mods_e {
        ghosttyMods(event.modifierFlags)
    }
}

// MARK: - Modifier translation (module-internal)

func ghosttyMods(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
    var mods: UInt32 = GHOSTTY_MODS_NONE.rawValue
    if flags.contains(.shift) { mods |= GHOSTTY_MODS_SHIFT.rawValue }
    if flags.contains(.control) { mods |= GHOSTTY_MODS_CTRL.rawValue }
    if flags.contains(.option) { mods |= GHOSTTY_MODS_ALT.rawValue }
    if flags.contains(.command) { mods |= GHOSTTY_MODS_SUPER.rawValue }
    if flags.contains(.capsLock) { mods |= GHOSTTY_MODS_CAPS.rawValue }
    let raw = flags.rawValue
    if raw & UInt(NX_DEVICERSHIFTKEYMASK) != 0 { mods |= GHOSTTY_MODS_SHIFT_RIGHT.rawValue }
    if raw & UInt(NX_DEVICERCTLKEYMASK) != 0 { mods |= GHOSTTY_MODS_CTRL_RIGHT.rawValue }
    if raw & UInt(NX_DEVICERALTKEYMASK) != 0 { mods |= GHOSTTY_MODS_ALT_RIGHT.rawValue }
    if raw & UInt(NX_DEVICERCMDKEYMASK) != 0 { mods |= GHOSTTY_MODS_SUPER_RIGHT.rawValue }
    return ghostty_input_mods_e(mods)
}

// MARK: - NSEvent keyboard helpers (mirrors upstream NSEvent+Extension)

extension NSEvent {
    func kottyKeyEvent(
        _ action: ghostty_input_action_e,
        translationMods: NSEvent.ModifierFlags? = nil
    ) -> ghostty_input_key_s {
        var keyEvent = ghostty_input_key_s()
        keyEvent.action = action
        keyEvent.keycode = UInt32(keyCode)
        keyEvent.text = nil
        keyEvent.composing = false
        keyEvent.mods = ghosttyMods(modifierFlags)
        keyEvent.consumed_mods = ghosttyMods(
            (translationMods ?? modifierFlags).subtracting([.control, .command]))
        keyEvent.unshifted_codepoint = 0
        if type == .keyDown || type == .keyUp,
            let chars = characters(byApplyingModifiers: []),
            let scalar = chars.unicodeScalars.first {
            keyEvent.unshifted_codepoint = scalar.value
        }
        return keyEvent
    }

    var kottyCharacters: String? {
        guard let chars = characters else { return nil }
        if chars.count == 1, let scalar = chars.unicodeScalars.first {
            if scalar.value < 0x20 {
                return self.characters(byApplyingModifiers: modifierFlags.subtracting(.control))
            }
            if scalar.value >= 0xF700, scalar.value <= 0xF8FF { return nil }
        }
        return chars
    }
}

// MARK: - NSTextInputClient

extension SurfaceView: @preconcurrency NSTextInputClient {
    func insertText(_ string: Any, replacementRange: NSRange) {}
    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        markedText = NSMutableAttributedString(string: (string as? String) ?? "")
    }
    func unmarkText() { markedText = NSMutableAttributedString() }
    func selectedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
    func markedRange() -> NSRange {
        markedText.length > 0
            ? NSRange(location: 0, length: markedText.length)
            : NSRange(location: NSNotFound, length: 0)
    }
    func hasMarkedText() -> Bool { markedText.length > 0 }
    func attributedSubstring(forProposedRange: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
    func firstRect(forCharacterRange: NSRange, actualRange: NSRangePointer?) -> NSRect { .zero }
    func characterIndex(for: NSPoint) -> Int { 0 }
}

// MARK: - TerminalSurface (SwiftUI wrapper)

/// SwiftUI representable that hosts a single SurfaceView.
struct TerminalSurface: NSViewRepresentable {
    @EnvironmentObject private var ghosttyApp: GhosttyApp

    func makeNSView(context: Context) -> SurfaceView {
        guard let app = ghosttyApp.app else {
            fatalError("GhosttyApp is not ready")
        }
        return SurfaceView(app: app)
    }

    func updateNSView(_ nsView: SurfaceView, context: Context) {}
}
