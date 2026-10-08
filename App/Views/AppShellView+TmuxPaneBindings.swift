import ArgusConfigKit
import ArgusSupport
import GhosttyTerminal
import SwiftUI

extension View {
    /// Leader-key bindings for literal tmux pane-split navigation (`select-pane -L/-D/-U/-R`) —
    /// distinct from `focusPaneLeft`/`focusPaneRight`, which switch which of Argus's own
    /// shell/claude/codex roles is focused (see `AppShellView.stepFocus`). These target whichever
    /// tmux session `focusedRole` currently points to, so they only do anything once the user has
    /// manually split that session's window with tmux's own `split-window` — `select-pane` against
    /// a single-pane window is a safe no-op, so dispatching unconditionally needs no extra guard.
    func onReceiveTmuxPaneBindings(focusedRole: Binding<PaneRole>, worktreePath: String?) -> some View {
        onReceive(NotificationCenter.default.publisher(for: .tmuxPaneLeft)) { _ in
            selectTmuxPane(direction: "-L", focusedRole: focusedRole.wrappedValue, worktreePath: worktreePath)
        }
        .onReceive(NotificationCenter.default.publisher(for: .tmuxPaneDown)) { _ in
            selectTmuxPane(direction: "-D", focusedRole: focusedRole.wrappedValue, worktreePath: worktreePath)
        }
        .onReceive(NotificationCenter.default.publisher(for: .tmuxPaneUp)) { _ in
            selectTmuxPane(direction: "-U", focusedRole: focusedRole.wrappedValue, worktreePath: worktreePath)
        }
        .onReceive(NotificationCenter.default.publisher(for: .tmuxPaneRight)) { _ in
            selectTmuxPane(direction: "-R", focusedRole: focusedRole.wrappedValue, worktreePath: worktreePath)
        }
    }
}

@MainActor
private func selectTmuxPane(direction: String, focusedRole: PaneRole, worktreePath: String?) {
    guard let worktreePath else { return }
    let session = WorktreePane.sessionName(for: focusedRole, path: worktreePath)
    Task {
        await Tmux.run(TmuxCommand.selectPane(session: session, direction: direction))
    }
}
