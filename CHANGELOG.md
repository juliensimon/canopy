# Changelog

All notable changes to Canopy will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
