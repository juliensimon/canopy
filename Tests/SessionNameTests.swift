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

    @Test func appleContainerNestedQuotingRoundTrips() throws {
        let session = worktreeSession(named: "it's-$(whoami)-`id`;a|b&c")
        let sanitized = try #require(SessionInfo.sanitizedClaudeName(session.name))
        let flag = try #require(session.claudeNameFlag)
        let token = try #require(flag.split(separator: " ", maxSplits: 1).last)

        // Apple container embeds claude flags in a single-quoted `sh -c`
        // script, so exercise the second escaping pass from Settings.swift.
        let escapedToken = token.replacingOccurrences(of: "'", with: #"'\''"#)
        #expect(try shellOutput("sh -c 'printf %s \(escapedToken)'") == sanitized)
    }

    @Test func plainSessionsGetNoNameFlag() {
        let session = SessionInfo(name: "feature/foo", workingDirectory: "/tmp/repo")
        #expect(session.claudeNameFlag == nil)
    }

    private func worktreeSession(named name: String) -> SessionInfo {
        SessionInfo(
            name: name,
            workingDirectory: "/tmp/repo-feature",
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
