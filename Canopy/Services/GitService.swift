import Foundation

/// Wraps the git CLI for worktree, branch, and status operations.
///
/// We shell out to `git` rather than using a Swift git library because:
/// - No mature Swift git library handles worktrees well
/// - The git CLI is always available on macOS developer machines
/// - Output parsing is straightforward for the commands we need
///
/// All methods are async and throw on non-zero exit codes.
struct GitService {

    // MARK: - Worktree Operations

    /// Creates a new git worktree with an optional new branch.
    /// - Parameters:
    ///   - repoPath: The main repository path
    ///   - worktreePath: Where to create the worktree on disk
    ///   - branch: Branch name to check out (or create)
    ///   - baseBranch: Base branch to create from (e.g. "main"). If nil, uses current HEAD.
    ///   - createBranch: Whether to create a new branch (true) or check out existing (false)
    func createWorktree(
        repoPath: String,
        worktreePath: String,
        branch: String,
        baseBranch: String? = nil,
        createBranch: Bool = true
    ) async throws {
        var args = ["worktree", "add"]
        if createBranch {
            args += ["-b", branch, worktreePath]
            if let base = baseBranch {
                args.append(base)
            }
        } else {
            args += [worktreePath, branch]
        }
        try await run(args, in: repoPath)
    }

    /// Removes a worktree and its directory.
    func removeWorktree(repoPath: String, worktreePath: String) async throws {
        try await run(["worktree", "remove", "--force", worktreePath], in: repoPath)
    }

    /// Lists all worktrees for a repository.
    func listWorktrees(repoPath: String) async throws -> [WorktreeInfo] {
        let output = try await run(["worktree", "list", "--porcelain"], in: repoPath)
        return parseWorktreeList(output)
    }

    // MARK: - Branch Operations

    /// Lists local branches, returning them sorted with current branch first.
    /// Checks if a worktree has uncommitted changes or unmerged commits.
    func worktreeHasChanges(worktreePath: String) async -> Bool {
        // Check for uncommitted changes
        let hasUncommitted = (try? await run(["status", "--porcelain"], in: worktreePath))
            .map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false
        return hasUncommitted
    }

    /// Checks if a branch has commits not merged into the base branch.
    /// With no explicit base, detects it (main/master/develop/dev) -- the old
    /// hardcoded "main" default made the check silently pass (rev-list fails,
    /// count 0) on master-default repos, so users deleted unmerged work with
    /// no warning. Failures count as "has unmerged commits": warn-side.
    func branchHasUnmergedCommits(repoPath: String, branch: String, baseBranch explicitBase: String? = nil) async -> Bool {
        var resolvedBase = explicitBase
        if resolvedBase == nil {
            resolvedBase = await baseBranch(for: branch, repoPath: repoPath)
        }
        guard let base = resolvedBase else {
            return true
        }
        guard let count = (try? await run(["rev-list", "--count", "\(base)..\(branch)"], in: repoPath))
            .flatMap({ Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }) else {
            return true
        }
        return count > 0
    }

    /// Deletes a local branch.
    func deleteBranch(repoPath: String, branch: String) async throws {
        try await run(["branch", "-D", branch], in: repoPath)
    }

