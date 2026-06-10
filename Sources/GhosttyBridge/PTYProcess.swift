import Darwin
import Foundation

/// Owns a PTY master/slave pair and a child shell process.
/// Call `start()` to spawn the shell, `write(_:)` for user input, `resize(cols:rows:)` on terminal resize.
/// Shell output is delivered via `onOutput`.
final class PTYProcess: @unchecked Sendable {
    var onOutput: ((Data) -> Void)?
    private(set) var ptyFD: Int32 = -1
    private var childPID: Int32 = -1

    func start(shell: String? = nil, workingDirectory: String? = nil) {
        let shellPath =
            shell
            ?? loginShell()
            ?? ProcessInfo.processInfo.environment["SHELL"]
            ?? "/bin/zsh"

        var pid: Int32 = -1
        let newFD: Int32
        if let dir = workingDirectory {
            newFD = shellPath.withCString { cShell in
                dir.withCString { cDir in pty_spawn(cShell, cDir, &pid) }
            }
        } else {
            newFD = shellPath.withCString { cShell in pty_spawn(cShell, nil, &pid) }
        }
        guard newFD >= 0 else { return }
        ptyFD = newFD
        childPID = pid
        startReadLoop()
    }

    func write(_ data: Data) {
        guard ptyFD >= 0 else { return }
        data.withUnsafeBytes { buf in
            guard let ptr = buf.baseAddress else { return }
            _ = Darwin.write(ptyFD, ptr, data.count)
        }
    }

    func resize(cols: UInt16, rows: UInt16) {
        guard ptyFD >= 0 else { return }
        var size = winsize()
        size.ws_col = cols
        size.ws_row = rows
        _ = ioctl(ptyFD, TIOCSWINSZ, &size)
    }

    func stop() {
        if childPID > 0 { kill(childPID, SIGTERM); childPID = -1 }
        if ptyFD >= 0 { close(ptyFD); ptyFD = -1 }
    }

    deinit { stop() }

    private func loginShell() -> String? {
        guard let entry = getpwuid(getuid()) else { return nil }
        return String(cString: entry.pointee.pw_shell)
    }

    private func startReadLoop() {
        let capturedFD = ptyFD
        Thread.detachNewThread { [weak self] in
            var buf = [UInt8](repeating: 0, count: 4096)
            while true {
                let bytesRead = Darwin.read(capturedFD, &buf, buf.count)
                guard bytesRead > 0 else { break }
                let data = Data(buf[..<bytesRead])
                DispatchQueue.main.async { self?.onOutput?(data) }
            }
        }
    }
}
