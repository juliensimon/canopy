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

    @Test func dockerfileSetsRenderingEnvironment() {
        // Sessions inherit the image env when --env flags are absent (custom
        // commands, future paths). Bake sane terminal defaults into the image
        // too: UTF-8 locale and no self-updates into the ephemeral layer.
        #expect(ContainerImageBuilder.dockerfile.contains("DISABLE_AUTOUPDATER=1"))
    }

    @Test func imageExistsFalseForBogusImage() async {
        // Stable on any machine: false whether the container CLI is
        // missing or the image is simply not present.
        let exists = await ContainerImageBuilder.imageExists("definitely-not-an-image-xyz-123")
        #expect(exists == false)
    }
}