    func listBranches(repoPath: String) async throws -> [BranchInfo] {
        let output = try await run(
            ["branch", "--format=%(refname:short)\t%(HEAD)\t%(upstream:short)"],
            in: repoPath
        )
        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count >= 2 else { return nil }
            return BranchInfo(
                name: String(parts[0]),
                isCurrent: parts[1] == "*",
                upstream: parts.count > 2 && !parts[2].isEmpty ? String(parts[2]) : nil
            )
        }.sorted { $0.isCurrent && !$1.isCurrent }
    }

    /// Returns the current branch name.
    func currentBranch(repoPath: String) async throws -> String {
        let output = try await run(["rev-parse", "--abbrev-ref", "HEAD"], in: repoPath)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Finds the most likely base branch for a given branch.
    /// Uses merge-base to find the nearest ancestor among well-known base branches.
    func baseBranch(for branch: String, repoPath: String) async -> String? {
        let candidates = ["main", "master", "develop", "dev"]
        var bestBranch: String?
        var bestDistance = Int.max

        for candidate in candidates {
            // Check if candidate exists
            guard let _ = try? await run(["rev-parse", "--verify", candidate], in: repoPath) else {
                continue
            }
            // Count commits between merge-base and branch tip
            if let output = try? await run(
                ["rev-list", "--count", "\(candidate)..\(branch)"],
                in: repoPath
            ) {
                let distance = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? Int.max
                if distance < bestDistance {
                    bestDistance = distance
                    bestBranch = candidate
                }
            }
        }
        return bestBranch
    }

    // MARK: - Merge Operations

    /// Returns true if the working tree has uncommitted changes (staged or unstaged).
    func hasUncommittedChanges(repoPath: String) async throws -> Bool {
        let output = try await run(["status", "--porcelain"], in: repoPath)
        return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Returns the number of commits in `from` that are not in `to`.
    func commitCount(from source: String, to target: String, repoPath: String) async throws -> Int {
        let output = try await run(["rev-list", "--count", "\(target)..\(source)"], in: repoPath)
        return Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    /// Files that would textually conflict if `branchA` and `branchB` were
    /// merged — computed WITHOUT touching the working tree, via
    /// `git merge-tree --write-tree` (a 3-way merge against their merge-base).
    ///
    /// Returns `[]` for a clean merge, the conflicting paths on conflict, or
    /// `nil` if the command is unavailable/errored (git < 2.38, bad ref, …) so
    /// callers can fall back to the heuristic layer and flag textual-check as
    /// unavailable. Note: only catches *textual* conflicts — see SharedSurface.
    func mergeTreeConflicts(branchA: String, branchB: String, repoPath: String) async -> [String]? {
        guard let result = try? await runAllowingFailure(
            ["merge-tree", "--write-tree", "--name-only", "--no-messages", branchA, branchB],
            in: repoPath
        ) else {
            return nil
        }
        switch result.status {
        case 0:
            return []
        case 1:
            // On a real conflict, stdout is "<tree-oid>\n" then one conflicting
            // path per line. Git also exits 1 for a *bad ref*, but with empty
            // stdout (the error goes to stderr) — treat that as unavailable.
            let lines = result.stdout
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard !lines.isEmpty else { return nil }
            return Array(lines.dropFirst())
        default:
            return nil
        }
    }

    /// Files that `branch` changed relative to `base` (three-dot diff: changes
    /// introduced on the branch since their merge-base). Non-throwing; `[]` on
    /// error. Used by the heuristic (watch) layer to find shared-surface overlap.
    func changedFiles(base: String, branch: String, repoPath: String) async -> [String] {
        // Use runAllowingFailure (drains pipes before waiting) rather than run():
        // a large `diff --name-only` in a monorepo can exceed the pipe buffer and
        // deadlock run()'s read-after-wait ordering.
        guard let result = try? await runAllowingFailure(
            ["diff", "--name-only", "\(base)...\(branch)"], in: repoPath
        ), result.status == 0 else { return [] }
        return result.stdout
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Cross-worktree conflict pre-flight: how `branch` collides with each of
    /// its `siblings`, combining the textual (hard) and shared-surface (watch)
    /// layers. `base` is the common branch both diverged from (e.g. the merge
    /// target). Computed without touching the working tree.
    func collisionReport(
        for branch: String, against siblings: [String], base: String, repoPath: String
    ) async -> WorktreeCollisionReport {
        // Group this branch's surface-touching files by surface key once.
        let branchFiles = await changedFiles(base: base, branch: branch, repoPath: repoPath)
        var branchSurfaces: [String: [String]] = [:]
        for file in branchFiles {
            if let key = SharedSurface.surfaceKey(for: file) {
                branchSurfaces[key, default: []].append(file)
            }
        }

        var collisions: [BranchCollision] = []
        var textualAvailable = true

        for sibling in siblings {
            // Layer 1 — textual.
            let hardOpt = await mergeTreeConflicts(branchA: branch, branchB: sibling, repoPath: repoPath)
            if hardOpt == nil { textualAvailable = false }
            let hard = hardOpt ?? []

            // Layer 2 — shared-surface overlap by surface key, minus the hard set.
            let siblingFiles = await changedFiles(base: base, branch: sibling, repoPath: repoPath)
            let siblingKeys = Set(siblingFiles.compactMap { SharedSurface.surfaceKey(for: $0) })
            let watch = branchSurfaces
                .filter { siblingKeys.contains($0.key) }
                .flatMap { $0.value }
                .filter { !hard.contains($0) }
                .sorted()

            if !hard.isEmpty || !watch.isEmpty {
                collisions.append(BranchCollision(
                    branch: sibling, conflictingFiles: hard, sharedSurfaceFiles: watch
                ))
            }
        }

        return WorktreeCollisionReport(
            branch: branch, collisions: collisions, textualCheckAvailable: textualAvailable
        )
    }

    /// Collision report for each branch against all the others — for the
    /// ambient worktree-list badges. Branches with no siblings are omitted.
    func collisionReports(
        branches: [String], base: String, repoPath: String
    ) async -> [String: WorktreeCollisionReport] {
        // Fan out per-branch reports concurrently — each is independent and
        // read-only against the repo, so a project with several worktrees
        // doesn't pay an O(N²) sequential cost before its badges appear.
        await withTaskGroup(of: (String, WorktreeCollisionReport).self) { group in
            for branch in branches {
                let siblings = branches.filter { $0 != branch }
                guard !siblings.isEmpty else { continue }
                group.addTask {
                    (branch, await collisionReport(
                        for: branch, against: siblings, base: base, repoPath: repoPath
                    ))
                }
            }
            var result: [String: WorktreeCollisionReport] = [:]
            for await (branch, report) in group {
                result[branch] = report
            }
            return result
        }
    }

    /// Merges source branch into target branch.
    /// Checks out target in `repoPath`, attempts merge. On conflict, aborts and returns conflicting files.
    /// Note: this performs a `git checkout` on `repoPath` — callers must ensure no active work exists there.
    func mergeInto(target: String, source: String, repoPath: String) async throws -> MergeResult {
        // Record merge-base before merging (deterministic, unlike reflog)
        let baseOutput = try await run(["merge-base", target, source], in: repoPath)
        let mergeBase = baseOutput.trimmingCharacters(in: .whitespacesAndNewlines)

        // The merge requires checking out target in the user's main repo;
        // put their original branch back afterwards instead of silently
        // leaving the checkout switched.
        let originalBranch = (try? await currentBranch(repoPath: repoPath)) ?? ""
        func restoreOriginalBranch() async {
            if !originalBranch.isEmpty, originalBranch != "HEAD", originalBranch != target {
                _ = try? await run(["checkout", originalBranch], in: repoPath)
            }
        }

        // Checkout target branch
        try await run(["checkout", target], in: repoPath)

        // Attempt merge
        do {
            try await run(["merge", source], in: repoPath)
        } catch {
            // Check if it's a conflict
            let conflictOutput = try await run(["diff", "--name-only", "--diff-filter=U"], in: repoPath)
            let files = conflictOutput
                .split(separator: "\n")
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            if !files.isEmpty {
                _ = try? await run(["merge", "--abort"], in: repoPath)
                await restoreOriginalBranch()
                return .conflict(files: files)
            }
            // Not a conflict — re-throw
            await restoreOriginalBranch()
            throw error
        }

        // Count commits that were merged using merge-base
        let countOutput = try await run(["rev-list", "--count", "\(mergeBase)..\(target)"], in: repoPath)
        let count = Int(countOutput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        await restoreOriginalBranch()
        return .success(commitCount: count)
    }

    /// Deletes a local branch. Uses -d (safe delete) — only works if branch is fully merged.
    func deleteBranch(name: String, repoPath: String) async throws {
        try await run(["branch", "-d", name], in: repoPath)
    }

    // MARK: - Status

    /// Returns true if the path is inside a git repository.
    func isGitRepo(path: String) async -> Bool {
        do {
            try await run(["rev-parse", "--is-inside-work-tree"], in: path)
            return true
        } catch {
            return false
        }
    }

    /// Returns the root directory of the git repository.
    func repoRoot(path: String) async throws -> String {
        let output = try await run(["rev-parse", "--show-toplevel"], in: path)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns the common git directory (stable across worktrees of the same repo).
    func gitCommonDir(path: String) async throws -> String {
        let output = try await run(["rev-parse", "--git-common-dir"], in: path)
        let raw = output.trimmingCharacters(in: .whitespacesAndNewlines)
        // --git-common-dir may return a relative path; resolve it
        if raw.hasPrefix("/") { return raw }
        return (path as NSString).appendingPathComponent(raw)
    }

    // MARK: - Diff & Push Status

    /// Returns a summary of uncommitted changes (staged + unstaged) vs HEAD.
    /// Returns nil if the directory is not a git repo or has no commits yet.
    func diffStat(repoPath: String) async -> GitDiffStat? {
        guard let shortstat = try? await run(["diff", "--shortstat", "HEAD"], in: repoPath) else {
            return nil
        }
        let nameOnly = (try? await run(["diff", "--name-only", "HEAD"], in: repoPath)) ?? ""
        let files = nameOnly
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let trimmed = shortstat.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return GitDiffStat(filesChanged: 0, insertions: 0, deletions: 0, changedFiles: [])
        }

        return GitDiffStat.parse(shortstat: trimmed, changedFiles: files)
    }

    /// Returns open PRs for the repo.
    /// By default, scopes to the current branch (`branch = "HEAD"`).
    /// Pass `nil` to return open PRs across the entire repository, or pass a branch name
    /// to scope to that branch only.
    /// Returns empty array on any error (gh not installed, not a GitHub repo, no auth).
    func openPRs(repoPath: String, branch: String? = "HEAD") async -> [GitPRInfo] {
        var args = ["pr", "list", "--json", "number,title,url,isDraft,headRefName", "--state", "open", "--limit", "10"]
        if let branch = branch {
            if branch == "HEAD" {
                guard let current = try? await currentBranch(repoPath: repoPath) else { return [] }
                // Detached HEAD returns literal "HEAD" — skip filtering
                if current != "HEAD" {
                    args += ["--head", current]
                }
            } else {
                args += ["--head", branch]
            }
        }
        guard let output = try? await runGH(args, in: repoPath) else { return [] }
        return GitPRInfo.parseGHJSON(output)
    }

    /// Returns how many commits HEAD is ahead of its upstream or base branch.
    /// Tries upstream first (pushed branches). Falls back to base branch detection
    /// (main/master/develop) for unpushed feature branches and worktrees.
    func commitsAhead(repoPath: String) async -> Int? {
        if let output = try? await run(
            ["rev-list", "--count", "@{upstream}..HEAD"], in: repoPath
        ), let count = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return count
        }
        guard let branch = try? await currentBranch(repoPath: repoPath) else { return nil }
        guard let base = await baseBranch(for: branch, repoPath: repoPath) else { return nil }
        if branch == base { return nil }
        return try? await commitCount(from: branch, to: base, repoPath: repoPath)
    }

    // MARK: - File Operations for Worktree Setup

    /// Copies files from the main repo to a worktree.
    /// Supports glob-like patterns (just direct file paths for now).
    static func copyFiles(from repoPath: String, to worktreePath: String, paths: [String]) throws {
        let fm = FileManager.default
        for relativePath in paths {
            let source = (repoPath as NSString).appendingPathComponent(relativePath)
            let dest = (worktreePath as NSString).appendingPathComponent(relativePath)

            guard fm.fileExists(atPath: source) else { continue }

            // Create parent directory if needed
            let destDir = (dest as NSString).deletingLastPathComponent
            if !fm.fileExists(atPath: destDir) {
                try fm.createDirectory(atPath: destDir, withIntermediateDirectories: true)
            }

            // Remove existing file at destination (worktree might have a placeholder)
            if fm.fileExists(atPath: dest) {
                try fm.removeItem(atPath: dest)
            }

            try fm.copyItem(atPath: source, toPath: dest)
        }
    }

    /// Creates symlinks in the worktree pointing to directories in the main repo.
    /// Used for heavy directories like node_modules that shouldn't be duplicated.
    static func createSymlinks(from repoPath: String, to worktreePath: String, paths: [String]) throws {
        let fm = FileManager.default
        for relativePath in paths {
            let source = (repoPath as NSString).appendingPathComponent(relativePath)
            let dest = (worktreePath as NSString).appendingPathComponent(relativePath)

            guard fm.fileExists(atPath: source) else { continue }

            // Remove existing item at destination
            if fm.fileExists(atPath: dest) || (try? fm.destinationOfSymbolicLink(atPath: dest)) != nil {
                try fm.removeItem(atPath: dest)
            }

            try fm.createSymbolicLink(atPath: dest, withDestinationPath: source)
        }
    }

    /// Runs a shell command in the worktree directory.
    static func runSetupCommand(_ command: String, in directory: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", command]
        process.currentDirectoryURL = URL(fileURLWithPath: directory)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            throw GitError.commandFailed("Setup command failed: \(command)\n\(output)")
        }
    }

    // MARK: - Private

    /// Runs a git command and returns stdout.
    @discardableResult
    private func run(_ args: [String], in directory: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: directory)

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8) ?? "Unknown error"
            throw GitError.commandFailed("git \(args.joined(separator: " ")): \(errStr)")
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Like `run`, but returns the exit status and stdout instead of throwing on
    /// a non-zero exit. Needed for commands that signal a meaningful result via
    /// exit code — e.g. `git merge-tree` returns 1 with the conflict list on
    /// stdout, which `run` would discard while throwing.
    private func runAllowingFailure(_ args: [String], in directory: String) async throws -> (status: Int32, stdout: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: directory)

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        _ = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return (process.terminationStatus, String(data: outData, encoding: .utf8) ?? "")
    }

    /// Resolves the `gh` CLI path, checking common Homebrew and system locations.
    private static let ghPath: String? = {
        let candidates = [
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
            "/usr/bin/gh"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    /// Runs a `gh` CLI command and returns stdout. Throws on non-zero exit.
    @discardableResult
    private func runGH(_ args: [String], in directory: String) async throws -> String {
        guard let ghPath = GitService.ghPath else {
            throw GitError.commandFailed("gh CLI not found")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ghPath)
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: directory)

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8) ?? "Unknown error"
            throw GitError.commandFailed("gh \(args.joined(separator: " ")): \(errStr)")
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Parses `git worktree list --porcelain` output into structured data.
    private func parseWorktreeList(_ output: String) -> [WorktreeInfo] {
        var worktrees: [WorktreeInfo] = []
        var currentPath: String?
        var currentBranch: String?
        var isBare = false

        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let str = String(line)
            if str.hasPrefix("worktree ") {
                // Save previous worktree if any
                if let path = currentPath {
                    worktrees.append(WorktreeInfo(path: path, branch: currentBranch, isBare: isBare))
                }
                let rawPath = String(str.dropFirst("worktree ".count))
                currentPath = (rawPath as NSString).expandingTildeInPath
                currentBranch = nil
                isBare = false
            } else if str.hasPrefix("branch ") {
                let ref = String(str.dropFirst("branch ".count))
                // Strip refs/heads/ prefix
                currentBranch = ref.hasPrefix("refs/heads/")
                    ? String(ref.dropFirst("refs/heads/".count))
                    : ref
            } else if str == "bare" {
                isBare = true
            }
        }

        // Don't forget the last entry
        if let path = currentPath {
            worktrees.append(WorktreeInfo(path: path, branch: currentBranch, isBare: isBare))
        }

        return worktrees
    }
}

