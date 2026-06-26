import AppKit
import GhosttyTerminal
import ObjectiveC

// The address of this variable is the key for objc_setAssociatedObject.
// nonisolated(unsafe): always accessed on @MainActor; external sync guarantees safety.
private nonisolated(unsafe) var hoverLinkKey: UInt8 = 0

extension TerminalViewState: @retroactive TerminalSurfaceOpenURLDelegate,
    @retroactive TerminalSurfaceHoverLinkDelegate
{
    var hoverLink: String? {
        objc_getAssociatedObject(self, &hoverLinkKey) as? String
    }

    public func terminalDidRequestOpenURL(_ url: String, kind: TerminalOpenURLKind) {
        guard let parsed = URL(string: url) else { return }
        NSWorkspace.shared.open(parsed)
    }

    public func terminalDidUpdateHoverLink(_ url: String?) {
        objc_setAssociatedObject(self, &hoverLinkKey, url, .OBJC_ASSOCIATION_COPY_NONATOMIC)
    }
}
