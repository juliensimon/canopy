import Testing
import Foundation
@testable import Canopy

/// Merge & Finish runs `git checkout` / `git merge` on the HOST in the main
/// repo. A sandboxed agent can write that repo's `.git/hooks` (a worktree's
/// `.git` points into the main repo, which is mounted writable), so a planted
/// `post-checkout` / `post-merge` hook would execute on the host the moment the
/// user clicks Merge & Finish — without ever running git themselves. Canopy must
/// run the merge operations with repo-local hooks disabled.
@Suite("Merge Hook Isolation")
struct MergeHookIsolationTests {
    private let git = GitService()
    private let fm = FileManager.default

    @Test func mergeDoesNotFireRepoLocalHooks() async throws {
        let repo = NSTemporaryDirectory() + "canopy-hook-\(UUID().uuidString)"
        try fm.createDirectory(atPath: repo, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: repo) }

        try shell("git init -q -b main && git config user.email t@t.com && git config user.name T", in: repo)
        try "base\n".write(toFile: "\(repo)/file.txt", atomically: true, encoding: .utf8)
        try shell("git add -A && git commit -q -m initial", in: repo)
        // feat/x and main diverge with disjoint changes → a real (non-fast-forward)
        // merge that creates a merge commit and runs post-merge.
        try shell("git checkout -q -b feat/x", in: repo)
        try "feat\n".write(toFile: "\(repo)/feat.txt", atomically: true, encoding: .utf8)
        try shell("git add -A && git commit -q -m feat", in: repo)
        try shell("git checkout -q main", in: repo)
        try "main\n".write(toFile: "\(repo)/main.txt", atomically: true, encoding: .utf8)
        try shell("git add -A && git commit -q -m main", in: repo)
        // Leave the repo on feat/x so mergeInto's checkout of main is a real
        // branch switch (fires post-checkout on buggy code).
        try shell("git checkout -q feat/x", in: repo)

        // Plant executable hooks that record if they ever run on the host.
        let sentinel = "\(repo)/HOOK_FIRED"
        let hooksDir = "\(repo)/.git/hooks"
        try fm.createDirectory(atPath: hooksDir, withIntermediateDirectories: true)
        for hook in ["post-checkout", "post-merge"] {
            let path = "\(hooksDir)/\(hook)"
            try "#!/bin/sh\ntouch '\(sentinel)'\n".write(toFile: path, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        }

        let result = try await git.mergeInto(target: "main", source: "feat/x", repoPath: repo)
        if case .conflict = result {
            Issue.record("expected a clean merge, got a conflict")
        }

        #expect(
            !fm.fileExists(atPath: sentinel),
            "a repo-local git hook fired during a Canopy-initiated host merge"
        )
    }

    @discardableResult
    private func shell(_ command: String, in dir: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = URL(fileURLWithPath: dir)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus != 0 {
            throw NSError(domain: "test", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? ""])
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
