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
                currentPath = String(str.dropFirst("worktree ".count))
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

struct WorktreeInfo: Identifiable {
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

enum GitError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let msg): return msg
        }
    }
}
