# Changelog

All notable changes to Canopy will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- **Terminal scroll bar restored with Claude Code ≥ 2.1.206** (#40): newer
  Claude Code renders in the alternate screen buffer, which has no scrollback,
  so SwiftTerm disabled its scroller. A new **Show terminal scroll bar**
  setting (Settings → Sessions, default on) opts sessions out via
  `CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1` — including Apple container
  sessions, where it's injected as a `--env` flag. Turn it off to keep
  Claude Code's alt-screen rendering. Applies to new sessions.

## [1.1.1] - 2026-06-30

### Added
- **Update the Apple container sandbox image**: a new **Update** button (Settings
  → Apple container, next to Build Image) rebuilds the image with `--no-cache`
  to pull the latest Claude Code. Claude Code is baked into an image layer with
  its auto-updater disabled, so the version was previously frozen at first build
  — and a plain rebuild reused the cached install layer and reinstalled the same
  version. (#38)
- **Privacy statement in the About window**: a "Zero telemetry · Zero data
  collection" line, with a note disclosing that the only outbound request is the
  optional, user-toggleable update check to GitHub. (#35)

### Changed
- **Claude JSONL timestamp parsing is now single-sourced** through
  `ClaudeSessionFinder.parseTimestamp`, removing duplicated ISO8601 parsing in
  the activity and cost services (behavior-preserving). (#36)

### Fixed
- **Sandbox readiness is now checked when a session launches**, not just when a
  backend is selected in Settings. A backend that stopped being ready after
  configuration — most commonly the Apple container runtime not restarted after
  a reboot — now prints the actionable fix (e.g. `container system start`) in the
  session terminal instead of a cryptic `XPC connection error`. (#37)

## [1.1.0] - 2026-06-22

### Added
- **Cross-worktree conflict pre-flight for Merge & Finish**: before you merge,
  Canopy shows how the branch being merged collides with your *other* in-flight
  worktree branches. Two layers, advisory only (they never block the merge): a
  **hard** layer (`will conflict`) computed with `git merge-tree` for real
  textual conflicts, and a **watch** layer (`shared surface`) that flags files
  two branches both touch on a high-stakes surface — package manifests,
  lockfiles, migration directories, generated types — even when they merge
  textually clean (e.g. two same-sequence migrations). Surfaced in the Merge &
  Finish sheet and as a ⚠ badge (red = hard, orange = watch) on the project
  view's worktree rows. (#33)

### Fixed
- **Main worktree no longer misclassified on symlinked repo paths**: the main
  worktree could be shown as a feature worktree — wrongly offering Merge &
  Finish and Delete on your primary checkout — when the repository path was a
  symlink (e.g. `/tmp` vs `/private/tmp`). Path comparison now resolves
  symlinks before deciding. (#32)
- **Merge & Finish and the project view no longer hang on large repositories**:
  git commands that produced more than ~64KB of output (a big merge, or a
  worktree with many changed files) could deadlock and freeze the app — in the
  merge case, mid-merge with the repo left on the target branch. All git
  invocations now drain their output concurrently and cannot deadlock.
- **Config files are no longer lost on corruption**: a corrupt `projects.json`
  or `prompts.json` was silently discarded and then overwritten with an empty
  list on the next save, permanently losing every project's repo/worktree
  config or the entire prompt library. Both are now backed up before loading
  (like `sessions.json`) and written atomically.
- **Merge & Finish now closes the correct session** when the stored worktree
  path and git's resolved path differ only by a symlink, instead of leaving an
  orphaned tab (and a running shell) over a deleted worktree.
- **Merge & Finish runs git with repo-local hooks disabled.** A worktree's
  `.git` points into the (sandbox-writable) main repo, so a hook planted there
  could otherwise execute on the host the moment you clicked Merge & Finish.
- **Quitting Canopy now terminates every session's shell and Claude process**
  instead of leaving them — and any running, paid agent — alive after the
  window closes.
- **Background git-status polling pauses during Merge & Finish**, preventing a
  spurious "merge failed" from `index.lock` contention on the flagship flow.
- **Per-session token/cost counting is more accurate**: it now skips synthetic
  harness entries and excludes entries it can't place within the selected time
  window.
- **The command palette no longer rebuilds its full search corpus on every
  keystroke**, removing typing jank with several busy sessions open.
- **Worktree creation trims surrounding whitespace from the branch name**
  instead of failing when a text field carries a stray space.

### Changed
- The cross-worktree watch layer recognizes more shared surfaces (`go.sum`,
  `requirements.txt`, `Pipfile`, `composer.json`, `Podfile`) and now matches
  file surfaces case-insensitively.

## [1.0.0] - 2026-06-12

### Added
- **Apple container sandbox backend**: the Docker Sandbox toggle is now a
  picker -- Off / Docker Sandbox (sbx) / Apple container. The new backend runs
  Claude Code inside a lightweight VM via Apple's open-source
  [container](https://github.com/apple/container) runtime (macOS 26+, Apple
  silicon) with no Docker Desktop dependency. The worktree is mounted at its
  host path and `~/.claude` is mounted from the host, so session resume, Show
  Transcript, and activity tracking work in sandboxed sessions (unlike sbx).
  The image defaults to `canopy-claude` and a **Build Image** button in
  Settings creates it from Canopy's built-in recipe (native Claude Code
  install, so `/doctor` is clean against the mounted host config). Settings
  gain Container image / Container flags fields (global and per-project)
  plus a `container` CLI path row; Canopy validates the CLI is installed,
  the runtime is started, and whether the image exists locally.

- **Per-session sandbox override**: the New Worktree Session sheet gains a
  Sandbox picker (Use project default / Off / Docker Sandbox / Apple
  container) that applies to that session only. Resolution order is
  session → project → global.

### Changed
- Settings/projects persistence: `useSandbox` (bool) is superseded by
  `sandboxBackend` (`off` / `dockerSbx` / `appleContainer`). Existing files
  migrate automatically on load; the legacy key is still read.

### Fixed
- **Closing a session now terminates its shell and claude process.** They
  previously kept running (and an agent kept working/spending) invisibly
  until the app quit.
- **Session resume/transcripts/cost now work for paths with `_`, spaces,
  and other special characters**: Canopy's encoding of Claude Code's
  `~/.claude/projects/` directory names only handled `/` and `.`, while
  Claude replaces every non-alphanumeric character -- so worktrees like
  `fix_thing` silently lost resume and transcripts. `/tmp`-style paths now
  resolve the way Claude's `process.cwd()` does.
- **Merge & Finish** refuses to run when the main repository has
  uncommitted changes (the merge switches its checked-out branch and would
  drag them along), and it now restores the branch you had checked out
  instead of leaving the repo on the merge target. Cleanup closes the
  session only after the git operations succeed.
- **The unmerged-commits warning before deleting a worktree now works on
  master/develop repos** -- it was hardcoded to compare against `main` and
  silently passed when that branch didn't exist. Unknown merge state now
  warns instead of staying quiet.
- sessions.json is written atomically and backed up on load (a crash
  mid-write could previously corrupt it, and the next save erased all
  sessions permanently).
- Image build no longer hangs forever on builds with more than 64 KB of
  output (the progress pipe was only drained after exit); builds also get
  a 30-minute timeout. Settings save failures keep the sheet open with an
  error instead of pretending success; a corrupt settings.json is backed
  up to `settings.json.corrupt` before falling back to defaults.
- Reordering plain sessions in the sidebar no longer moves the wrong
  session when project sessions exist; Send Prompt is disabled for
  sessions whose terminal hasn't been opened yet (it silently did
  nothing); single quotes in Claude flags no longer break the sandbox
  command; closed sessions no longer reappear in the git status bar.

Apple container hardening, from adversarial review and end-to-end probing
with the real runtime:
- **git now works in sandboxed worktree sessions**: the project's main
  repository is mounted alongside the worktree (a worktree's `.git` file
  points there); `~/.gitconfig` is mounted **read-only** so commits have
  your identity -- read-only because a writable copy would let a sandboxed
  agent plant a git alias or `core.hooksPath` that executes on the host
  the next time you run git.
- The user guide gains a "What sandboxing does -- and doesn't -- protect
  against" section: an honest threat model covering the writable
  worktree/main repo (including `.git/hooks`), writable Claude state, and
  unrestricted outbound network. README and in-app Help state the precise
  boundary ("everything not explicitly mounted") instead of overclaiming.
- **Terminal no longer renders garbled** in container sessions: TERM,
  COLORTERM, and a UTF-8 locale are passed into the VM, and claude starts
  only after the VM terminal has its real window size (it briefly reports
  0x0, which made claude lay out for 80 columns).
- Home-directory sessions are blocked for the container backend with a clear
  message -- mounting `~` overlaps the `~/.claude` mounts and breaks the VM.
- Enabling "Override global Claude settings" on a project no longer silently
  saves auto-start=off and empty flags; fields now seed from the effective
  values, so saving without changes is a no-op.
- Config files written by a newer Canopy (unknown sandbox backend value) no
  longer silently factory-reset all settings/projects on load.
- Validation now also detects a missing Linux kernel (`container system
  status` passes even without one) and points at the exact fix command.
- Saving Settings (or a project sheet) while backend validation is running
  no longer persists a stale backend value.
- Fresh machines: `~/.claude`, `~/.claude.json`, and `~/.gitconfig` are
  created on first sandboxed launch instead of failing the mounts; the image
  build command quotes user input; claude self-updates inside the ephemeral
  VM are disabled (`DISABLE_AUTOUPDATER=1`).

## [0.9.5] - 2026-05-14

### Added
- **Show Transcript** view: right-click a session > Show Transcript… for a
  scrollable read-only view of the conversation. When the session is a Claude
  Code session, Canopy reads its structured JSONL session log and renders
  user/assistant turns with markdown formatting (assistant text via
  `AttributedString(markdown:)`, tool calls compacted to `🔧 ToolName — hint`
  rows, tool results to `↳ truncated` lines). Falls back to the raw 500 KB
  PTY capture for plain (non-Claude) sessions. Live-updates as the
  conversation streams via a 500 ms mtime poll on the JSONL. Header has an
  Auto-tail toggle -- on by default, turn off to read older history without
  being yanked down. Copy button in the footer (⌘⇧C) puts the formatted
  markdown on the clipboard. (#16)

### Changed
- Sidebar context menu: removed "Copy Session Output" -- the copy action now
  lives in the Show Transcript sheet (it copies the rendered markdown view, or
  the raw capture when no JSONL is available).
- `scripts/bundle.sh`: archive failures no longer install a stale `.xcarchive`.
  The previous `| xcpretty 2>/dev/null || cat` silently swallowed
  `xcodebuild`'s non-zero exit, then `cp -r` happily copied an old archive.
  Replaced with `set -o pipefail` + explicit existence check on the archive
  output path before installing.
- `project.yml` excludes `**/CLAUDE.md` from the Canopy sources -- prevents
  `claude-mem`'s auto-generated `<claude-mem-context>` marker files in source
  subdirectories from colliding in the .app's Resources bundle during archive.

## [0.9.4] - 2026-05-01

### Added
- Prompt Library: save and reuse prompts across Claude Code sessions. Create,
  edit, star, and reorder prompts in Settings → Prompt Library. Right-click a
  session to send a starred prompt directly or browse all via the picker sheet.
  Template variables `{{branch}}`, `{{project}}`, and `{{dir}}` are resolved at
  send time. Prompts persisted to `~/.config/canopy/prompts.json`. (#15)
- Secret scanning: pre-commit hook via `gitleaks` and CI workflow
  `.github/workflows/secret-scan.yml` on every push/PR to prevent credential
  leaks. (#13)

### Fixed
- Shift+Enter dropped input when a split pane was open. (#14)
- Sending a prompt via the Prompt Library now correctly submits in Claude Code
  (text and carriage return sent as separate pty `read()` batches via a 100 ms
  delay, preventing soft-newline misinterpretation).
- `BuildInfo.swift` generation escaped double quotes in commit messages to avoid
  Swift parse errors on revert commits.

## [0.9.3] - 2026-04-17

### Added
- Git awareness. A polled status bar at the bottom of the window shows the
  active session's modified-file count with insertion/deletion totals,
  commits ahead of upstream, and open pull-request count (with draft split),
  each with a hover tooltip for the full file list, push status, or PR
  titles. Sidebar session rows mirror the same data in compact form so
  every worktree's state is visible at once. (#8, #9, #10)
- Project detail view now lists every open pull request for the repository,
  pulled via `gh pr list`. (#10)
- Docker Sandbox support: optionally run Claude Code inside a `sbx` microVM
  for hard process isolation. Configurable globally and per-project with a
  toggle and optional `sbx run` flags. Canopy validates that Docker Desktop
  and `sbx` are installed before enabling. Session resume is automatically
  disabled in sandbox mode (session files are ephemeral). A shield icon in
  the sidebar indicates sandboxed sessions.
- Settings: `gh` and `sbx` CLI path overrides with auto-detection of the
  common Homebrew locations. Leave blank to use `PATH`; set explicitly for
  non-standard installs. (#11)

### Fixed
- Activity view: `<synthetic>` Claude Code harness entries (emitted for API
  errors and "No response requested." sentinels) were being counted as
  real model calls, polluting the per-model breakdown and session-day
  attribution. Filter them at parse time and bump the activity cache
  version so existing caches are invalidated on upgrade.
- Sidebar git data would occasionally display the previous session's
  diffstat/ahead/PR counts immediately after a tab switch. The 10-second
  git-status poller now guards against stamping stale data onto the
  newly-active session. (#12)
- Closing a session no longer leaks its per-session git entries
  (`sessionDiffStats`, `sessionCommitsAhead`, `sessionPRCount`). (#12)
- `selectSession` is now a no-op when called with an unknown session id,
  so stale notification callbacks (e.g. clicking a banner for a session
  that was closed in the meantime) can't clobber the active selection. (#12)
- `performOpenOrSelectSession` now guards `NSApp.activate` against a nil
  `NSApp`, which kept the app from crashing in test harnesses that post
  the `.canopySelectSession` notification without a running `NSApplication`.

### Internal
- New characterization tests around `AppState.refreshAllSessionPRCounts`
  cover the 60-second throttle, the `force:` override, the empty-session
  early exit, and commits-ahead tracking. (#12)
- Terminal output pipeline and notification routing now have direct test
  coverage.
- CI uploads coverage reports to Codecov; SwiftUI views are excluded from
  the coverage report.
- `.worktrees/` is now gitignored so local isolation worktrees don't
  pollute `git status`.

## [0.9.2] - 2026-04-14

### Fixed
- Activity view: labels, stat values, legend text, month spans, and hour-axis
  ticks were invisible in light mode because the dark-filled cards still used
  adaptive foreground styles (`.secondary`, `.tertiary`). Replaced the
  adaptive styles with explicit light-on-dark constants so the cards render
  correctly regardless of the system appearance. (#5, #6)
- Build: `UserNotifications` is not yet audited for Swift 6 strict
  concurrency, so `NotificationService` now uses `@preconcurrency import
  UserNotifications` to silence spurious `Sendable` warnings without losing
  diagnostics on our own code.

### Changed
- README: dropped the ASCII layout diagram and the Roadmap section in favor
  of the screenshots and live issue tracker. Docs-only, no user-visible
  behavior change.

## [0.9.1] - 2026-04-13

### Added
- Native macOS notifications via `UNUserNotificationCenter`. Session-finished
  banners now show Canopy's app icon and name (instead of Script Editor's),
  and clicking a banner activates Canopy and selects the finished session's
  tab. (#3)
- Background update check on launch. A rate-limited (once per 24h) GitHub
  Releases poll surfaces update availability in the About sheet and Settings,
  with a manual "Check Now" button and a native notification when a newer
  release is found. Semver comparison is numeric (so `0.10.0 > 0.9.0`). (#4)
- `Help → Check for Updates...` menu entry that triggers an immediate check
  and opens the About sheet so the status row is visible.
- Splash hero in the About sheet — a downscaled JPEG of the README splash
  image, with the About sheet resized to 540×520 to match the 2.4:1 aspect.
- Launch splash: the Canopy logo is now rendered in warm sand beige with a
  1px black outline, and the duplicate wordmark overlay on the About hero
  has been removed.

### Fixed
- `Resources/` directory (`CanopyLogo.png`, `Canopy.icns`, `Splash.jpg`) was
  being silently excluded from every Xcode build because `project.yml` used
  an invalid XcodeGen `resources:` target key. The app previously only
  worked because `AboutView` had a relative-path fallback. Resources are now
  bundled via a proper `sources:` entry with `buildPhase: resources`.
- `NotificationService.swift` was present on disk but not registered in
  `Canopy.xcodeproj/project.pbxproj`, which would have broken the next
  tagged release (`xcodebuild archive` does not do SPM-style target
  globbing). Regenerated via xcodegen.
- DMG no longer ships the `xcodebuild -exportArchive` sidecar files
  (`DistributionSummary.plist`, `ExportOptions.plist`, `Packaging.log`).
  `create-dmg` is now pointed at `Canopy.app` directly instead of the
  `build/export/` directory.
- Update-available notification path no longer references the removed
  AppleScript helper (leftover from the update-checker merge) that was
  breaking the CI build.
- README "Build" badge now points at `ci.yml` instead of `release.yml`, so
  it reflects master status rather than only tag pushes.

### Internal
- Homebrew tap workflow gained a `workflow_dispatch` trigger with a `tag`
  input, so the cask update can be re-dispatched on demand. The default
  `GITHUB_TOKEN` suppresses the cascading `release: published` event, so a
  manual escape hatch is required.

## [0.9.0] - 2026-04-13

First public release. 0.1.0 was an internal build; 0.9.0 is the same
app polished for distribution: signed, notarized, and installable via
Homebrew or direct DMG download.

### Added
- Direct DMG download link in the README (stable
  `releases/latest/download/Canopy.dmg` URL, published alongside the
  versioned asset).
- Dynamic GitHub badges (release, downloads, build status, stars,
  issues, last commit) in the README header.
- Splash header image (rainforest canopy at sunrise with the Canopy
  wordmark) replacing the bare logo at the top of the README.
- User guide section listing every keyboard shortcut.
- Help menu entry pointing at the online user guide.

### Fixed
- Command palette is now bound to `Cmd+K` (industry standard) instead
  of `Cmd+F`. `Cmd+F` is now wired through to the terminal output
  search it was always meant to trigger. The in-app Shortcuts sheet
  was updated to match.

### Changed
- Pitch line in the README rewritten to drop the arbitrary "four
  Claudes" framing.

## [0.1.0] - 2026-04-07

### Added
- Worktree lifecycle: create, open, merge, delete from the UI
- Session resume: reopen a worktree and continue the previous Claude conversation
- Auto-start Claude: configurable globally and per-project
- Tab sorting: manual, by name, project, creation date, or directory (Cmd+Shift+S)
- Drag-and-drop: reorder tabs and sidebar sessions
- Context menus: Open in Terminal, Finder, or IDE; copy paths and branch names
- Merge & Finish: merge branch, clean up worktree and branch in one step
- Split terminal: secondary shell pane below the main terminal (Cmd+Shift+D)
- Session persistence: sessions restored across app restarts with Claude resume
- Tab switching: Cmd+1–9 to jump to any tab instantly
- Finish notifications: macOS notification when a session finishes in background
- Command palette: Cmd+K fuzzy-match sessions, projects, branches, actions
- Terminal search: Cmd+F search through terminal output with match navigation
- Token and cost tracking: per-session and per-project from Claude JSONL files
- Welcome screen: onboarding for new users, quick-launch for returning users
- App icon: tropical rainforest canopy at sunrise
