import Testing
import Foundation
@testable import Canopy

/// Cross-worktree conflict pre-flight engine.
///
/// Two layers:
/// - hard (textual): `git merge-tree --write-tree` between two branch tips;
/// - watch (heuristic): files both branches touch on a high-stakes shared
///   surface, even when they merge textually clean.
///
/// All tests shell out to real `git` against real worktrees — no mocking.
@Suite("Worktree Collision")
struct WorktreeCollisionTests {
    private let git = GitService()
    private let fm = FileManager.default

    // MARK: - Layer 1: textual (merge-tree)

    @Test func mergeTreeDetectsTextualConflict() async throws {
        try await withWorktrees(["feat/a", "feat/b"]) { repo, wt in
            // Both branches change the same line of an existing file → conflict.
            try commit("from A\n", to: "file.txt", in: wt["feat/a"]!)
            try commit("from B\n", to: "file.txt", in: wt["feat/b"]!)

            let conflicts = await git.mergeTreeConflicts(
                branchA: "feat/a", branchB: "feat/b", repoPath: repo
            )
            #expect(conflicts == ["file.txt"])
        }
    }

    @Test func mergeTreeReportsNoConflictForDisjointChanges() async throws {
        try await withWorktrees(["feat/a", "feat/b"]) { repo, wt in
            try commit("a only\n", to: "a.txt", in: wt["feat/a"]!)
            try commit("b only\n", to: "b.txt", in: wt["feat/b"]!)

            let conflicts = await git.mergeTreeConflicts(
                branchA: "feat/a", branchB: "feat/b", repoPath: repo
            )
            #expect(conflicts == [])
        }
    }

    /// Documents the gap that Layer 2 exists to close: two branches that ADD
    /// migrations with the same sequence number but different filenames merge
    /// textually clean, so merge-tree reports nothing.
    @Test func mergeTreeMissesSameSequenceMigrations() async throws {
        try await withWorktrees(["feat/a", "feat/b"]) { repo, wt in
            try commit("-- a\n", to: "db/migrations/0007_users.sql", in: wt["feat/a"]!)
            try commit("-- b\n", to: "db/migrations/0007_orders.sql", in: wt["feat/b"]!)

            let conflicts = await git.mergeTreeConflicts(
                branchA: "feat/a", branchB: "feat/b", repoPath: repo
            )
            #expect(conflicts == [])
        }
    }

    // MARK: - Layer 2: shared-surface heuristic

    @Test func changedFilesListsBranchEditsSinceBase() async throws {
        try await withWorktrees(["feat/a"]) { repo, wt in
            try commit("x\n", to: "src/app.ts", in: wt["feat/a"]!)
            try commit("y\n", to: "package.json", in: wt["feat/a"]!)

            let files = await git.changedFiles(base: "main", branch: "feat/a", repoPath: repo)
            #expect(Set(files) == ["src/app.ts", "package.json"])
        }
    }

    @Test func sharedSurfaceMatchesHighStakesPaths() {
        // Manifests, lockfiles, migrations, generated types, env examples.
        #expect(SharedSurface.matches("package.json"))
        #expect(SharedSurface.matches("apps/web/package.json"))
        #expect(SharedSurface.matches("bun.lockb"))
        #expect(SharedSurface.matches("db/migrations/0007_users.sql"))
        #expect(SharedSurface.matches("src/generated/types.ts"))
        #expect(SharedSurface.matches(".env.example"))
        // Ordinary source and docs are not shared surfaces.
        #expect(!SharedSurface.matches("README.md"))
        #expect(!SharedSurface.matches("src/app.ts"))
        // Directory markers match whole components only — no substring false
        // positives on lookalike directory names.
        #expect(!SharedSurface.matches("src/notmigrations/seed.sql"))
        #expect(!SharedSurface.matches("regenerated/config.txt"))
    }

