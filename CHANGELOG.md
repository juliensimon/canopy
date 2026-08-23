# Changelog

All notable changes to Canopy will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.2.1] - 2026-08-23

### Added
- **Model, effort, and live context size in the status bar** (#78, #83, #84, #86):
  the active session's segment reads `opus-5 · xhigh · 402.3K` — which model
  produced its last turn, at what reasoning effort, and how much context that
  turn had to read. With several worktrees open there was previously no way to
  see which session was on which model, or how full its context had become,
  which is the number that decides whether a session is about to compact.

  The figure is deliberately absolute rather than a percentage. `claude-opus-5`
  and `claude-opus-5[1m]` are indistinguishable in the transcript, so a
  share-of-window reading would be silently five times wrong for long-context
  sessions — one real session here reads 991.5K, which a 200k assumption would
  render as 496%.

  Model and effort follow the last *completed* turn. Claude Code writes no
  transcript record for `/model` or `/effort`, so those fields exist only as
  attributes of an assistant turn: the bar reports what actually produced a
  turn rather than what a setting claims will happen next.

### Fixed
- **`/clear` no longer strands a session on its old conversation** (#83, #84, #86):
  `/clear` does not restart Claude, it re-keys the running process and starts a
  fresh transcript. Canopy kept the previous ID, so the status bar, the
  transcript viewer and the token counts all read a file that would never change
  again — and the next launch `--resume`d the conversation you had just cleared.
  A tab now records which process it took its ID from and follows that process
  when it re-keys. A different `claude` in the same directory still cannot take
  a session over.
- **Two Claude sessions in one worktree no longer blind the tab** (#86):
  previously an ambiguous match made Canopy give up on the whole directory,
  losing both the re-key and the live status. A tab that knows its own process
  is not guessing, so it picks its own out of the set.
- **Apple container sessions follow a re-key too** (#86): the gate that kept
  them out was doing two jobs. A container's *status* genuinely cannot be
  trusted — its peer socket is unreachable — but its *identity* can, because it
  bind-mounts `~/.claude`, which is why its transcript is readable at all.
  Status stays host-only; Docker Sandbox still reports nothing.
- **Fable usage no longer files under a label naming no model** (#77): the
  Activity view derived a model family from a hardcoded list with a `Claude`
  catch-all. Fable shipped after that was written, so 1.2M tokens landed under
  a name that identifies nothing. The family is now derived from the ID's shape,
  which also stops every future model family joining that same bucket.

### Changed
- Screenshots retaken at the current UI and compressed (#87). `project-detail`
  still showed the prominent "New Worktree Session" button that #60 demoted.
  The set drops from 6.4 MB to 1.6 MB, applying the `pngquant` rule that
  `docs/screenshots/README.md` documents and only `hero.png` had followed.

### Internal
- `swift test` no longer writes to the developer's real `~/.config/canopy`
  (#79, #80). `AppState(configDir:)` isolates persistence, but the parameter
  defaults to the real directory, so a bare `AppState()` followed by any write
  landed on your own config — fake sessions then appeared in the sidebar
  pointing at deleted temp directories. A guard test now fails if a test file
  default-constructs `AppState` at all.
- The git stale-session guard is tested through a seam rather than by winning a
  scheduling race (#81, #82), and the same treatment covers the session-context
  guard. The previous approach passed in isolation, failed under load, and was
  finally broken outright by an optimisation that made the awaited work faster.
  The clearing branch of that guard had no coverage at all.

## [1.2.0] - 2026-08-08

### Added
- **Worktree sessions are named in Claude Code** (#62, #63): Canopy passes
  `--name`, so a session is identifiable by its branch in Claude's prompt box
  and `/resume` picker instead of falling back to an auto-generated label.
  A newly created worktree session is named `<repo>-<branch>`; reopening an
  existing worktree uses the branch alone. Branch names are treated as hostile
  shell input — git refs permit characters a shell would act on — so they are
  sanitized and quoted before use. Plain sessions and detached-HEAD worktrees
  get no name: the former are renamed asynchronously and would race, the latter
  have no branch worth naming.
- **"Needs input" session state** (#52, #54): a session blocked on a permission
  prompt now shows an amber dot with a raised hand, and the status bar leads
  with "1 needs input". Previously the PTY went silent while Claude waited, so
  after five seconds the session was declared *finished* — checkmark, "Session
  finished" notification — and three seconds later decayed to grey, making a
  stalled agent indistinguishable from an idle one. Canopy now asks Claude Code
  directly (`claude agents --json`) instead of inferring from silence, so it can
  tell a permission prompt from a finished turn. Requires a backend that runs
  Claude on the host (Off or Claude sandbox); other backends keep the old
  heuristic. A separate **Notify when sessions need input** setting (on by
  default) fires even when Canopy is in front — unless you are already looking
  at that exact tab — since the blocked session usually is not the one on screen.
- **Claude sandbox (Bash only)** (#53): a third sandbox option, using Claude
  Code's own macOS Seatbelt sandbox. Nothing to install — no image, no daemon,
  no Docker — and session resume works. It is deliberately the weakest of the
  three: it confines **Bash only** (Read/Edit/Write go through the permission
  system), and while writes are limited to an allowlist, reads are filtered
  only by a deny-list, so `~/.ssh` and `~/.aws/credentials` remain readable.
  Canopy sets `allowUnsandboxedCommands: false`, because the CLI defaults it to
  *true*: without it, a command the sandbox denies is simply retried outside the
  sandbox and auto-approved by `--permission-mode auto`, which would make the
  setting advisory. The "Bash only" part is architectural — Claude Code wraps
  each shell command in `sandbox-exec`, so the profile covers the child process
  and not Claude itself. **Apple container remains the strongest option**: it is
  the only backend that confines the whole Claude process. Every sandbox picker
  now describes what its backend actually protects.
- **Per-session Claude flags** (#55): the New Worktree Session sheet has a flags
  field that overrides the project and global values for that session only, so
  "fable on the hard branch, opus on the chore branch" no longer means editing a
  project-wide setting that hits every sibling. Free text rather than pickers —
  `--permission-mode` gained `dontAsk` and renamed `default`→`manual` in 2.1.200,
  and every enum the CLI owns is a maintenance subscription.
- **Model and reasoning effort per turn in the transcript** (#56): each Claude
  turn is labelled with what produced it (e.g. `opus-5 · xhigh`). Copy includes
  it, so a transcript pasted into an issue says which model wrote which turn.
  Per-message on purpose: the model can change mid-conversation via `/model`,
  and effort is legitimately absent on older CLIs and on models without the
  concept.
- **Sandbox and Claude flags in Session Info** (#73): a running session had no
  way to show how it was actually isolated or which flags it launched with —
  both are per-session overridable, and a chosen backend can silently fall back
  when its prerequisites are missing. The flags row includes the `--add-dir`
  Canopy injects for worktree sessions, not only what you configured.

### Changed
- **Claude session IDs are assigned, not discovered** (#61): a new session is
  launched with `--session-id <uuid>` and resumed with `--resume` afterwards,
  instead of Canopy guessing which conversation a tab owned by scanning
  `~/.claude/projects/` for the most recently modified transcript. A tab is now
  bound to its own conversation from the moment it starts, so running `claude`
  yourself in the same directory cannot hijack it — and the transcript viewer
  and token counts work immediately, where before they were empty for the
  entire life of any session Canopy created.
- **Docker Sandbox (sbx) is labelled legacy**: it is the only backend without
  session resume, and Claude sandbox now covers the zero-install case. It still
  works and is not deprecated. (#53)
- **The project view leads with cross-worktree state** (#60): the worktree list
  and a collision summary come first; "New Worktree Session" moves into the
  header. Claude Code creates worktrees itself now (`claude -w`, `/fork`,
  isolated subagents), so creation is no longer the differentiated part —
  watching several at once is, and nothing upstream reports collisions.
- **SwiftTerm 1.15.0**, removing the hover-motion workaround. Upstream fixed the
  SGR encoding bug (migueldeicaza/SwiftTerm#520) that made buttonless hover
  motion read as a button release, so Canopy no longer swallows `mouseMoved`
  while any-event tracking is active. Hover highlighting in Claude Code's
  fullscreen menus works again, and the Cmd-hover link preview is no longer
  suppressed. (#48)
- **`scripts/bundle.sh` no longer dirties the working tree** (#64): it restores
  the committed `BuildInfo.swift` on exit unless `--release` is passed. Running
  it after every change — which CLAUDE.md instructs — used to guarantee a dirty
  generated file that `git add -A` swept into unrelated commits. New `--dry-run`
  stops before the archive.
- **CI runs on every pull request**, not only those targeting `master`. A
  `branches:` filter meant stacked PRs got no CI at all, so code could reach
  `master` having only ever been built locally.

### Fixed
- **A tab no longer adopts an unrelated Claude conversation** (#51):
  `loadSessions` overwrote every stored session ID on launch with whatever
  transcript in that directory was newest, so running `claude` yourself in a
  worktree — or opening a second tab on it — silently re-pointed the tab, and
  Canopy then `--resume`d into that conversation. An established session ID is
  user data; it is now filled in only when missing.
- **git works inside Docker Sandbox worktree sessions** (#59): only the worktree
  was mounted, so its `.git` file pointed at a path that did not exist in the
  sandbox and *every* git command failed with "not a git repository", with
  nothing surfaced by Canopy. The main repository is now passed as an extra sbx
  workspace.
- **Worktree sessions can read the main repository** (#58): mounting fixed the
  filesystem, but Claude Code's own tool boundary is scoped to the working
  directory independently of what is mounted, so a main-repo read was refused
  under `--permission-mode manual`. Canopy now passes `--add-dir`.
- **The sidebar shield names the right backend**: it was a binary test between
  two backends, so a Claude sandbox session displayed "Running in Apple
  container" — claiming stronger isolation than it had.
- **Tests no longer read your real settings**: `AppState(configDir:)` isolated
  sessions and projects but not `settings.json`, so a test could pass locally
  and fail in CI for reasons invisible in its body. (#66)
- **Claude-created worktrees under `.claude/worktrees/`** are verified to flow
  through worktree listing, collision reports and the unmerged-commit warning.
  The hypothesis held, so the deliverable is the tests. (#57)

## [1.1.2] - 2026-07-10

### Added
- **Staleness nudge for the sandbox image** (#44): when the Apple container
  image is more than 30 days old, Settings shows "Image built N days ago —
  Update to pull the latest Claude Code" next to the image status. Age-based
  on purpose — Claude Code releases near-daily, so comparing against "latest"
  would nudge constantly.
- **Host Claude Code CLI version in Settings** (#43): shown in the Claude Code
  section. CLI behavior changes are keyed to versions (e.g. the ≥ 2.1.132
  alternate-screen renderer) and the sandbox image can run a different version
  than the host, so drift is now diagnosable at a glance.

### Changed
- **Mouse reporting now follows the scroll bar setting** (#42): scrollback mode
  (default) keeps mouse reporting off so plain click-drag selects text;
  fullscreen mode enables it so Claude Code's clickable menus and Cmd+click
  links work (Option-drag still selects text).
- **Release CI now asserts `BuildInfo.version` matches `VERSION`** before
  signing, so a forgotten regeneration fails fast instead of shipping a stale
  About panel. (#39)

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
