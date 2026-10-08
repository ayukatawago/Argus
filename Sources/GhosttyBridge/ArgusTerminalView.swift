import AppKit
import ArgusSupport
import GhosttyTerminal

/// AppTerminalView subclass that opens URLs on Cmd+click.
///
/// Two-path implementation:
///  1. Native — if Ghostty's MOUSE_OVER_LINK fires the hoverLink is used (fast).
///  2. Fallback — captures the full visible tmux pane on Cmd+click, finds all
///     URLs, and opens the one closest to the click position.
@MainActor
final class ArgusTerminalView: AppTerminalView {
    var sessionName: String?

    override func mouseDown(with event: NSEvent) {
        guard event.modifierFlags.contains(.command) else {
            super.mouseDown(with: event)
            return
        }

        // Path 1: hover-tracked URL (Ghostty native link detection)
        if let state = delegate as? TerminalViewState,
            let urlString = state.hoverLink,
            let url = URL(string: urlString)
        {
            NSWorkspace.shared.open(url)
            return
        }

        // Path 2: scan full pane via tmux
        openURLAtClick(event: event)
    }

    private func openURLAtClick(event: NSEvent) {
        guard let sessionName else {
            super.mouseDown(with: event)
            return
        }

        // Resolve the click cell now: the event and view geometry are only valid on this turn.
        let point = convert(event.locationInWindow, from: nil)
        let scale = window?.backingScaleFactor ?? 2.0
        let metrics = (delegate as? TerminalViewState)?.surfaceSize
        let (clickRow, clickCol) = clickCell(point: point, scale: scale, metrics: metrics)

        // Off the main thread, with a timeout: this used to be a synchronous `Process` that blocked
        // the UI for as long as tmux took (indefinitely if it wedged).
        Task { @MainActor in
            let capture = await Tmux.run(["capture-pane", "-t", sessionName, "-p"], timeout: 3)
            let candidates = capture.succeeded ? TerminalURLDetector.candidates(in: capture.standardOutput) : []
            guard let target = TerminalURLDetector.best(candidates, clickRow: clickRow, clickColumn: clickCol) else {
                NSSound.beep()
                return
            }
            NSWorkspace.shared.open(target)
        }
    }

    private func clickCell(
        point: CGPoint,
        scale: CGFloat,
        metrics: TerminalGridMetrics?
    ) -> (row: Int?, col: Int) {
        var row: Int?
        if let metrics, metrics.cellHeightPixels > 0 {
            let terminalY = bounds.height - point.y
            row = Int(terminalY * scale) / Int(metrics.cellHeightPixels)
        }
        let col =
            metrics.map { mtr in
                mtr.cellWidthPixels > 0 ? Int(point.x * scale) / Int(mtr.cellWidthPixels) : 0
            } ?? 0
        return (row, col)
    }
}