// MARK: - Types

struct WorktreeInfo: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let branch: String?
    let isBare: Bool
    var baseBranch: String?
}

struct BranchInfo: Identifiable {
    var id: String { name }
    let name: String
    let isCurrent: Bool
    let upstream: String?
}

enum MergeResult {
    case success(commitCount: Int)
    case conflict(files: [String])
}

/// Classifies "high-stakes shared surfaces" — files that commonly cause
/// *semantic* collisions across parallel worktrees even when they merge
/// textually clean (package manifests, lockfiles, migrations, generated types,
/// env examples). Drives the heuristic "watch" layer of the cross-worktree
/// conflict pre-flight, which catches what `merge-tree` structurally cannot.
enum SharedSurface {
    /// Default glob patterns, matched against the repo-relative path and the
    /// basename. (Per-project overrides are a planned follow-up.)
    static let patterns: [String] = [
        // package manifests
        "package.json", "Cargo.toml", "go.mod", "pyproject.toml", "Gemfile",
        "Package.swift", "pom.xml", "build.gradle", "build.gradle.kts", "*.csproj",
        // lockfiles
        "*.lock", "package-lock.json", "yarn.lock", "pnpm-lock.yaml", "bun.lockb",
        "Gemfile.lock", "Cargo.lock", "poetry.lock", "Package.resolved",
        // migrations
        "**/migrations/**", "**/migrate/**", "db/migrate/**",
        // generated types
        "**/generated/**", "*.generated.*", "schema.d.ts",
        // env examples
        ".env.example", ".env.*.example",
    ]

