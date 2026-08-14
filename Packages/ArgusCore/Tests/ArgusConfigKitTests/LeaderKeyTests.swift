import Testing

@testable import ArgusConfigKit

@Suite("LeaderKey")
struct LeaderKeyTests {
    @Test("ctrl+b parses to control + b")
    func ctrlB() {
        let chord = LeaderKey.parse("ctrl+b")
        #expect(chord == LeaderChord(modifiers: [.control], character: "b"))
    }

    @Test("cmd+shift+p parses to command, shift + p")
    func cmdShiftP() {
        let chord = LeaderKey.parse("cmd+shift+p")
        #expect(chord == LeaderChord(modifiers: [.command, .shift], character: "p"))
    }

    @Test(
        "opt/option/alt all map to the .option modifier",
        arguments: ["opt+b", "option+b", "alt+b"]
    )
    func optionAliases(input: String) {
        let chord = LeaderKey.parse(input)
        #expect(chord == LeaderChord(modifiers: [.option], character: "b"))
    }

    @Test("a bare character with no modifiers parses to an empty modifier set")
    func bareCharacter() {
        let chord = LeaderKey.parse("b")
        #expect(chord == LeaderChord(modifiers: [], character: "b"))
    }

    @Test("an empty string returns nil")
    func emptyString() {
        #expect(LeaderKey.parse("") == nil)
    }

    @Test("a string with no character component returns nil")
    func noCharacterComponent() {
        #expect(LeaderKey.parse("+") == nil)
        #expect(LeaderKey.parse("++") == nil)
    }

    @Test("an unrecognized modifier token is ignored, not treated as an error")
    func unknownModifierIgnored() {
        let chord = LeaderKey.parse("meta+b")
        #expect(chord == LeaderChord(modifiers: [], character: "b"))
    }

    @Test("parsing is case-insensitive")
    func caseInsensitive() {
        let chord = LeaderKey.parse("CTRL+B")
        #expect(chord == LeaderChord(modifiers: [.control], character: "b"))
    }

    @Test("cmd and command are both accepted for the command modifier")
    func cmdAndCommandAliases() {
        #expect(LeaderKey.parse("cmd+k") == LeaderChord(modifiers: [.command], character: "k"))
        #expect(LeaderKey.parse("command+k") == LeaderChord(modifiers: [.command], character: "k"))
    }
}
