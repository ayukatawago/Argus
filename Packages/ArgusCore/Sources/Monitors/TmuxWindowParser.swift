import Foundation

/// One tmux window, as reported by `tmux list-windows`. One window = one tab in the terminal
/// tab bar; tabs are just tmux window indices, nothing more.
public struct TmuxWindow: Equatable, Sendable, Identifiable {
    public let sessionName: String
    public let index: Int
    public let isActive: Bool
    /// The active pane's current working directory, absolute path.
    public let currentPath: String

    public var id: Int { index }

    public init(sessionName: String, index: Int, isActive: Bool, currentPath: String) {
        self.sessionName = sessionName
        self.index = index
        self.isActive = isActive
        self.currentPath = currentPath
    }

    /// The tab label — the current directory's folder name, updating live as the user `cd`s
    /// around. Falls back to the window index if the path can't be read (empty `currentPath`).
    public var label: String {
        guard !currentPath.isEmpty else { return "\(index)" }
        let name = URL(fileURLWithPath: currentPath).lastPathComponent
        return name.isEmpty ? "\(index)" : name
    }
}

/// Parses `tmux list-windows` output for the terminal tab bar.
public enum TmuxWindowParser {
    /// Field order must match `parse`. Tab-separated rather than `|`-separated: a path can
    /// contain `|` but a literal tab in a path is practically unheard of.
    public static let listFormat = "#{session_name}\t#{window_index}\t#{window_active}\t#{pane_current_path}"

    /// Parses `tmux list-windows -a -F listFormat` output, sorted by window index. Lines with
    /// the wrong field count or a non-integer index are skipped.
    public static func parse(_ output: String) -> [TmuxWindow] {
        var windows: [TmuxWindow] = []
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count == 4, let index = Int(parts[1]) else { continue }
            windows.append(
                TmuxWindow(
                    sessionName: String(parts[0]),
                    index: index,
                    isActive: parts[2] == "1",
                    currentPath: String(parts[3])
                ))
        }
        return windows.sorted { $0.index < $1.index }
    }
}
