# Merge & Finish Worktree

**Date:** 2026-04-06
**Status:** Approved

## Summary

Add a "Merge & Finish" action to Tempo that merges a worktree's branch into its base branch, then optionally deletes the worktree and branch. This completes the worktree lifecycle: create, work, finish.

## User Flow

1. User triggers "Merge & Finish..." from either:
   - Right-click context menu on a worktree session in the sidebar
   - Merge button on a worktree row in ProjectDetailView
2. **MergeWorktreeSheet** appears showing:
   - Source branch (the worktree's branch, read-only)
   - Target branch (auto-detected via `GitService.baseBranch()`, editable via picker)
   - Commit count between source and target
3. User clicks "Merge & Finish":
   - If the worktree has uncommitted changes, block with an error message
   - Checkout the target branch in the main repository
   - Run `git merge <source-branch>`
   - On **conflict**: run `git merge --abort`, show error listing conflicting files
   - On **success**: show confirmation panel
4. Confirmation panel displays:
   - Summary: "Merged `feat/x` into `main` (3 commits)"
   - Checkbox: "Delete worktree directory" (default: on)
   - Checkbox: "Delete branch" (default: on)
   - "Finish" button executes cleanup; "Close" keeps everything as-is

## GitService Changes

### New Methods

**`mergeInto(target:source:repoPath:) async throws -> MergeResult`**

- Checks out `target` branch in the repo at `repoPath`
- Runs `git merge <source>`
- On success: returns `MergeResult.success(commitCount:)`
- On conflict: runs `git merge --abort`, returns `MergeResult.conflict(files:)`
- Parses conflicting files from `git diff --name-only --diff-filter=U`

**`deleteBranch(name:repoPath:) async throws`**

- Runs `git branch -d <name>` (safe delete, only works if branch is merged)

**`hasUncommittedChanges(repoPath:) async throws -> Bool`**

- Runs `git status --porcelain` and checks for non-empty output

**`commitCount(from:to:repoPath:) async throws -> Int`**

- Runs `git rev-list --count <to>..<from>` for the pre-merge summary

### New Types

```swift
enum MergeResult {
    case success(commitCount: Int)
    case conflict(files: [String])
}
```

## UI Changes

### MergeWorktreeSheet (new file)

A sheet with two phases:

**Phase 1 — Confirm merge:**
- Source branch label (read-only)
- Target branch picker (populated from `GitService.listBranches`, defaults to detected base)
- Commit count display
- "Merge & Finish" button (disabled while loading or if source == target)

**Phase 2 — Post-merge cleanup:**
- Success message with commit count
- Two checkboxes: delete worktree, delete branch
- "Finish" button to execute cleanup
- "Close" to dismiss without cleanup

**Error states:**
- Uncommitted changes: inline error, merge button disabled
- Merge conflict: error message listing conflicting files, dismiss button only
- Delete failure: inline error (non-fatal, worktree was already merged)

### Sidebar (Sidebar.swift)

Add "Merge & Finish..." to `sessionContextMenu`, guarded by `session.isWorktreeSession`:

```swift
if session.isWorktreeSession {
    Button("Merge & Finish...") {
        mergeSession = session
    }
}
```

New `@State` property `mergeSession: SessionInfo?` triggers the sheet.

### ProjectDetailView (ProjectDetailView.swift)

Add a merge button to `worktreeRow` for non-main worktrees, next to the existing Open and Delete buttons:

```swift
Button(action: { worktreeToMerge = wt }) {
    Image(systemName: "arrow.merge")
        .font(.system(size: 11))
}
.buttonStyle(.bordered)
.controlSize(.small)
.help("Merge & Finish")
```

New `@State` property `worktreeToMerge: WorktreeInfo?` triggers the sheet.

## Edge Cases

| Case | Behavior |
|------|----------|
| Dirty worktree | Block merge, show "Uncommitted changes" error |
| Merge conflicts | Abort merge, show conflicting file list |
| Active session on worktree | Close session before deleting worktree |
| Branch already deleted | Ignore deletion error gracefully |
| Target branch same as source | Disable merge button |
| Fast-forward possible | Git handles this naturally via `git merge` |
| Branch not fully merged (`-d` fails) | Show error, suggest using `-D` is NOT offered (safety) |

## Files to Create/Modify

| File | Action |
|------|--------|
| `Tempo/Views/MergeWorktreeSheet.swift` | **Create** — new sheet view |
| `Tempo/Services/GitService.swift` | **Modify** — add merge, delete branch, status methods |
| `Tempo/Views/Sidebar.swift` | **Modify** — add context menu item + sheet binding |
| `Tempo/Views/ProjectDetailView.swift` | **Modify** — add merge button + sheet binding |
