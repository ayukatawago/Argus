import AgentStateKit
import ArgusConfigKit
import ArgusSupport
import SwiftUI
import Workspaces

struct PaletteItem: Identifiable {
    enum Kind {
        case worktree(id: String)
        case action(LeaderAction)
        case popup(id: String)
    }

    let id: String
    let kind: Kind
    let title: String
    let subtitle: String
    /// The leader key that triggers this item, shown as a hint.
    var key: String?
    var agentState: AgentState?
    var agentType: AgentType = .claude

    /// Strings the fuzzy matcher scores against.
    var searchTerms: [String] { [title, subtitle] }

    /// Fires the action/popup this item stands for; a worktree item has nothing to post.
    func postNotification() {
        switch kind {
        case .worktree: break
        case .action(let action): NotificationCenter.default.post(name: action.notificationName, object: nil)
        case .popup(let id): NotificationCenter.default.post(name: .openPopupTerminal, object: id)
        }
    }

    /// Every worktree (agent state attached), leader action and popup shortcut the palette offers,
    /// in the order they show for an empty query.
    static func items(
        repos: [GitRepo], hidden: Set<String>, config: ArgusConfig,
        agentState: (String) -> WorktreeAgentState
    ) -> [PaletteItem] {
        var items: [PaletteItem] = []
        for repo in repos {
            for worktree in repo.worktrees where !hidden.contains(worktree.id) {
                let state = agentState(worktree.id)
                let name = worktree.branch ?? URL(fileURLWithPath: worktree.path).lastPathComponent
                items.append(
                    PaletteItem(
                        id: worktree.id, kind: .worktree(id: worktree.id), title: name, subtitle: repo.name,
                        agentState: state.state, agentType: state.agent))
            }
        }
        let pairs = LeaderActionCatalog.entries(config: config).map { ($0.title, $0.key) }
        let keys = Dictionary(pairs, uniquingKeysWith: { first, _ in first })
        for action in LeaderAction.allCases where action != .openCommandPalette {
            items.append(
                PaletteItem(
                    id: "action.\(action)", kind: .action(action), title: action.title, subtitle: "Action",
                    key: keys[action.title].map { "\(config.leaderKey) \($0)" }))
        }
        for shortcut in config.popupShortcuts {
            items.append(
                PaletteItem(
                    id: "popup.\(shortcut.id)", kind: .popup(id: shortcut.id), title: shortcut.name,
                    subtitle: "Popup", key: shortcut.key.isEmpty ? nil : "\(config.leaderKey) \(shortcut.key)"))
        }
        return items
    }
}

/// ⌘K palette: fuzzy-switch to a worktree or run any leader action by name.
struct CommandPaletteView: View {
    let items: [PaletteItem]
    let onSelect: (PaletteItem) -> Void
    let onClose: () -> Void

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var fieldFocused: Bool

    private var results: [PaletteItem] {
        FuzzyMatcher.rank(items, query: query.trimmingCharacters(in: .whitespaces), candidates: \.searchTerms)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
            VStack(spacing: 0) {
                TextField("Switch worktree or run a command…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .padding(12)
                    .focused($fieldFocused)
                    .onSubmit(commit)
                    .onKeyPress(.upArrow) { move(-1) }
                    .onKeyPress(.downArrow) { move(1) }
                    .onKeyPress(.escape) {
                        onClose()
                        return .handled
                    }
                Divider()
                resultList
            }
            .frame(width: 560)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .shadow(radius: 20)
            .padding(.top, 80)
        }
        .onAppear { fieldFocused = true }
        .onChange(of: query) { _, _ in selection = 0 }
    }

    private var resultList: some View {
        let current = results
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if current.isEmpty {
                        Text("No matches")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(16)
                    }
                    ForEach(Array(current.enumerated()), id: \.element.id) { index, item in
                        row(item, isSelected: index == selection)
                            .id(item.id)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(item) }
                    }
                }
            }
            .frame(maxHeight: 360)
            .onChange(of: selection) { _, newValue in
                if current.indices.contains(newValue) { proxy.scrollTo(current[newValue].id) }
            }
        }
    }

    private func row(_ item: PaletteItem, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            if let state = item.agentState, state != .idle {
                AgentDot(state: state, agentType: item.agentType)
            }
            Text(item.title).lineLimit(1)
            Text(item.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if let key = item.key {
                Text(key)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        let count = results.count
        guard count > 0 else { return .handled }
        selection = max(0, min(count - 1, selection + delta))
        return .handled
    }

    private func commit() {
        let current = results
        guard current.indices.contains(selection) else { return }
        onSelect(current[selection])
    }
}
