import ArgusSupport
import Foundation

/// The one place Argus runs tmux: resolves the binary once per call via `TmuxCommand` (honouring
/// `ARGUS_TMUX`) and funnels every invocation through `ProcessRunner`, instead of each store and
/// view repeating `ProcessRunner.run(tmuxPath, …)`.
enum Tmux {
    static var executable: String { TmuxCommand.executablePath() }

    @discardableResult
    static func run(_ arguments: [String], timeout: TimeInterval? = nil) async -> ProcessResult {
        await ProcessRunner.run(executable, arguments, timeout: timeout)
    }
}
