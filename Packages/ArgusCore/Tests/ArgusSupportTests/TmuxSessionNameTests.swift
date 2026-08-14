import Testing

@testable import ArgusSupport

@Suite("TmuxSessionName")
struct TmuxSessionNameTests {
    @Test("the same path yields the same name across calls")
    func deterministicAcrossCalls() {
        let first = TmuxSessionName.make(type: "a", path: "/Users/taku/workspace/app/Argus")
        let second = TmuxSessionName.make(type: "a", path: "/Users/taku/workspace/app/Argus")
        #expect(first == second)
    }

    @Test("different paths yield different names")
    func differentPathsDiffer() {
        let first = TmuxSessionName.make(type: "a", path: "/Users/taku/workspace/app/Argus")
        let second = TmuxSessionName.make(type: "a", path: "/Users/taku/workspace/app/Other")
        #expect(first != second)
    }

    @Test("different types yield different names for the same path")
    func differentTypesDiffer() {
        let shell = TmuxSessionName.make(type: "s", path: "/tmp/repo")
        let claude = TmuxSessionName.make(type: "a", path: "/tmp/repo")
        #expect(shell != claude)
    }

    @Test("the name has the argus-<type>-<safe-name>-<hash> shape")
    func nameShape() {
        let name = TmuxSessionName.make(type: "a", path: "/tmp/my-feature")
        #expect(name.hasPrefix("argus-a-my-feature-"))
        let hash = name.components(separatedBy: "-").last ?? ""
        #expect(hash.count == 6)
        #expect(hash.allSatisfy { $0.isHexDigit })
    }

    @Test("characters outside [a-zA-Z0-9_-] are sanitized to a dash")
    func sanitizesUnsafeCharacters() {
        let name = TmuxSessionName.make(type: "a", path: "/tmp/my feature (v2)")
        #expect(name.hasPrefix("argus-a-my-feature--v2--"))
    }

    @Test("the sanitized path component is truncated to 20 characters")
    func truncatesLongNames() {
        let longName = String(repeating: "x", count: 40)
        let name = TmuxSessionName.make(type: "a", path: "/tmp/\(longName)")
        // "argus-a-" + 20 x's + "-" + 6-hex-char hash
        let expectedPrefix = "argus-a-" + String(repeating: "x", count: 20) + "-"
        #expect(name.hasPrefix(expectedPrefix))
    }
}
