import Testing
@testable import Canopy

/// The host Claude Code CLI version shown in Settings (#43). Behavior changes
/// are keyed to CLI versions (e.g. the ≥ 2.1.132 alternate-screen renderer),
/// so surfacing the version turns "terminal behaves differently" into a glance.
@Suite("ClaudeVersionChecker")
struct ClaudeVersionCheckerTests {

    @Test func parsesStandardOutput() {
        #expect(ClaudeVersionChecker.parse("2.1.206 (Claude Code)") == "2.1.206")
    }

    @Test func parsesBareVersion() {
        #expect(ClaudeVersionChecker.parse("2.1.206") == "2.1.206")
    }

    @Test func trimsWhitespaceAndNewline() {
        #expect(ClaudeVersionChecker.parse("  2.1.206 (Claude Code)\n") == "2.1.206")
    }

    @Test func rejectsEmptyOutput() {
        #expect(ClaudeVersionChecker.parse("") == nil)
        #expect(ClaudeVersionChecker.parse("   \n") == nil)
    }

    @Test func rejectsNonVersionOutput() {
        // e.g. a shell error like "command not found: claude"
        #expect(ClaudeVersionChecker.parse("zsh: command not found: claude") == nil)
    }

    /// Exercises the real CLI path end to end (repo convention, like
    /// `imageExistsFalseForBogusImage`): on machines without claude the
    /// login shell exits non-zero → nil; where it exists, the result must
    /// be a clean semver token (parse is idempotent on its own output).
    @Test func hostVersionReturnsNilOrSemver() async {
        let version = await ClaudeVersionChecker.hostVersion()
        if let version {
            #expect(ClaudeVersionChecker.parse(version) == version)
        }
    }
}
