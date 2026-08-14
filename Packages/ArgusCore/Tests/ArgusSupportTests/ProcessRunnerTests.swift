import Testing

@testable import ArgusSupport

@Suite("ProcessRunner")
struct ProcessRunnerTests {
    @Test("captures stdout and a zero exit code")
    func capturesStdout() async {
        let result = await ProcessRunner.run("/bin/echo", ["hello"])
        #expect(result.succeeded)
        #expect(result.exitCode == 0)
        #expect(result.standardOutput == "hello\n")
    }

    @Test("captures a non-zero exit code")
    func capturesFailure() async {
        let result = await ProcessRunner.run("/usr/bin/false")
        #expect(!result.succeeded)
        #expect(result.exitCode == 1)
    }

    @Test("captures stderr separately from stdout")
    func capturesStderr() async {
        let result = await ProcessRunner.run("/bin/sh", ["-c", "echo out; echo err 1>&2"])
        #expect(result.standardOutput == "out\n")
        #expect(result.standardError == "err\n")
    }

    @Test("a missing binary fails gracefully instead of throwing")
    func missingBinary() async {
        let result = await ProcessRunner.run("/no/such/binary")
        #expect(result.exitCode == -1)
        #expect(!result.standardError.isEmpty)
    }

    @Test("runs in the given working directory")
    func currentDirectory() async {
        let result = await ProcessRunner.run("/bin/pwd", [], currentDirectory: "/tmp")
        #expect(result.succeeded)
        // /tmp may be a symlink (e.g. to /private/tmp on macOS); check the resolved suffix.
        #expect(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("tmp"))
    }
}
