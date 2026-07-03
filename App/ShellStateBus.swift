import Foundation

/// Polls tmux every ~400 ms to detect which shell panes have a foreground
/// command running (i.e. pane_current_command is not a known shell name).
/// Keys are worktree paths, matching GitWorktree.id and AgentStateBus keys.
@MainActor
final class ShellStateBus: ObservableObject {
    @Published private(set) var busyPaths: Set<String> = []

    private var pollTask: Task<Void, Never>?
    private var activePaths: Set<String> = []

    private static let shellNames: Set<String> = [
        "bash", "zsh", "fish", "sh", "dash", "ksh", "tcsh", "csh",
    ]

    func updateActivePaths(_ paths: Set<String>) {
        activePaths = paths
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        busyPaths = []
    }

    private func poll() async {
        let paths = activePaths
        guard !paths.isEmpty else {
            busyPaths = []
            return
        }
        let tmux = WorktreePane.tmuxExecutable
        let output = await Task.detached(priority: .utility) { () -> String in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: tmux)
            process.arguments = ["list-panes", "-a", "-F", "#{session_name}|#{pane_current_command}"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
            return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        }.value

        var sessionToCommand: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "|", maxSplits: 1)
            if parts.count == 2 {
                sessionToCommand[String(parts[0])] = String(parts[1])
            }
        }

        var newBusy: Set<String> = []
        for path in paths {
            let session = WorktreePane.sessionName("s", path: path)
            if let cmd = sessionToCommand[session], !ShellStateBus.shellNames.contains(cmd) {
                newBusy.insert(path)
            }
        }
        busyPaths = newBusy
    }
}
