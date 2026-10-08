import Foundation
import Testing

@testable import ArgusConfigKit

struct LeaderActionCatalogTests {
    @Test func defaultEntriesSkipUnboundKeys() {
        let entries = LeaderActionCatalog.entries(config: ArgusConfig())
        #expect(!entries.contains { $0.key.isEmpty })
        #expect(!entries.contains { $0.target == .action(.nextTerminalTab) })
        #expect(entries.contains { $0.target == .action(.openCommandPalette) && $0.key == "/" })
    }

    @Test func defaultKeysAreUnique() {
        let entries = LeaderActionCatalog.entries(config: ArgusConfig())
        let keys = entries.map(\.key)
        #expect(Set(keys).count == keys.count)
    }

    @Test func duplicateKeyKeepsFirstEntry() {
        var config = ArgusConfig()
        config.keyBindings.openNvim = "z"
        config.keyBindings.openSettings = "z"
        let matching = LeaderActionCatalog.entries(config: config).filter { $0.key == "z" }
        #expect(matching.count == 1)
        #expect(matching.first?.target == .action(.openNvim))
    }

    @Test func popupShortcutsAreIncludedAndShadowedByActions() {
        var config = ArgusConfig()
        config.popupShortcuts = [.init(id: "p1", name: "top", key: "y", command: "top", sizePercent: 50)]
        #expect(LeaderActionCatalog.target(forKey: "y", config: config) == .popup(id: "p1"))
        config.popupShortcuts[0].key = config.keyBindings.openNvim
        #expect(LeaderActionCatalog.target(forKey: config.keyBindings.openNvim, config: config) == .action(.openNvim))
    }

    @Test func unboundKeyResolvesToNil() {
        #expect(LeaderActionCatalog.target(forKey: "~", config: ArgusConfig()) == nil)
    }

    @Test func oldConfigWithoutNewBindingsDecodesDefaults() throws {
        let data = Data(#"{"keyBindings":{"openNvim":"v"}}"#.utf8)
        let config = try JSONDecoder().decode(ArgusConfig.self, from: data)
        #expect(config.keyBindings.openCommandPalette == "/")
        #expect(config.keyBindings.jumpToAttention == "e")
        #expect(config.keyBindings.focusSidebarFilter == "f")
    }
}

struct LeaderActionTableTests {
    @Test func everyActionHasATitleAndDistinctDefaultKeyOrNone() {
        let bindings = ArgusConfig.KeyBindings()
        for action in LeaderAction.allCases {
            #expect(!action.title.isEmpty)
            _ = action.key(in: bindings)
        }
        #expect(Set(LeaderAction.allCases.map(\.title)).count == LeaderAction.allCases.count)
    }
}