    /// `changedFiles` uses a three-dot diff (`base...branch`) so base-side edits
    /// made AFTER the fork are excluded. A regression to two-dot would leak the
    /// base's later changes into the shared-surface set and raise false-positive
    /// "shared surface" alarms over a destructive merge. The original fixture
    /// never advanced `main` after forking, so this case was invisible.
    @Test func changedFilesExcludesBaseSideEditsMadeAfterFork() async throws {
        try await withWorktrees(["feat/a"]) { repo, wt in
            try commit("a\n", to: "go.mod", in: wt["feat/a"]!)
            // main advances AFTER the fork with its OWN, different surface edit.
            try commit("main\n", to: "Cargo.lock", in: repo)

            let files = await git.changedFiles(base: "main", branch: "feat/a", repoPath: repo)
            // Three-dot: only feat/a's change. Two-dot would also include
            // main's Cargo.lock, which this asserts against.
            #expect(files == ["go.mod"])
        }
    }

    /// The grouping *key* (not just `matches`) is what closes the
    /// same-sequence-migration gap: two DIFFERENT files on the same surface must
    /// produce the SAME key so the branches collide. This pins the key directly.
    @Test func surfaceKeyGroupsSameSurfaceAcrossDifferentFiles() {
        // Same directory surface, different files → same key.
        #expect(SharedSurface.surfaceKey(for: "db/migrations/0007_users.sql")
                == SharedSurface.surfaceKey(for: "db/migrations/0007_orders.sql"))
        // Same file surface in different directories → same key (basename).
        #expect(SharedSurface.surfaceKey(for: "apps/web/package.json")
                == SharedSurface.surfaceKey(for: "services/api/package.json"))
        // Different surfaces → different keys.
        #expect(SharedSurface.surfaceKey(for: "package.json")
                != SharedSurface.surfaceKey(for: "go.mod"))
        // Non-surface paths have no key.
        #expect(SharedSurface.surfaceKey(for: "src/app.ts") == nil)
    }

    /// macOS's default filesystem is case-insensitive, so surface matching must
    /// be too — otherwise a `Package.json` / `GEMFILE` silently escapes the
    /// watch layer (a false negative that defeats the feature's purpose).
    @Test func sharedSurfaceMatchingIsCaseInsensitive() {
        #expect(SharedSurface.matches("apps/web/PACKAGE.JSON"))
        #expect(SharedSurface.matches("GEMFILE"))
        #expect(SharedSurface.surfaceKey(for: "Package.JSON")
                == SharedSurface.surfaceKey(for: "package.json"))
    }

    /// High-collision manifests/checksums that were missing from the watch list.
    @Test func sharedSurfaceCoversCommonEcosystemManifests() {
        #expect(SharedSurface.matches("go.sum"))
        #expect(SharedSurface.matches("requirements.txt"))
        #expect(SharedSurface.matches("Pipfile"))
        #expect(SharedSurface.matches("composer.json"))
        #expect(SharedSurface.matches("ios/Podfile"))
    }

    // MARK: - collisionReport (both layers combined)

    @Test func collisionReportSeparatesHardAndWatch() async throws {
        try await withWorktrees(["feat/a", "feat/b"]) { repo, wt in
            // package.json: both edit the same line → HARD textual conflict.
            try commit("{ \"v\": \"a\" }\n", to: "package.json", in: wt["feat/a"]!)
            try commit("{ \"v\": \"b\" }\n", to: "package.json", in: wt["feat/b"]!)
            // Same-sequence migrations, different filenames → WATCH (merges clean,
            // and the two branches touch *different* files in the same surface).
            try commit("-- a\n", to: "db/migrations/0007_users.sql", in: wt["feat/a"]!)
            try commit("-- b\n", to: "db/migrations/0007_orders.sql", in: wt["feat/b"]!)

            let report = await git.collisionReport(
                for: "feat/a", against: ["feat/b"], base: "main", repoPath: repo
            )
            #expect(report.textualCheckAvailable)
            let c = try #require(report.collisions.first { $0.branch == "feat/b" })
            // package.json is the hard conflict; the migration is watch-only and
            // package.json is NOT duplicated into watch.
            #expect(c.conflictingFiles == ["package.json"])
            #expect(c.sharedSurfaceFiles == ["db/migrations/0007_users.sql"])
        }
    }

    @Test func collisionReportEmptyWhenBranchesAreDisjoint() async throws {
        try await withWorktrees(["feat/a", "feat/b"]) { repo, wt in
            try commit("a\n", to: "src/a.ts", in: wt["feat/a"]!)
            try commit("b\n", to: "src/b.ts", in: wt["feat/b"]!)
            let report = await git.collisionReport(
                for: "feat/a", against: ["feat/b"], base: "main", repoPath: repo
            )
            #expect(report.isEmpty)
        }
    }

    @Test func collisionReportFlagsTextualCheckUnavailableOnError() async throws {
        try await withWorktrees(["feat/a"]) { repo, wt in
            try commit("a\n", to: "package.json", in: wt["feat/a"]!)
            // A bad sibling ref makes merge-tree error — same signal path as an
            // unsupported git: the textual layer reports unavailable.
            let report = await git.collisionReport(
                for: "feat/a", against: ["feat/does-not-exist"], base: "main", repoPath: repo
            )
            #expect(!report.textualCheckAvailable)
        }
    }

    // MARK: - collisionReports (per-branch, for the worktree list)

    @Test func collisionReportsCoversEachBranchAgainstTheOthers() async throws {
        try await withWorktrees(["feat/a", "feat/b", "feat/c"]) { repo, wt in
            // a and b collide on package.json; c is disjoint.
            try commit("{ \"v\": \"a\" }\n", to: "package.json", in: wt["feat/a"]!)
            try commit("{ \"v\": \"b\" }\n", to: "package.json", in: wt["feat/b"]!)
            try commit("c\n", to: "src/c.ts", in: wt["feat/c"]!)

            let reports = await git.collisionReports(
                branches: ["feat/a", "feat/b", "feat/c"], base: "main", repoPath: repo
            )
            #expect(reports["feat/a"]?.collisions.contains { $0.branch == "feat/b" } == true)
            #expect(reports["feat/b"]?.collisions.contains { $0.branch == "feat/a" } == true)
            #expect(reports["feat/c"]?.isEmpty == true)
        }
    }

    // MARK: - Fixture

    /// Creates a repo on `main` with an initial commit plus one worktree per
    /// branch (each off `main`), runs `body`, and cleans everything up.
    private func withWorktrees(
        _ branches: [String],
        _ body: (_ repo: String, _ worktrees: [String: String]) async throws -> Void
    ) async throws {
        let repo = NSTemporaryDirectory() + "canopy-collision-\(UUID().uuidString)"
        try fm.createDirectory(atPath: repo, withIntermediateDirectories: true)
        var worktreeDirs: [String] = []
        defer {
            try? fm.removeItem(atPath: repo)
            for dir in worktreeDirs { try? fm.removeItem(atPath: dir) }
        }

        try shell("git init -b main && git config user.email 'test@test.com' && git config user.name 'Test'", in: repo)
        try "base\n".write(toFile: "\(repo)/file.txt", atomically: true, encoding: .utf8)
        try shell("git add -A && git commit -m 'initial'", in: repo)

        var map: [String: String] = [:]
        for branch in branches {
            let wt = "\(repo)-wt-\(branch.replacingOccurrences(of: "/", with: "-"))"
            worktreeDirs.append(wt)
            try await git.createWorktree(
                repoPath: repo, worktreePath: wt, branch: branch,
                baseBranch: "main", createBranch: true
            )
            map[branch] = wt
        }
        try await body(repo, map)
    }

    private func commit(_ contents: String, to file: String, in dir: String) throws {
        let full = (dir as NSString).appendingPathComponent(file)
        try fm.createDirectory(
            atPath: (full as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        try contents.write(toFile: full, atomically: true, encoding: .utf8)
        try shell("git add -A && git commit -m 'edit'", in: dir)
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
