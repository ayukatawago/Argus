import Testing

@testable import ArgusSupport

@Suite("JSONQuotedValue")
struct JSONQuotedValueTests {
    @Test("returns the plain value for a key")
    func plain() {
        #expect(JSONQuotedValue.first(forKey: "cwd", in: #"{"type":"x","cwd":"/a/b","n":1}"#) == "/a/b")
    }

    @Test("decodes an escaped quote and backslash instead of stopping or keeping the backslash")
    func escapes() {
        #expect(JSONQuotedValue.first(forKey: "cwd", in: #"{"cwd":"/a/\"q\"/c\\d"}"#) == #"/a/"q"/c\d"#)
    }

    @Test("decodes unicode escapes, including a surrogate pair")
    func unicode() {
        #expect(JSONQuotedValue.first(forKey: "k", in: #"{"k":"é😀"}"#) == "é😀")
    }

    @Test("a lone high surrogate or a bad escape yields nil rather than garbage")
    func malformedUnicode() {
        #expect(JSONQuotedValue.first(forKey: "k", in: #"{"k":"\ud83dx"}"#) == nil)
        #expect(JSONQuotedValue.first(forKey: "k", in: #"{"k":"\u12"}"#) == nil)
    }

    @Test("missing key, empty value and an unterminated window all yield nil")
    func absent() {
        #expect(JSONQuotedValue.first(forKey: "cwd", in: #"{"a":"b"}"#) == nil)
        #expect(JSONQuotedValue.first(forKey: "cwd", in: #"{"cwd":""}"#) == nil)
        #expect(JSONQuotedValue.first(forKey: "cwd", in: #"{"cwd":"/trunca"#) == nil)
    }

    @Test("a key that only appears inside an escaped string value is not matched")
    func keyInsideStringValue() {
        let line = #"{"text":"{\"cwd\":\"/inner\"}","cwd":"/outer"}"#
        #expect(JSONQuotedValue.first(forKey: "cwd", in: line) == "/outer")
        #expect(JSONQuotedValue.occurrences(ofKey: "cwd", in: line) == 1)
    }

    @Test("occurrences counts every unescaped marker")
    func occurrences() {
        #expect(JSONQuotedValue.occurrences(ofKey: "t", in: #"{"t":"a","x":{"t":"b"}}"#) == 2)
        #expect(JSONQuotedValue.occurrences(ofKey: "t", in: "{}") == 0)
    }
}
