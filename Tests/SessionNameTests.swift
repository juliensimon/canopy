import Foundation
import Testing
@testable import Canopy

@Suite("Claude Session Names")
struct SessionNameTests {
    @Test(arguments: [
        "feature/foo",
        "it's-broken",
        "fix-$HOME",
        "fix-$(whoami)",
        "fix-`rm -rf /`",
        "a;b",
        "a|b",
        "a&b",
        "a>b",
        "my session name",
        "naïve-café-日本語-🌲",
        "",
        "   ",
        String(repeating: "x", count: 500),
        "line\nbreak",
    ])
    func nameEscapingRoundTrips(_ name: String) throws {
        let session = worktreeSession(named: name)

        guard let sanitized = SessionInfo.sanitizedClaudeName(name) else {
            #expect(session.claudeNameFlag == nil)
            return
        }

        let flag = try #require(session.claudeNameFlag)
        let token = try #require(flag.split(separator: " ", maxSplits: 1).last)
        #expect(try shellOutput("printf %s \(token)") == sanitized)
        #expect(sanitized.count <= 64)
    }

    @Test(arguments: ["", "   ", "\n\t"])
    func emptyNamesGetNoNameFlag(_ name: String) {
        #expect(worktreeSession(named: name).claudeNameFlag == nil)
    }

    /// Whitespace control characters are separators, not noise: dropping them
    /// outright welds words together. Hardcoded expectations on purpose --
    /// nameEscapingRoundTrips compares against sanitizedClaudeName's own
    /// output, so it cannot see a sanitizer bug, only a quoting one.
    @Test(arguments: [
        ("line\nbreak", "line break"),
        ("tab\tsep", "tab sep"),
        ("crlf\r\nsep", "crlf sep"),
        ("many \n\t  gaps", "many gaps"),
        ("  leading and trailing  ", "leading and trailing"),
        ("bell\u{07}kept", "bellkept"),
    ])
    func whitespaceControlsBecomeSeparators(_ input: String, _ expected: String) {
        #expect(SessionInfo.sanitizedClaudeName(input) == expected)
    }

    /// A detached-HEAD worktree has no branch, so openWorktreeSession falls
    /// back to the literal name "session" (AppState.swift:489). Passing that
    /// labels every such worktree identically in the /resume picker -- worse
    /// than Claude's own generated name. Absence of a branch means absence of
    /// a name worth sending.
    @Test func detachedHeadWorktreeGetsNoNameFlag() {
        let session = SessionInfo(
            name: "session",
            workingDirectory: "/tmp/repo-detached",
            branchName: nil,
            worktreePath: "/tmp/repo-detached"
        )
        #expect(session.claudeNameFlag == nil)
    }

    @Test func branchBackedWorktreeStillGetsNameFlag() {
        let session = SessionInfo(
            name: "repo-feature",
            workingDirectory: "/tmp/repo-feature",
            branchName: "feature",
            worktreePath: "/tmp/repo-feature"
        )
        #expect(session.claudeNameFlag == "--name 'repo-feature'")
    }

    /// The name flag is appended to the command AFTER claudeCommand has built
    /// it, so for .appleContainer it lands OUTSIDE the `sh -c '...'` wrapper
    /// and reaches claude through the wrapper's "$@" -- Settings.swift's
    /// second escaping pass never touches it, and single-level quoting is
    /// correct. Exercise the real composition rather than re-applying an
    /// escaping pass the shipping code does not perform.
    @Test func appleContainerNameFlagSurvivesTheWrapperArgPath() throws {
        let hostile = "it's-$(whoami)-`id`;a|b&c"
        let session = worktreeSession(named: hostile)
        let sanitized = try #require(SessionInfo.sanitizedClaudeName(hostile))
        let flag = try #require(session.claudeNameFlag)

        let command = SandboxBackend.appleContainer.claudeCommand(
            claudeFlags: "--permission-mode auto",
            sbxFlags: "",
            containerImage: "canopy-claude",
            containerFlags: "",
            disableAltScreen: false
        ) + " \(flag)"

        // The flag must sit after the wrapper's closing quote, not inside it.
        let wrapperEnd = try #require(command.range(of: "' claude"))
        let flagStart = try #require(command.range(of: "--name"))
        #expect(flagStart.lowerBound > wrapperEnd.lowerBound)

        // Replay the production arg path: the host shell splits the appended
        // tokens into the wrapper's positional args ($0=claude, $1=--name,
        // $2=<name>), which `exec claude ... "$@"` forwards verbatim.
        let tail = String(command[wrapperEnd.upperBound...])
        #expect(try shellOutput(#"sh -c 'printf %s "$2"' claude\#(tail)"#) == sanitized)
    }

    @Test func plainSessionsGetNoNameFlag() {
        let session = SessionInfo(name: "feature/foo", workingDirectory: "/tmp/repo")
        #expect(session.claudeNameFlag == nil)
    }

    /// A branch-backed worktree session -- the only shape that gets a name
    /// flag. branchName must be set: see detachedHeadWorktreeGetsNoNameFlag.
    private func worktreeSession(named name: String) -> SessionInfo {
        SessionInfo(
            name: name,
            workingDirectory: "/tmp/repo-feature",
            branchName: "feature",
            worktreePath: "/tmp/repo-feature"
        )
    }

    private func shellOutput(_ command: String) throws -> String {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.standardOutput = standardOutput
        process.standardError = standardError

        try process.run()
        process.waitUntilExit()

        let error = String(
            data: standardError.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        #expect(process.terminationStatus == 0, "Shell failed: \(error)")
        return String(
            data: standardOutput.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
    }
}
