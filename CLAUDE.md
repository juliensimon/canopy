# Canopy

macOS app for running parallel Claude Code sessions across git worktrees (version: see VERSION file).

## Build

- `swift build` — debug build. **Does NOT compile the test target**: a syntactically broken test file builds clean here and only fails under `swift test`.
- `swift test` — run test suite (783 tests, 58 suites). Run this, not just `swift build`, before claiming anything works.
- `scripts/bundle.sh` — release build via Xcode; auto-generates BuildInfo.swift; installs to /Applications
- **Always run `scripts/bundle.sh` after code changes** — it archives via Xcode and installs to /Applications, which `swift build` does not do. It no longer dirties the tree: the committed `BuildInfo.swift` is restored on exit unless `--release` is passed. `--dry-run` stops before the archive.

## Architecture

```
Canopy/App/AppState.swift   — central @MainActor state (~1350 lines), all @Published UI state
Canopy/Models/              — Codable structs: Project, CanopySettings (+ SandboxBackend enum), ActivityData, PromptLibrary
Canopy/Services/            — GitService, TerminalSession, ClaudeAgentsService (activity truth source),
                              ClaudeTranscriptLoader, SessionCostService, ActivityDataService,
                              NotificationService, SandboxChecker, ContainerImageBuilder, UpdateChecker
Canopy/Utilities/           — ClaudeSessionFinder (legacy fallback only), ClaudeVersionChecker, ProjectColor
Canopy/Views/               — SwiftUI components. SandboxBackendUI (in EditProjectSheet.swift) is the
                              single source of sandbox picker labels and descriptions — do not re-type them
Tests/                      — Swift Testing suites (@Suite/@Test), NOT XCTest
```

## Testing

- Framework: Swift `Testing` (@Suite/@Test macros) — not XCTest
- Pattern: create temp repos via `NSTemporaryDirectory()` + `defer { cleanup }`
- `AppState(configDir:)` isolates sessions, projects **and** settings. Use it for anything
  settings-touching, or the test reads your real `~/.config/canopy/settings.json` and passes
  locally while failing in CI (see `Tests/SettingsIsolationTests.swift`)
- Integration tests shell out to real `git` CLI — no mocking
- TDD: write tests first, run `swift test` at each step

## Key Patterns

- Git: shells out to `git` CLI (no Swift git library)
- Notifications: `UNUserNotificationCenter` — app is notarized; app icon shows automatically
- Persistence: JSON files at `~/.config/canopy/{projects,settings,sessions,prompts}.json`
- Activity data: scans `~/.claude/projects/` for Claude Code JSONL session files
- Concurrency: strict Swift 6 @MainActor; use `Task { @MainActor in ... }` for background→main
- Three-tier resolution: both `sandboxBackend(for:)` and `resolvedClaudeFlags(for:)` resolve
  session → project → global. For flags, `nil` (inherit) and `""` (no flags) are different
- Claude session IDs are **assigned**, not discovered: `--session-id <uuid>` on first launch,
  `--resume` after. Validate as a UUID before shelling out, never overwrite an established id,
  and persist an assigned id *before* the command is sent

## Secret Prevention

- Pre-commit hook runs `gitleaks` on staged files — requires `brew install gitleaks`
- Activate hooks once per clone: `git config core.hooksPath .githooks`
- CI also runs gitleaks on every push/PR (`.github/workflows/secret-scan.yml`)
- `.github/workflows/ci.yml` builds + tests + uploads coverage. Its `pull_request:` trigger has
  **no `branches:` filter on purpose** — with one, stacked PRs targeting a non-master branch got
  no CI at all and code reached master having only been built locally
- Common credential files (`.env.*`, `*.pem`, `*.p8`, `AuthKey_*.p8`, etc.) are gitignored

## Gotchas

- `BuildInfo.swift` is tracked and load-bearing (`release.yml` validates it against `VERSION`;
  AboutView and UpdateChecker read it). bundle.sh regenerates it transiently and restores the
  committed copy; only `bundle.sh --release` is meant to change it. Never edit it by hand
- SwiftTerm stderr redirected to /dev/null in CanopyApp.swift (suppress noise)
- SwiftTerm table rendering misaligns with cursor movements — known issue, deprioritized
- Sandbox disabled in entitlements (required for CLI access)
- Four sandbox backends: off, claudeNative (Seatbelt, Bash only), dockerSbx (legacy, no resume),
  appleContainer. Anything user-facing about them belongs in `SandboxBackendUI`
- `VERSION` file is the single source of truth for version numbers
- `project.yml` is the XcodeGen config; run `xcodegen generate` to regenerate .xcodeproj
- `.claude/` is git-ignored (local Claude Code state not tracked)
