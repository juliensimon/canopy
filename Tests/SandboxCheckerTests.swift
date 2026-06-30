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
        #expect(SandboxChecker.Status.missingContainer != SandboxChecker.Status.containerSystemStopped)
        #expect(SandboxChecker.Status.missingKernel != SandboxChecker.Status.containerSystemStopped)
    }

    @Test func checkOffNeedsNoTools() async {
        // No backend means nothing to validate -- must not probe for CLIs.
        let status = await SandboxChecker.check(backend: .off)
        #expect(status == .available)
    }

    @Test func legacyCheckMatchesDockerSbxBackend() async {
        // The original check() validated docker + sbx; the backend-aware
        // overload must report the same thing for .dockerSbx.
        let legacy = await SandboxChecker.check()
        let backend = await SandboxChecker.check(backend: .dockerSbx)
        #expect(legacy == backend)
    }
}

@Suite("SandboxBackendUI launch preflight")
struct SandboxBackendUILaunchTests {

    @Test func availableLaunchesTheCommandUnchanged() {
        // A ready backend must run Claude exactly as built -- no wrapping.
        let cmd = "container run --rm img claude --resume abc123"
        #expect(SandboxBackendUI.launchCommand(for: .available, command: cmd) == cmd)
    }

    @Test func stoppedDaemonSurfacesTheFixNotTheCommand() {
        // The whole point: a stopped apiserver must show the actionable
        // `container system start` hint, never fire the command that would
        // print the cryptic "XPC connection error" instead.
        let sent = SandboxBackendUI.launchCommand(for: .containerSystemStopped, command: "claude")
        #expect(sent != "claude")
        #expect(sent.hasPrefix("echo "))
        #expect(sent.contains("container system start"))
    }

    @Test func unavailableNeverLeaksTheLaunchCommand() {
        // For any non-available status the launch command must not run --
        // otherwise the preflight is decorative.
        for status: SandboxChecker.Status in [.missingDocker, .missingSbx, .missingContainer, .missingKernel] {
            let sent = SandboxBackendUI.launchCommand(for: status, command: "claude --dangerously-skip")
            #expect(!sent.contains("claude --dangerously-skip"))
            #expect(sent.hasPrefix("echo "))
        }
    }
}
