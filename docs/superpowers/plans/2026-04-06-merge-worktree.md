# Merge & Finish Worktree Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Merge & Finish" action that merges a worktree's branch into its base branch, then optionally cleans up the worktree and branch.

**Architecture:** Extend `GitService` with merge/status methods, create a new `MergeWorktreeSheet` view with a two-phase flow (confirm merge → cleanup), and wire it into both `Sidebar` context menu and `ProjectDetailView` worktree rows.

**Tech Stack:** Swift, SwiftUI, git CLI via `Process`

---

### Task 1: Add merge and status methods to GitService

**Files:**
- Modify: `Tempo/Services/GitService.swift:103` (before `// MARK: - Status`)
- Modify: `Tempo/Services/GitService.swift:252-279` (Types section)
- Test: `Tests/GitServiceTests.swift`

- [ ] **Step 1: Write failing test for `hasUncommittedChanges`**

Add to `Tests/GitServiceTests.swift` before the `// MARK: - Helpers` section (line 234):

```swift
// MARK: - Merge Operations

@Test func hasUncommittedChangesClean() async throws {
    try await withTempRepo { repo in
        let dirty = try await git.hasUncommittedChanges(repoPath: repo)
        #expect(dirty == false)
    }
}

@Test func hasUncommittedChangesDirty() async throws {
    try await withTempRepo { repo in
        try "modified".write(toFile: "\(repo)/file.txt", atomically: true, encoding: .utf8)
        let dirty = try await git.hasUncommittedChanges(repoPath: repo)
        #expect(dirty == true)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter GitServiceTests.hasUncommittedChanges 2>&1 | tail -20`
Expected: FAIL — `hasUncommittedChanges` not defined

- [ ] **Step 3: Implement `hasUncommittedChanges`**

Add to `Tempo/Services/GitService.swift` at line 104, before `// MARK: - Status`:

```swift
// MARK: - Merge Operations

/// Returns true if the working tree has uncommitted changes (staged or unstaged).
func hasUncommittedChanges(repoPath: String) async throws -> Bool {
    let output = try await run(["status", "--porcelain"], in: repoPath)
    return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter GitServiceTests.hasUncommittedChanges 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 5: Write failing test for `commitCount`**

Add after the `hasUncommittedChanges` tests:

```swift
@Test func commitCount() async throws {
    try await withTempRepo { repo in
        try shell("git checkout -b feat/count", in: repo)
        for i in 1...3 {
            try "change \(i)".write(toFile: "\(repo)/file.txt", atomically: true, encoding: .utf8)
            try shell("git add -A && git commit -m 'commit \(i)'", in: repo)
        }
        let count = try await git.commitCount(from: "feat/count", to: "main", repoPath: repo)
        #expect(count == 3)
    }
}
```

- [ ] **Step 6: Run test to verify it fails**

Run: `swift test --filter GitServiceTests.commitCount 2>&1 | tail -20`
Expected: FAIL — `commitCount` not defined

- [ ] **Step 7: Implement `commitCount`**

Add below `hasUncommittedChanges` in `Tempo/Services/GitService.swift`:

```swift
/// Returns the number of commits in `from` that are not in `to`.
func commitCount(from source: String, to target: String, repoPath: String) async throws -> Int {
    let output = try await run(["rev-list", "--count", "\(target)..\(source)"], in: repoPath)
    return Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
}
```

- [ ] **Step 8: Run test to verify it passes**

Run: `swift test --filter GitServiceTests.commitCount 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 9: Write failing test for `mergeInto` — success case**

Add after the `commitCount` test:

```swift
@Test func mergeIntoSuccess() async throws {
    try await withTempRepo { repo in
        try shell("git checkout -b feat/merge-ok", in: repo)
        try "merged".write(toFile: "\(repo)/new.txt", atomically: true, encoding: .utf8)
        try shell("git add -A && git commit -m 'feature work'", in: repo)
        try shell("git checkout main 2>/dev/null || git checkout master", in: repo)

        let result = try await git.mergeInto(
            target: "main",
            source: "feat/merge-ok",
            repoPath: repo
        )

        switch result {
        case .success(let count):
            #expect(count == 1)
            // Verify the file is now on main
            let content = try String(contentsOfFile: "\(repo)/new.txt", encoding: .utf8)
            #expect(content == "merged")
        case .conflict:
            Issue.record("Expected success but got conflict")
        }
    }
}
```

- [ ] **Step 10: Run test to verify it fails**

Run: `swift test --filter GitServiceTests.mergeIntoSuccess 2>&1 | tail -20`
Expected: FAIL — `mergeInto` not defined

- [ ] **Step 11: Write failing test for `mergeInto` — conflict case**

