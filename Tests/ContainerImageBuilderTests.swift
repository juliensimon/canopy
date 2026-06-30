import Testing
import Foundation
@testable import Canopy

@Suite("ContainerImageBuilder")
struct ContainerImageBuilderTests {

    @Test func dockerfileUsesNativeInstaller() {
        // The mounted host ~/.claude.json declares installMethod "native",
        // so the in-container claude looks for /root/.local/bin/claude.
        // An npm-only image triggers /doctor "missing or broken" warnings.
        #expect(ContainerImageBuilder.dockerfile.contains("https://claude.ai/install.sh"))
        #expect(ContainerImageBuilder.dockerfile.contains(#"PATH="/root/.local/bin:$PATH""#))
    }

    @Test func dockerfileIncludesAgentEssentials() {
        // git for commits, node base for npx-launched MCP servers.
        #expect(ContainerImageBuilder.dockerfile.contains("FROM node:"))
        #expect(ContainerImageBuilder.dockerfile.contains("git"))
    }

    @Test func buildCommandQuotesTagAndContext() {
        // The tag is user input interpolated into a login-shell command:
        // unquoted, a space or shell metacharacter would split arguments
        // or inject commands.
        let command = ContainerImageBuilder.buildCommand(tag: "canopy-claude", contextDir: "/tmp/my ctx")
        #expect(command == "container build --tag 'canopy-claude' --file '/tmp/my ctx/Dockerfile' '/tmp/my ctx'")
    }

    @Test func buildCommandEscapesEmbeddedSingleQuotes() {
        // A raw ' inside the tag would terminate the quoting and leak the
        // rest of the value as shell tokens.
        let command = ContainerImageBuilder.buildCommand(tag: "a'b", contextDir: "/tmp/ctx")
        #expect(command.contains(#"--tag 'a'\''b'"#))
    }

    @Test func buildCommandOmitsNoCacheByDefault() {
        // A normal build reuses cached layers -- fast, and correct for the
        // create-from-scratch case.
        let command = ContainerImageBuilder.buildCommand(tag: "canopy-claude", contextDir: "/tmp/ctx")
        #expect(!command.contains("--no-cache"))
    }

    @Test func buildCommandAddsNoCacheForUpdates() {
        // Updating MUST bypass the layer cache: otherwise the cached
        // `RUN curl install.sh` layer reinstalls the same pinned Claude
        // version and "Update" is a no-op.
        let command = ContainerImageBuilder.buildCommand(tag: "canopy-claude", contextDir: "/tmp/ctx", noCache: true)
        #expect(command.contains("container build --no-cache "))
    }

    @Test func dockerfileSetsRenderingEnvironment() {
        // Sessions inherit the image env when --env flags are absent (custom
        // commands, future paths). Bake sane terminal defaults into the image
        // too: UTF-8 locale and no self-updates into the ephemeral layer.
        #expect(ContainerImageBuilder.dockerfile.contains("DISABLE_AUTOUPDATER=1"))
    }

    @Test func runCapturingOutputSurvivesLargeOutput() async {
        // A 64KB pipe buffer blocks the child if nobody drains it while the
        // process runs -- the old implementation read only after termination,
        // so any real `container build` (apt-get logs alone exceed 64KB)
        // deadlocked with the Building… spinner stuck forever.
        let result = await ContainerImageBuilder.runCapturingOutput(
            "i=0; while [ $i -lt 5000 ]; do echo 0123456789012345678901234567890123456789; i=$((i+1)); done; echo TAIL-MARKER",
            timeoutSeconds: 60
        )
        #expect(result.exitCode == 0)
        #expect(result.output.count > 100_000)
        #expect(result.output.contains("TAIL-MARKER"))
    }

    @Test func runCapturingOutputTimesOut() async {
        let result = await ContainerImageBuilder.runCapturingOutput("sleep 60", timeoutSeconds: 2)
        #expect(result.exitCode != 0)
        #expect(result.output.contains("timed out"))
    }

    @Test func imageExistsFalseForBogusImage() async {
        // Stable on any machine: false whether the container CLI is
        // missing or the image is simply not present.
        let exists = await ContainerImageBuilder.imageExists("definitely-not-an-image-xyz-123")
        #expect(exists == false)
    }
}
