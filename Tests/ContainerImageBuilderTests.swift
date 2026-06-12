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

    @Test func buildCommandTargetsTagAndContext() {
        let command = ContainerImageBuilder.buildCommand(tag: "canopy-claude", contextDir: "/tmp/ctx")
        #expect(command == "container build --tag canopy-claude --file /tmp/ctx/Dockerfile /tmp/ctx")
    }

    @Test func imageExistsFalseForBogusImage() async {
        // Stable on any machine: false whether the container CLI is
        // missing or the image is simply not present.
        let exists = await ContainerImageBuilder.imageExists("definitely-not-an-image-xyz-123")
        #expect(exists == false)
    }
}