```swift
@Test func mergeIntoConflict() async throws {
    try await withTempRepo { repo in
        // Create conflicting changes on two branches
        try shell("git checkout -b feat/conflict", in: repo)
        try "branch version".write(toFile: "\(repo)/file.txt", atomically: true, encoding: .utf8)
        try shell("git add -A && git commit -m 'branch change'", in: repo)

        try shell("git checkout main 2>/dev/null || git checkout master", in: repo)
        try "main version".write(toFile: "\(repo)/file.txt", atomically: true, encoding: .utf8)
        try shell("git add -A && git commit -m 'main change'", in: repo)

        let result = try await git.mergeInto(
            target: "main",
            source: "feat/conflict",
            repoPath: repo
        )

        switch result {
        case .success:
            Issue.record("Expected conflict but got success")
        case .conflict(let files):
            #expect(files.contains("file.txt"))
        }
    }
}
```

- [ ] **Step 12: Implement `MergeResult` type and `mergeInto`**

Add `MergeResult` to the Types section in `Tempo/Services/GitService.swift` (after `GitError`):

```swift
enum MergeResult {
    case success(commitCount: Int)
    case conflict(files: [String])
}
```

Add `mergeInto` below `commitCount` in the Merge Operations section:

```swift
/// Merges source branch into target branch.
/// Checks out target, attempts merge. On conflict, aborts and returns conflicting files.
func mergeInto(target: String, source: String, repoPath: String) async throws -> MergeResult {
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
            try? await run(["merge", "--abort"], in: repoPath)
            return .conflict(files: files)
        }
        // Not a conflict — re-throw
        throw error
    }

    // Count commits that were merged
    let output = try await run(["log", "--oneline", "\(target)@{1}..\(target)"], in: repoPath)
    let count = output.split(separator: "\n").count
    return .success(commitCount: count)
}
```

- [ ] **Step 13: Run merge tests to verify they pass**

Run: `swift test --filter GitServiceTests.mergeInto 2>&1 | tail -20`
Expected: PASS (both success and conflict cases)

- [ ] **Step 14: Write failing test for `deleteBranch`**

```swift
@Test func deleteBranch() async throws {
    try await withTempRepo { repo in
        try shell("git checkout -b feat/to-delete", in: repo)
        try "x".write(toFile: "\(repo)/del.txt", atomically: true, encoding: .utf8)
        try shell("git add -A && git commit -m 'branch work'", in: repo)
        try shell("git checkout main 2>/dev/null || git checkout master", in: repo)

        // Merge first so -d works (safe delete requires merged)
        try shell("git merge feat/to-delete", in: repo)

        try await git.deleteBranch(name: "feat/to-delete", repoPath: repo)

        let branches = try await git.listBranches(repoPath: repo)
        #expect(!branches.contains { $0.name == "feat/to-delete" })
    }
}
```

- [ ] **Step 15: Implement `deleteBranch`**

Add below `mergeInto` in `Tempo/Services/GitService.swift`:

```swift
/// Deletes a local branch. Uses -d (safe delete) — only works if branch is fully merged.
func deleteBranch(name: String, repoPath: String) async throws {
    try await run(["branch", "-d", name], in: repoPath)
}
```

- [ ] **Step 16: Run all new tests**

Run: `swift test --filter GitServiceTests 2>&1 | tail -30`
Expected: All PASS

- [ ] **Step 17: Commit**

```bash
git add Tempo/Services/GitService.swift Tests/GitServiceTests.swift
git commit -m "feat: add merge, delete branch, and status methods to GitService"
```

---

### Task 2: Create MergeWorktreeSheet view

**Files:**
- Create: `Tempo/Views/MergeWorktreeSheet.swift`

- [ ] **Step 1: Create the MergeWorktreeSheet**

Create `Tempo/Views/MergeWorktreeSheet.swift`:

```swift
import SwiftUI

/// Two-phase sheet for merging a worktree branch and cleaning up.
///
/// Phase 1: User confirms source/target branches, sees commit count, clicks "Merge & Finish"
/// Phase 2: After successful merge, user chooses whether to delete worktree and branch
struct MergeWorktreeSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    let project: Project
    let worktreePath: String
    let branchName: String
    /// Session ID if triggered from an active session (sidebar context menu)
    var sessionId: UUID?

    @State private var targetBranch = ""
    @State private var branches: [BranchInfo] = []
    @State private var commitCount: Int?
    @State private var isLoading = true
    @State private var isMerging = false
    @State private var errorMessage: String?

    // Phase 2 state
    @State private var mergeComplete = false
    @State private var mergedCommitCount = 0
    @State private var deleteWorktree = true
    @State private var deleteBranch = true
    @State private var isCleaningUp = false

    private let git = GitService()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(mergeComplete ? "Merge Successful" : "Merge & Finish")
                .font(.title2)
                .fontWeight(.bold)

            if mergeComplete {
                cleanupPhase
            } else {
                mergePhase
            }
        }
        .padding(20)
        .frame(width: 450, height: mergeComplete ? 300 : 380)
        .task { await loadInfo() }
    }

    // MARK: - Phase 1: Merge

    private var mergePhase: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Source branch (read-only)
            VStack(alignment: .leading, spacing: 4) {
                Text("Source Branch")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(branchName)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
            }

            // Target branch picker
            VStack(alignment: .leading, spacing: 4) {
                Text("Merge Into")
                    .font(.subheadline)
                    .fontWeight(.medium)
                if branches.isEmpty {
                    TextField("main", text: $targetBranch)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Picker("", selection: $targetBranch) {
                        ForEach(branches.filter { $0.name != branchName }) { branch in
                            Text(branch.name).tag(branch.name)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: targetBranch) { _, _ in
                        Task { await loadCommitCount() }
                    }
                }
            }

            // Commit count
            if let count = commitCount {
                HStack(spacing: 6) {
                    Image(systemName: "number")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("\(count) commit\(count == 1 ? "" : "s") to merge")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            if isMerging {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Merging...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isMerging)
                Spacer()
                Button("Merge & Finish") { performMerge() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        isLoading || isMerging || targetBranch.isEmpty || targetBranch == branchName
                    )
            }
        }
    }

    // MARK: - Phase 2: Cleanup

    private var cleanupPhase: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Success summary
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.green)
                Text("Merged **\(branchName)** into **\(targetBranch)** (\(mergedCommitCount) commit\(mergedCommitCount == 1 ? "" : "s"))")
                    .font(.subheadline)
            }

            Divider()

            // Cleanup options
            VStack(alignment: .leading, spacing: 8) {
                Text("Cleanup")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Toggle("Delete worktree directory", isOn: $deleteWorktree)
                    .font(.subheadline)
                Toggle("Delete branch \"\(branchName)\"", isOn: $deleteBranch)
                    .font(.subheadline)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            if isCleaningUp {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Cleaning up...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isCleaningUp)
                Spacer()
                Button("Finish") { performCleanup() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isCleaningUp || (!deleteWorktree && !deleteBranch))
            }
        }
    }

    // MARK: - Actions

    private func loadInfo() async {
        do {
            let branchList = try await git.listBranches(repoPath: project.repositoryPath)
            let detected = await git.baseBranch(for: branchName, repoPath: project.repositoryPath)

            branches = branchList
            targetBranch = detected
                ?? branchList.first(where: { $0.name == "main" })?.name
                ?? branchList.first?.name
                ?? "main"

            await loadCommitCount()
        } catch {
            errorMessage = "Failed to load repository info"
        }
        isLoading = false
    }

    private func loadCommitCount() async {
        guard !targetBranch.isEmpty else { return }
        commitCount = try? await git.commitCount(
            from: branchName,
            to: targetBranch,
            repoPath: project.repositoryPath
        )
    }

    private func performMerge() {
        isMerging = true
        errorMessage = nil

        Task {
            do {
                // Check for uncommitted changes in the worktree
                let dirty = try await git.hasUncommittedChanges(repoPath: worktreePath)
                if dirty {
                    errorMessage = "Worktree has uncommitted changes. Commit or stash them first."
                    isMerging = false
                    return
                }

                let result = try await git.mergeInto(
                    target: targetBranch,
                    source: branchName,
                    repoPath: project.repositoryPath
                )

                switch result {
                case .success(let count):
                    mergedCommitCount = count
                    mergeComplete = true
                case .conflict(let files):
                    errorMessage = "Merge conflict in: \(files.joined(separator: ", "))\nResolve conflicts manually and try again."
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isMerging = false
        }
    }

    private func performCleanup() {
        isCleaningUp = true
        errorMessage = nil

        Task {
            // Close session if active
            if let sid = sessionId {
                appState.performCloseSession(id: sid)
            } else if let session = appState.sessions.first(where: { $0.worktreePath == worktreePath }) {
                appState.performCloseSession(id: session.id)
            }

            do {
                if deleteWorktree {
                    try await git.removeWorktree(
                        repoPath: project.repositoryPath,
                        worktreePath: worktreePath
                    )
                }

                if deleteBranch {
                    try await git.deleteBranch(name: branchName, repoPath: project.repositoryPath)
                }

                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isCleaningUp = false
            }
        }
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build 2>&1 | tail -20`
Expected: Build succeeds (sheet isn't wired up yet, but should compile)

- [ ] **Step 3: Commit**

```bash
git add Tempo/Views/MergeWorktreeSheet.swift
git commit -m "feat: add MergeWorktreeSheet two-phase merge and cleanup view"
```

---

### Task 3: Wire merge action into Sidebar context menu

**Files:**
- Modify: `Tempo/Views/Sidebar.swift:12` (add state property)
- Modify: `Tempo/Views/Sidebar.swift:115-162` (context menu)
- Modify: `Tempo/Views/Sidebar.swift:53-76` (sheet bindings)

- [ ] **Step 1: Add state property for merge sheet**

In `Tempo/Views/Sidebar.swift`, add after the `watchdogSessionId` state (line 17):

```swift
@State private var mergeSession: SessionInfo?
```

- [ ] **Step 2: Add "Merge & Finish..." to session context menu**

In `sessionContextMenu` (around line 115), add after the `Button("Watchdog...")` block and before the first `Divider()`:

```swift
if session.isWorktreeSession {
    Button("Merge & Finish...") {
        mergeSession = session
    }
}
```

- [ ] **Step 3: Add sheet binding for MergeWorktreeSheet**

After the existing `watchdogSessionId` sheet binding (around line 76), add:

```swift
.sheet(item: $mergeSession) { session in
    if let project = appState.projects.first(where: { $0.id == session.projectId }),
       let branch = session.branchName,
       let wtPath = session.worktreePath {
        MergeWorktreeSheet(
            project: project,
            worktreePath: wtPath,
            branchName: branch,
            sessionId: session.id
        )
        .environmentObject(appState)
    }
}
```

Note: `SessionInfo` needs to conform to `Identifiable` (it already does via `let id = UUID()`), but we also need it to conform to `Hashable` for `.sheet(item:)`. Alternatively, use a binding approach. Actually, `.sheet(item:)` requires `Identifiable`, which `SessionInfo` already conforms to. But `@State` with `item` also requires the type to be `Identifiable`. Since `SessionInfo` is already `Identifiable`, this works.

- [ ] **Step 4: Verify it compiles**

Run: `swift build 2>&1 | tail -20`
Expected: Build succeeds

- [ ] **Step 5: Commit**

```bash
git add Tempo/Views/Sidebar.swift
git commit -m "feat: add Merge & Finish to sidebar session context menu"
```

---

### Task 4: Wire merge action into ProjectDetailView

**Files:**
- Modify: `Tempo/Views/ProjectDetailView.swift:13` (add state property)
- Modify: `Tempo/Views/ProjectDetailView.swift:174-260` (worktree row)
- Modify: `Tempo/Views/ProjectDetailView.swift:73-91` (sheet/alert bindings)

- [ ] **Step 1: Add state property**

In `Tempo/Views/ProjectDetailView.swift`, add after `worktreeToDelete` (line 13):

```swift
@State private var worktreeToMerge: WorktreeInfo?
```

- [ ] **Step 2: Add merge button to worktree row**

In the `worktreeRow` method, inside the `else` block that shows the "Open" and "Delete" buttons (around line 235-250), add the merge button between the "Open" button and the "Delete" button:

```swift
if !isMain, let branch = wt.branch {
    Button(action: { worktreeToMerge = wt }) {
        Image(systemName: "arrow.merge")
            .font(.system(size: 11))
    }
    .buttonStyle(.bordered)
    .controlSize(.small)
    .help("Merge & Finish")
}
```

- [ ] **Step 3: Add sheet binding for MergeWorktreeSheet**

After the existing `.alert("Delete Worktree?"` binding (around line 91), add:

```swift
.sheet(item: $worktreeToMerge) { wt in
    if let branch = wt.branch {
        MergeWorktreeSheet(
            project: project,
            worktreePath: wt.path,
            branchName: branch
        )
        .environmentObject(appState)
    }
}
```

Note: `WorktreeInfo` already conforms to `Identifiable` (via `var id: String { path }`), but for `.sheet(item:)` it also needs to be `Hashable`. We need to add `Hashable` conformance to `WorktreeInfo`. Add it in `GitService.swift`:

Change `struct WorktreeInfo: Identifiable {` to `struct WorktreeInfo: Identifiable, Hashable {`.

- [ ] **Step 4: Verify it compiles**

Run: `swift build 2>&1 | tail -20`
Expected: Build succeeds

- [ ] **Step 5: Commit**

```bash
git add Tempo/Views/ProjectDetailView.swift Tempo/Services/GitService.swift
git commit -m "feat: add Merge & Finish button to ProjectDetailView worktree rows"
```

---

### Task 5: Manual smoke test and final verification

**Files:**
- All modified files

- [ ] **Step 1: Run full test suite**

Run: `swift test 2>&1 | tail -40`
Expected: All tests pass

- [ ] **Step 2: Build the app**

Run: `swift build 2>&1 | tail -20`
Expected: Build succeeds with no warnings in our modified files

- [ ] **Step 3: Commit any remaining fixes**

If any fixes were needed, commit them:

```bash
git add -A
git commit -m "fix: address build/test issues in merge worktree feature"
```
