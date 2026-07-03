import Foundation

/// Tracks which shell panes have a command running and publishes the set of busy
/// worktree paths.  Fish shell users get an event-driven path via preexec/postexec
/// hooks installed to ~/.config/fish/conf.d/argus.fish; other shells fall back to
/// polling tmux every 400 ms.
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
        busyPaths = busyPaths.filter { paths.contains($0) }
    }

    func start() {
        guard pollTask == nil else { return }
        if WorktreeHookManager.isFishShell {
            try? FileManager.default.removeItem(atPath: HookIPC.shellEventLogPath)
            pollTask = Task { [weak self] in await self?.tailShellEvents() }
        } else {
            pollTask = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.poll()
                    try? await Task.sleep(nanoseconds: 400_000_000)
                }
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        busyPaths = []
    }

    // MARK: - Fish: tail shell event log

    private func tailShellEvents() async {
        let path = HookIPC.shellEventLogPath
        let url = URL(fileURLWithPath: path)
        var offset: UInt64 = 0
        while !Task.isCancelled {
            guard
                let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                let size = (attrs[.size] as? NSNumber)?.uint64Value
            else {
                offset = 0
                try? await Task.sleep(nanoseconds: 200_000_000)
                continue
            }
            if size < offset { offset = 0 }
            guard size > offset, let handle = try? FileHandle(forReadingFrom: url) else {
                try? await Task.sleep(nanoseconds: 200_000_000)
                continue
            }
            do {
                try handle.seek(toOffset: offset)
                let data = try handle.readToEnd() ?? Data()
                offset = try handle.offset()
                try handle.close()
                guard let text = String(data: data, encoding: .utf8) else { continue }
                for line in text.split(separator: "\n") {
                    guard let lineData = line.data(using: .utf8),
                        let payload = try? JSONDecoder().decode(HookPayload.self, from: lineData)
                    else { continue }
                    applyShellEvent(payload)
                }
            } catch {
                try? handle.close()
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    private func applyShellEvent(_ payload: HookPayload) {
        let path = payload.worktreePath
        if payload.state == "running" {
            busyPaths.insert(path)
        } else {
            busyPaths.remove(path)
        }
        busyPaths = busyPaths.filter { activePaths.contains($0) }
    }

    // MARK: - Non-fish: tmux polling

    private func poll() async {
        let paths = activePaths
        guard !paths.isEmpty else { busyPaths = []; return }
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