    static func matches(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        return patterns.contains { glob($0, matches: path) || glob($0, matches: name) }
    }

    /// A grouping key so two branches that touch the *same surface* collide even
    /// when they touch *different files* in it. Directory surfaces (migrations,
    /// generated, …) group by the directory marker; file surfaces (manifests,
    /// lockfiles) group by basename. Returns nil for non-surface paths.
    static func surfaceKey(for path: String) -> String? {
        guard matches(path) else { return nil }
        let lower = path.lowercased()
        for marker in ["migrations", "migrate", "generated"] {
            if lower.hasPrefix("\(marker)/") || lower.contains("/\(marker)/") {
                return marker
            }
        }
        return (path as NSString).lastPathComponent
    }

    /// fnmatch-based glob. `**` is normalised to `*`; with no FNM_PATHNAME flag
    /// `*` already spans `/`, so `*migrations/*` matches `db/migrations/x.sql`.
    private static func glob(_ pattern: String, matches text: String) -> Bool {
        let p = pattern
            .replacingOccurrences(of: "**/", with: "*")
            .replacingOccurrences(of: "**", with: "*")
        return fnmatch(p, text, 0) == 0
    }
}

/// How one sibling branch collides with the branch being evaluated.
struct BranchCollision: Identifiable, Hashable {
    var id: String { branch }
    let branch: String
    /// Files that textually conflict (merge-tree) — a *hard* collision.
    let conflictingFiles: [String]
    /// Files on a shared high-stakes surface that merge textually clean — a
    /// *watch* (advisory) collision the textual layer can't see.
    let sharedSurfaceFiles: [String]
}

