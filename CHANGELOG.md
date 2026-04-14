# Changelog

All notable changes to Canopy will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
