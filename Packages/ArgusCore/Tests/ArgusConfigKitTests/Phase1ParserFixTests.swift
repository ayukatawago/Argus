import Testing

@testable import ArgusConfigKit

@Suite("LeaderKey and EnvExportPreamble fixes")
struct Phase1ParserFixTests {
    @Test("a doubled trailing plus after a modifier binds the + character")
    func plusKey() {
        #expect(LeaderKey.parse("ctrl++") == LeaderChord(modifiers: [.control], character: "+"))
        #expect(LeaderKey.parse("cmd+shift++") == LeaderChord(modifiers: [.command, .shift], character: "+"))
    }

    @Test("existing forms are unchanged")
    func existingForms() {
        #expect(LeaderKey.parse("ctrl+b") == LeaderChord(modifiers: [.control], character: "b"))
        #expect(LeaderKey.parse("b+") == LeaderChord(modifiers: [], character: "b"))
        #expect(LeaderKey.parse("++") == nil)
        #expect(LeaderKey.parse("") == nil)
    }

    @Test("environment keys that are not shell identifiers are skipped, not interpolated")
    func invalidKeysSkipped() {
        let result = EnvExportPreamble.make(from: [
            "GOOD_1": "x", "A; rm -rf ~": "y", "A B": "z", "1BAD": "w", "": "v", "É": "u",
        ])
        #expect(result == "export GOOD_1=\"x\"; ")
    }

    @Test("if every key is invalid the result is empty")
    func allInvalid() {
        #expect(EnvExportPreamble.make(from: ["a-b": "1"]) == "")
    }

    @Test("identifier validation")
    func validation() {
        #expect(EnvExportPreamble.isValidName("_x9"))
        #expect(!EnvExportPreamble.isValidName("9x"))
        #expect(!EnvExportPreamble.isValidName("a=b"))
    }
}
