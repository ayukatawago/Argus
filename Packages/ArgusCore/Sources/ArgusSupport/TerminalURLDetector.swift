import Foundation

/// Finds `http(s)://` URLs in captured terminal text and picks the one a click landed on.
/// Pure so the matching, trimming and column math are unit-testable; the view layer only feeds it
/// a `tmux capture-pane` dump and a click cell.
public enum TerminalURLDetector {
    public struct Candidate: Equatable, Sendable {
        public let url: URL
        public let row: Int
        /// First terminal column the URL occupies (display cells, not characters).
        public let startColumn: Int
        /// One past the last column it occupies.
        public let endColumn: Int

        public init(url: URL, row: Int, startColumn: Int, endColumn: Int) {
            self.url = url
            self.row = row
            self.startColumn = startColumn
            self.endColumn = endColumn
        }
    }

    // Constant pattern: construction cannot fail, but is optional-returning in Foundation.
    private static let pattern = try? NSRegularExpression(pattern: #"https?://\S+"#)

    public static func candidates(in pane: String) -> [Candidate] {
        guard let regex = pattern else { return [] }
        var result: [Candidate] = []
        for (row, line) in pane.components(separatedBy: "\n").enumerated() {
            let nsLine = line as NSString
            for match in regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length)) {
                let raw = trimmed(nsLine.substring(with: match.range))
                guard let url = URL(string: raw) else { continue }
                let prefix = nsLine.substring(to: match.range.location)
                let start = displayWidth(of: prefix)
                result.append(
                    Candidate(url: url, row: row, startColumn: start, endColumn: start + displayWidth(of: raw)))
            }
        }
        return result
    }

    /// The candidate to open for a click at (`clickRow`, `clickColumn`). A click inside a URL's own
    /// span wins outright; otherwise the nearest one (rows weigh far more than columns). With no
    /// known click row — metrics unavailable — the first URL on screen.
    public static func best(_ candidates: [Candidate], clickRow: Int?, clickColumn: Int) -> URL? {
        guard let first = candidates.first else { return nil }
        guard let clickRow else { return first.url }
        if let hit = candidates.first(where: {
            $0.row == clickRow && (($0.startColumn)..<$0.endColumn).contains(clickColumn)
        }) {
            return hit.url
        }
        return candidates.min { distance($0, clickRow, clickColumn) < distance($1, clickRow, clickColumn) }?.url
            ?? first.url
    }

    private static func distance(_ candidate: Candidate, _ row: Int, _ column: Int) -> Int {
        let columnGap =
            column < candidate.startColumn ? candidate.startColumn - column : max(0, column - candidate.endColumn + 1)
        return abs(candidate.row - row) * 1_000 + columnGap
    }

    /// Strips sentence punctuation a URL is routinely followed by. A closing bracket is kept when it
    /// balances one inside the URL (`…/Foo_(bar)`), and dropped only when it is unmatched.
    static func trimmed(_ raw: String) -> String {
        var text = raw
        let pairs: [Character: Character] = [")": "(", "]": "[", "}": "{"]
        while let last = text.last {
            if ".,;:!?'\"".contains(last) {
                text.removeLast()
            } else if let opener = pairs[last], text.filter({ $0 == last }).count > text.filter({ $0 == opener }).count
            {
                text.removeLast()
            } else {
                break
            }
        }
        return text
    }

    /// Terminal cells `text` occupies: wide (CJK, emoji) characters take two, combining marks none.
    public static func displayWidth(of text: String) -> Int {
        text.reduce(0) { $0 + width(of: $1) }
    }

    private static func width(of character: Character) -> Int {
        guard let scalar = character.unicodeScalars.first else { return 0 }
        switch scalar.value {
        case 0x0300...0x036F, 0x200B...0x200F, 0xFE00...0xFE0F:
            return 0

        case 0x1100...0x115F, 0x2E80...0xA4CF, 0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE6F,
            0xFF00...0xFF60, 0xFFE0...0xFFE6, 0x1F300...0x1F64F, 0x1F900...0x1F9FF, 0x20000...0x3FFFD:
            return 2

        default:
            return 1
        }
    }
}
