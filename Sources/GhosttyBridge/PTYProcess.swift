import Darwin
import Foundation

/// Owns a PTY master/slave pair and a child shell process.
/// Call `start()` to spawn the shell, `write(_:)` for user input, `resize(cols:rows:)` on terminal resize.
/// Shell output is delivered via `onOutput`.
final class PTYProcess: @unchecked Sendable {
    var onOutput: ((Data) -> Void)?
    private(set) var masterFD: Int32 = -1
    private var childPID: Int32 = -1

    func start(shell: String? = nil) {
        let shellPath = shell
            ?? loginShell()
            ?? ProcessInfo.processInfo.environment["SHELL"]
            ?? "/bin/zsh"

        var pid: Int32 = -1
        let master = shellPath.withCString { cShell in pty_spawn(cShell, &pid) }
        guard master >= 0 else { return }
        masterFD = master
        childPID = pid
        startReadLoop()
    }

    func write(_ data: Data) {
        guard masterFD >= 0 else { return }
        data.withUnsafeBytes { buf in
            guard let ptr = buf.baseAddress else { return }
            _ = Darwin.write(masterFD, ptr, data.count)
        }
    }

    func resize(cols: UInt16, rows: UInt16) {
        guard masterFD >= 0 else { return }
        var ws = winsize()
        ws.ws_col = cols
        ws.ws_row = rows
        _ = ioctl(masterFD, TIOCSWINSZ, &ws)
    }

    func stop() {
        if childPID > 0 { kill(childPID, SIGTERM); childPID = -1 }
        if masterFD >= 0 { close(masterFD); masterFD = -1 }
    }

    deinit { stop() }

    private func loginShell() -> String? {
        guard let pw = getpwuid(getuid()) else { return nil }
        return String(cString: pw.pointee.pw_shell)
    }

    private func startReadLoop() {
        let fd = masterFD
        Thread.detachNewThread { [weak self] in
            var buf = [UInt8](repeating: 0, count: 4096)
            while true {
                let bytesRead = Darwin.read(fd, &buf, buf.count)
                guard bytesRead > 0 else { break }
                let data = Data(buf[..<bytesRead])
                DispatchQueue.main.async { self?.onOutput?(data) }
            }
        }
    }
}
