# Canopy — Agent Context

Native macOS app (Swift 6, macOS 14+) for managing parallel Claude Code sessions across git worktrees.

## Repository Layout

| Path | Purpose |
|------|---------|
| `Canopy/App/AppState.swift` | Central observable state (~960 lines), @MainActor |
| `Canopy/Models/` | Codable data models (Project, CanopySettings, ActivityData) |
| `Canopy/Services/` | Business logic (GitService, TerminalSession, ActivityDataService) |
| `Canopy/Views/` | SwiftUI components |
| `Tests/` | Test suites using Swift's `Testing` framework |
| `scripts/bundle.sh` | Release build script (Xcode) |
| `project.yml` | XcodeGen project config |
| `Package.swift` | SPM config (single dep: SwiftTerm) |
| `VERSION` | Version source of truth |

## Build & Test Commands

```bash
swift build              # debug build
swift test               # run all tests
scripts/bundle.sh        # release build + install to /Applications
xcodegen generate        # regenerate Canopy.xcodeproj from project.yml
```

## Testing Rules

- Use Swift `Testing` framework (`@Suite`, `@Test`, `#expect`) — never XCTest
- Tests must run against real resources (temp git repos, real file system) — no mocks
- Always write tests before implementation (TDD)
- Run `swift test` after every change

## Critical Patterns

- All @Published state lives in `AppState` — add new state there
- Persist models as JSON to `~/.config/canopy/` using Codable
- Git operations use shell-out pattern (see GitService.swift for examples)
- macOS notifications via `UNUserNotificationCenter` (works because app is notarized)
- `BuildInfo.swift` is auto-generated — do not edit

## Secret Prevention

- Pre-commit hook blocks commits containing secrets (requires `brew install gitleaks`)
- Activate per clone: `git config core.hooksPath .githooks`
- CI secret scan: `.github/workflows/secret-scan.yml`
- Common credential files are gitignored (`.env.*`, `*.pem`, `*.p8`, `AuthKey_*.p8`, SSH keys)

## Swift 6 Concurrency Notes

- `AppState` and all Views are `@MainActor`
- Background work uses `Task { }` with explicit actor hops
- `MainActor.assumeIsolated()` used for synchronous callbacks from notification handlers
