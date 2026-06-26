import AppKit
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
        guard let sessionName,
            let tmux = tmuxPath(),
            let pane = runTmux(tmux, args: ["capture-pane", "-t", sessionName, "-p"])
        else {
            super.mouseDown(with: event)
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let scale = window?.backingScaleFactor ?? 2.0
        let metrics = (delegate as? TerminalViewState)?.surfaceSize
        let (clickRow, clickCol) = clickCell(point: point, scale: scale, metrics: metrics)

        let candidates = urlCandidates(in: pane)
        guard let target = bestCandidate(candidates, clickRow: clickRow, clickCol: clickCol) else {
            NSSound.beep()
            super.mouseDown(with: event)
            return
        }

        NSWorkspace.shared.open(target)
    }

    // MARK: - URL extraction

    private struct URLCandidate {
        let url: URL
        let row: Int
        let col: Int
    }

    private func urlCandidates(in pane: String) -> [URLCandidate] {
        guard let regex = try? NSRegularExpression(pattern: #"https?://\S+"#) else { return [] }
        var result: [URLCandidate] = []
        for (lineIdx, line) in pane.components(separatedBy: "\n").enumerated() {
            let nsLine = line as NSString
            let full = NSRange(location: 0, length: nsLine.length)
            for match in regex.matches(in: line, range: full) {
                var raw = nsLine.substring(with: match.range)
                while let last = raw.last, ".,;:)]}'\"".contains(last) {
                    raw = String(raw.dropLast())
                }
                if let url = URL(string: raw) {
                    result.append(URLCandidate(url: url, row: lineIdx, col: match.range.location))
                }
            }
        }
        return result
    }

    private func bestCandidate(_ candidates: [URLCandidate], clickRow: Int?, clickCol: Int) -> URL? {
        guard !candidates.isEmpty else { return nil }
        guard let clickRow else { return candidates[0].url }
        return candidates.min {
            abs($0.row - clickRow) * 1000 + abs($0.col - clickCol)
                < abs($1.row - clickRow) * 1000 + abs($1.col - clickCol)
        }?.url ?? candidates[0].url
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

    // MARK: - Helpers

    private func tmuxPath() -> String? {
        ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
            .first { FileManager.default.fileExists(atPath: $0) }
    }

    private func runTmux(_ path: String, args: [String]) -> String? {
        let task = Process()
        task.launchPath = path
        task.arguments = args
        let out = Pipe()
        task.standardOutput = out
        task.standardError = Pipe()
        guard (try? task.run()) != nil else { return nil }
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
