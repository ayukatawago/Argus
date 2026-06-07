import Foundation
import GhosttyTerminal

/// Owns a PTYProcess and an InMemoryTerminalSession, wiring them together.
/// Use `terminalState` as the context for TerminalSurfaceView.
@MainActor
final class TerminalController: ObservableObject {
    let terminalState: TerminalViewState
    private let session: InMemoryTerminalSession
    private let pty: PTYProcess

    init() {
        let pty = PTYProcess()
        // [weak pty] breaks the pty ↔ session retain cycle
        let session = InMemoryTerminalSession(
            write: { [weak pty] data in pty?.write(data) },
            resize: { [weak pty] viewport in
                pty?.resize(cols: UInt16(viewport.columns), rows: UInt16(viewport.rows))
            }
        )
        pty.onOutput = { [weak session] data in session?.receive(data) }

        self.pty = pty
        self.session = session
        self.terminalState = TerminalViewState(
            terminalConfiguration: TerminalConfiguration {
                $0.withFontSize(13)
                $0.withCursorStyleBlink(true)
            }
        )
        terminalState.configuration = TerminalSurfaceOptions(backend: .inMemory(session))
    }

    func start() {
        pty.start()
    }

    func restart(workingDirectory: String) {
        pty.stop()
        pty.start(workingDirectory: workingDirectory)
    }
}
