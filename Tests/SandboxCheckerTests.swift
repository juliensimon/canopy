import Testing
import Foundation
@testable import Canopy

@Suite("SandboxChecker")
struct SandboxCheckerTests {

    @Test func commandExistsFindsRealCommand() async {
        // `ls` is always available on macOS
        let exists = await SandboxChecker.commandExists("ls")
        #expect(exists == true)
    }

    @Test func commandExistsReturnsFalseForBogus() async {
        let exists = await SandboxChecker.commandExists("this-command-does-not-exist-xyz-123")
        #expect(exists == false)
    }

    @Test func statusEquatable() {
        #expect(SandboxChecker.Status.available == SandboxChecker.Status.available)
        #expect(SandboxChecker.Status.missingDocker == SandboxChecker.Status.missingDocker)
        #expect(SandboxChecker.Status.missingSbx == SandboxChecker.Status.missingSbx)
        #expect(SandboxChecker.Status.missingDocker != SandboxChecker.Status.missingSbx)
    }
}
