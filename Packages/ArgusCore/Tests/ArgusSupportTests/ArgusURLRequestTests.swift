import Foundation
import Testing

@testable import ArgusSupport

@Suite("ArgusURLRequest")
struct ArgusURLRequestTests {
    private func parse(
        _ string: String, kind: @escaping (String) -> ArgusURLRequest.ItemKind = { _ in .missing }
    ) -> Result<ArgusURLRequest, ArgusURLRequest.Rejection> {
        ArgusURLRequest.parse(URL(string: string) ?? URL(fileURLWithPath: "/"), itemKind: kind)
    }

    // MARK: diff

    @Test("a diff request carries workspace, from and to, with HEAD as the default head")
    func diff() {
        #expect(
            parse("argus://diff?workspace=/r&from=main&to=feat")
                == .success(.diff(workspace: "/r", base: "main", head: "feat")))
        #expect(parse("argus://diff?workspace=/r") == .success(.diff(workspace: "/r", base: "", head: "HEAD")))
    }

    @Test("a diff request without a workspace is rejected")
    func diffMissingWorkspace() {
        #expect(parse("argus://diff") == .failure(.missingWorkspace))
        #expect(parse("argus://diff?workspace=") == .failure(.missingWorkspace))
    }

    @Test("percent-encoded values are decoded")
    func percentDecoding() {
        #expect(
            parse("argus://diff?workspace=/My%20Repo&from=a%2Fb")
                == .success(.diff(workspace: "/My Repo", base: "a/b", head: "HEAD")))
    }

    @Test("an unknown host is unsupported")
    func unknownHost() {
        #expect(parse("argus://nope") == .failure(.unsupportedHost))
    }

    // MARK: capture

    @Test("a screenshot to a .png and a video to .mov/.mp4 are accepted")
    func captureAccepted() {
        #expect(
            parse("argus://capture?mode=screenshot&output=/tmp/a.png")
                == .success(.capture(.init(mode: .screenshot, outputPath: "/tmp/a.png", duration: 10))))
        #expect(
            parse("argus://capture?mode=video&output=/tmp/a.mov&duration=5")
                == .success(.capture(.init(mode: .video, outputPath: "/tmp/a.mov", duration: 5))))
        #expect(parse("argus://capture?mode=video&output=/tmp/a.MP4") != .failure(.badOutputExtension))
    }

    @Test(
        "an output with the wrong extension for its mode is refused",
        arguments: [
            "argus://capture?mode=screenshot&output=/Users/me/.zshrc",
            "argus://capture?mode=screenshot&output=/tmp/a.mov",
            "argus://capture?mode=video&output=/tmp/a.png",
            "argus://capture?mode=screenshot&output=/tmp/noextension",
            "argus://capture?mode=screenshot&output=/tmp/a.png.sh",
        ])
    func wrongExtension(_ url: String) {
        #expect(parse(url) == .failure(.badOutputExtension))
    }

    @Test("a relative output, missing output or unknown mode is refused")
    func malformedCapture() {
        #expect(parse("argus://capture?mode=screenshot&output=a.png") == .failure(.outputNotAbsolute))
        #expect(parse("argus://capture?mode=screenshot") == .failure(.missingOutput))
        #expect(parse("argus://capture?mode=gif&output=/tmp/a.png") == .failure(.unknownMode))
        #expect(parse("argus://capture?output=/tmp/a.png") == .failure(.unknownMode))
    }

    @Test("an existing regular file may be replaced; a symlink, directory or device may not")
    func overwriteRule() {
        let url = "argus://capture?mode=screenshot&output=/tmp/a.png"
        #expect(parse(url, kind: { _ in .regularFile }) != .failure(.outputTargetNotRegularFile))
        #expect(parse(url, kind: { _ in .other }) == .failure(.outputTargetNotRegularFile))
    }

    @Test("`..` segments are resolved before the extension and overwrite checks")
    func traversalResolved() {
        let result = parse("argus://capture?mode=screenshot&output=/tmp/x/../a.png")
        #expect(result == .success(.capture(.init(mode: .screenshot, outputPath: "/tmp/a.png", duration: 10))))
        #expect(
            parse("argus://capture?mode=screenshot&output=/tmp/a.png/../../etc/passwd") == .failure(.badOutputExtension)
        )
    }

    @Test(
        "the duration is defaulted when absent or invalid, and capped",
        arguments: [
            ("", 10.0), ("&duration=abc", 10.0), ("&duration=-3", 10.0), ("&duration=0", 10.0), ("&duration=nan", 10.0),
            ("&duration=99999", 300.0), ("&duration=2.5", 2.5),
        ])
    func duration(suffix: String, expected: Double) {
        guard case .success(.capture(let capture)) = parse("argus://capture?mode=video&output=/tmp/a.mov" + suffix)
        else {
            Issue.record("expected a capture")
            return
        }
        #expect(capture.duration == expected)
    }

    // MARK: file system item kind

    @Test("fileSystemItemKind reports missing, regular file and symlink (without following it)")
    func itemKinds() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("url-req-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("f.png")
        try Data("x".utf8).write(to: file)
        let link = dir.appendingPathComponent("l.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)

        #expect(ArgusURLRequest.fileSystemItemKind(dir.appendingPathComponent("none.png").path) == .missing)
        #expect(ArgusURLRequest.fileSystemItemKind(file.path) == .regularFile)
        #expect(ArgusURLRequest.fileSystemItemKind(link.path) == .other)
        #expect(ArgusURLRequest.fileSystemItemKind(dir.path) == .other)
    }
}