/// Cross-worktree pre-flight result for one branch vs its sibling worktrees.
struct WorktreeCollisionReport {
    let branch: String
    let collisions: [BranchCollision]
    /// False if the textual (merge-tree) check couldn't run (e.g. old git);
    /// the heuristic layer still populates and the UI says so.
    let textualCheckAvailable: Bool

    var isEmpty: Bool { collisions.isEmpty }
    var hardCount: Int { collisions.filter { !$0.conflictingFiles.isEmpty }.count }
    var watchCount: Int {
        collisions.filter { $0.conflictingFiles.isEmpty && !$0.sharedSurfaceFiles.isEmpty }.count
    }
}

struct GitStatusInfo {
    let diffStat: GitDiffStat?
    let commitsAhead: Int?
    let openPRs: [GitPRInfo]
    let changedFiles: [String]
}

struct GitPRInfo: Identifiable {
    let number: Int
    let title: String
    let url: String
    let isDraft: Bool
    let headBranch: String
    var id: Int { number }

    /// Parses JSON output from `gh pr list --json number,title,url,isDraft,headRefName`.
    static func parseGHJSON(_ json: String) -> [GitPRInfo] {
        guard !json.isEmpty,
              let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return array.compactMap { dict in
            guard let number = dict["number"] as? Int,
                  let title = dict["title"] as? String,
                  let url = dict["url"] as? String else {
                return nil
            }
            return GitPRInfo(
                number: number, title: title, url: url,
                isDraft: dict["isDraft"] as? Bool ?? false,
                headBranch: dict["headRefName"] as? String ?? ""
            )
        }
    }
}

struct GitDiffStat {
    let filesChanged: Int
    let insertions: Int
    let deletions: Int
    let changedFiles: [String]
    var isClean: Bool { filesChanged == 0 && insertions == 0 && deletions == 0 }

    /// Parses `git diff --shortstat` output.
    static func parse(shortstat: String, changedFiles: [String]) -> GitDiffStat {
        var files = 0, ins = 0, del = 0
        let components = shortstat.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        for component in components {
            if component.contains("file") {
                files = Int(component.split(separator: " ").first ?? "") ?? 0
            } else if component.contains("insertion") {
                ins = Int(component.split(separator: " ").first ?? "") ?? 0
            } else if component.contains("deletion") {
                del = Int(component.split(separator: " ").first ?? "") ?? 0
            }
        }
        return GitDiffStat(filesChanged: files, insertions: ins, deletions: del, changedFiles: changedFiles)
    }
}

enum GitError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let msg): return msg
        }
    }
}
