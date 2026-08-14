import Testing

@testable import ArgusConfigKit

@Suite("EnvExportPreamble")
struct EnvExportPreambleTests {
    @Test("an empty dictionary produces an empty string")
    func emptyDictionary() {
        #expect(EnvExportPreamble.make(from: [:]) == "")
    }

    @Test("a single variable is exported and terminated with '; '")
    func singleVariable() {
        let result = EnvExportPreamble.make(from: ["FOO": "bar"])
        #expect(result == "export FOO=\"bar\"; ")
    }

    @Test("multiple variables are sorted by key for stable output")
    func sortedByKey() {
        let result = EnvExportPreamble.make(from: ["ZED": "1", "ALPHA": "2"])
        #expect(result == "export ALPHA=\"2\"; export ZED=\"1\"; ")
    }

    @Test("backslashes, double quotes, dollar signs, and backticks are escaped")
    func escapesSpecialCharacters() {
        let result = EnvExportPreamble.make(from: ["VAR": #"a\b"c$d`e"#])
        #expect(result == #"export VAR="a\\b\"c\$d\`e"; "#)
    }
}
