import Foundation

extension ArgusConfig {
    public struct KeyBindings: Codable, Equatable, Sendable {
        public var focusPaneLeft: String = "["
        public var focusPaneRight: String = "]"
        // These four send a literal `tmux select-pane -L/-D/-U/-R` to whichever tmux session
        // `focusedRole` currently points to — distinct from focusPaneLeft/Right above, which
        // switch which of Argus's own shell/claude/codex roles is focused. Only meaningful if
        // that session's window was manually split with tmux's own `split-window`; a no-op
        // otherwise.
        public var tmuxPaneLeft: String = "h"
        public var tmuxPaneDown: String = "j"
        public var tmuxPaneUp: String = "k"
        public var tmuxPaneRight: String = "l"
        public var selectNextWorktree: String = "n"
        public var selectPreviousWorktree: String = "p"
        public var openNvim: String = "v"
        public var refreshWorkspace: String = "r"
        public var openMarkdownPreview: String = "m"
        public var openSettings: String = ","
        public var reloadAgentPane: String = "a"
        public var openDiskStatus: String = "d"
        public var openDiffReview: String = "w"
        public var openCodexUsage: String = "u"
        // These four act on whichever pane has focus: tmux windows in the shell pane, agent tabs
        // in the agent pane. No default key (still user-settable) — freed up for focusPaneLeft/Right.
        public var newTerminalTab: String = "t"
        public var nextTerminalTab: String = ""
        public var previousTerminalTab: String = ""
        public var closeTerminalTab: String = "x"
        public var toggleAgentSplit: String = "s"
        public var openCommandPalette: String = "/"
        // Not "g": the default lazygit popup shortcut already claims it.
        public var jumpToAttention: String = "e"
        public var focusSidebarFilter: String = "f"

        // Memberwise init needed because we declare a custom init(from:).
        public init() {}

        // Decode using decodeIfPresent so that missing or renamed keys use Swift defaults
        // rather than failing the entire config load. Legacy key names are tried as fallbacks.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: RawStringKey.self)
            let defaults = KeyBindings()
            func read(_ key: String, legacy: String? = nil, default dflt: String) -> String {
                if let value = try? container.decodeIfPresent(String.self, forKey: RawStringKey(key)) {
                    return value
                }
                if let alt = legacy,
                    let value = try? container.decodeIfPresent(String.self, forKey: RawStringKey(alt))
                {
                    return value
                }
                return dflt
            }
            focusPaneLeft = read("focusPaneLeft", legacy: "focusShellPane", default: defaults.focusPaneLeft)
            focusPaneRight = read("focusPaneRight", legacy: "focusAgentPane", default: defaults.focusPaneRight)
            tmuxPaneLeft = read("tmuxPaneLeft", default: defaults.tmuxPaneLeft)
            tmuxPaneDown = read("tmuxPaneDown", default: defaults.tmuxPaneDown)
            tmuxPaneUp = read("tmuxPaneUp", default: defaults.tmuxPaneUp)
            tmuxPaneRight = read("tmuxPaneRight", default: defaults.tmuxPaneRight)
            selectNextWorktree = read("selectNextWorktree", default: defaults.selectNextWorktree)
            selectPreviousWorktree = read("selectPreviousWorktree", default: defaults.selectPreviousWorktree)
            openNvim = read("openNvim", default: defaults.openNvim)
            refreshWorkspace = read("refreshWorkspace", default: defaults.refreshWorkspace)
            openMarkdownPreview = read("openMarkdownPreview", default: defaults.openMarkdownPreview)
            openSettings = read("openSettings", default: defaults.openSettings)
            reloadAgentPane = read("reloadAgentPane", default: defaults.reloadAgentPane)
            openDiskStatus = read("openDiskStatus", default: defaults.openDiskStatus)
            openDiffReview = read("openDiffReview", default: defaults.openDiffReview)
            openCodexUsage = read("openCodexUsage", default: defaults.openCodexUsage)
            newTerminalTab = read("newTerminalTab", default: defaults.newTerminalTab)
            nextTerminalTab = read("nextTerminalTab", default: defaults.nextTerminalTab)
            previousTerminalTab = read("previousTerminalTab", default: defaults.previousTerminalTab)
            closeTerminalTab = read("closeTerminalTab", default: defaults.closeTerminalTab)
            toggleAgentSplit = read("toggleAgentSplit", default: defaults.toggleAgentSplit)
            openCommandPalette = read("openCommandPalette", default: defaults.openCommandPalette)
            jumpToAttention = read("jumpToAttention", default: defaults.jumpToAttention)
            focusSidebarFilter = read("focusSidebarFilter", default: defaults.focusSidebarFilter)
        }
    }
}
