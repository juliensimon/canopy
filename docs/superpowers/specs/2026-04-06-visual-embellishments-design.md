# Canopy Visual Embellishments Design

**Date:** 2026-04-06
**Branch:** canopy-header
**Approach:** Incremental enhancement — modify existing views in-place, no new abstractions

## Overview

Eight visual embellishments to elevate Canopy from functional to polished, while respecting macOS native design conventions. All changes are additive styling modifications to existing views plus one model change (project color).

---

## 1. Project Color System

**Model change:** Add `colorIndex: Int?` to `Project`. Auto-assigned on creation (cycling through palette), user-overridable via Edit Project sheet.

**Palette** (8 colors, deterministic assignment based on project creation order):
1. Purple `#7C6AEF` / `Color(.sRGB, red: 0.486, green: 0.416, blue: 0.937)`
2. Teal `#2AC3A2` / `Color(.sRGB, red: 0.165, green: 0.765, blue: 0.635)`
3. Orange `#E6853E` / `Color(.sRGB, red: 0.902, green: 0.522, blue: 0.243)`
4. Pink `#E05DB6` / `Color(.sRGB, red: 0.878, green: 0.365, blue: 0.714)`
5. Blue `#3B82F6` / `Color(.sRGB, red: 0.231, green: 0.510, blue: 0.965)`
6. Red `#EF4444` / `Color(.sRGB, red: 0.937, green: 0.267, blue: 0.267)`
7. Amber `#D4A843` / `Color(.sRGB, red: 0.831, green: 0.659, blue: 0.263)`
8. Green `#22C55E` / `Color(.sRGB, red: 0.133, green: 0.773, blue: 0.369)`

**Utility:** A `ProjectColor` enum or static helper that:
- Returns `Color` for a given `colorIndex`
- Auto-assigns next index: `((projects.compactMap(\.colorIndex).max() ?? -1) + 1) % 8` — resilient to project deletion
- Sessions without a project use system gray

**Files changed:** `Project.swift` (add `colorIndex`), new `ProjectColor.swift` utility, `AddProjectSheet.swift` and `EditProjectSheet.swift` (color picker row).

---

## 2. Tab Bar Polish

**File:** `SessionTabBar.swift`, `SessionTab`

### Active tab underline
- 2px `Color.accentColor` bar at bottom of active tab
- Implemented as an overlay `Rectangle` positioned at `.bottom` with `frame(height: 2)`
- Active tab background reduced from `opacity(0.15)` to `opacity(0.10)`
- Active tab corner radius changes to `6px top, 0 bottom` (flat bottom meets underline)

### Project color dot in tabs
- Replace the `ActivityDot` in `SessionTab` with a simple colored circle using the session's project color
- Active/working sessions: full opacity project color dot
- Idle sessions: project color at 50% opacity
- Sessions without a project: gray dot (current behavior)

### Tab separators
- 1px vertical `Divider` between tabs, `Color.gray.opacity(0.08)`, height 16px
- Hidden adjacent to the active tab (check if neighbor is active)

### Tab animations
- New tab: `.transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity.combined(with: .scale(scale: 0.8))))`
- Apply `withAnimation(.easeOut(duration: 0.25))` to session creation/removal in AppState

---

## 3. Sidebar Visual Hierarchy

**File:** `Sidebar.swift`

### Project header color band
- Section header background: `projectColor.opacity(0.05)`
- Left border: 2px `projectColor.opacity(0.4)` via `.overlay(alignment: .leading)` with a `Rectangle`
- Folder icon color: use project color instead of hardcoded `.orange`

### Session count badge
- Rounded pill next to project name: `Text("\(count)")` styled with:
  - Font: `.system(size: 9, weight: .semibold)`
  - Padding: `1px vertical, 6px horizontal`
  - Background: `projectColor.opacity(0.2)`
  - Foreground: `projectColor`
  - Corner radius: 8px
- Only shown when count > 0

### Branch subtitle color
- Worktree session subtitles use `projectColor.opacity(0.7)` instead of hardcoded `.blue.opacity(0.7)`

---

## 4. Activity Indicator Upgrade

**File:** `ActivityDot.swift`

### Ring spinner for working state
- Outer ring: 12px circle with 1.5px stroke in `projectColor.opacity(0.3)`, with top quarter in full `projectColor`
- Ring rotates continuously: `RotationEffect` with `Animation.linear(duration: 1.0).repeatForever(autoreverses: false)`
- Center dot: 5px circle, green for working, gray for idle (preserves activity meaning)
- Idle state: ring is static at low opacity (`projectColor.opacity(0.15)`), center dot gray at 40%

### "Just finished" state
- New case in `SessionActivity` enum (`TerminalSession.swift:178`): `.justFinished`
- Ring becomes solid blue (`Color.blue.opacity(0.4)`) with subtle glow (blur 4px)
- Center shows checkmark (SF Symbol `checkmark`) in blue, 10pt
- Auto-transitions to `.idle` after 3 seconds via `TerminalSession` timer
- `TerminalSession` sets `.justFinished` when activity transitions from `.working` to `.idle`

**ActivityDot accepts a new parameter:** `projectColor: Color = .gray`

---

## 5. Status Bar Enhancement

**File:** `StatusBar.swift`

### Activity summary
Replace `"\(count) session(s)"` with a richer summary:
- Mini colored dots (5px) for each session: green if working, gray if idle
- Text: `"2 working, 1 idle"` (or `"3 sessions"` if all same state)
- Dots are `ForEach` over `appState.orderedSessions` reading their terminal activity

---

## 6. Terminal Rounded Inset

**File:** `TerminalContentView.swift` (the SwiftUI wrapper), `MainWindow.swift`

### Rounded container
- Add 4px padding around the terminal view in `MainWindow.swift` (between tab bar and terminal)
- Terminal container gets: `clipShape(RoundedRectangle(cornerRadius: 8))` and `overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.15), lineWidth: 1))`
- Background behind the padding: match `.bar` or a dark neutral

### Branch name overlay
- Frosted-glass label in top-right of terminal area
- `Text(branchName)` with `.font(.system(size: 9))`, `.foregroundStyle(.secondary)`
- Background: `.ultraThinMaterial` with corner radius 4px, padding 2px/8px
- Appears on tab switch, fades out after 2 seconds: `opacity` animated with `onAppear` timer
- Positioned as overlay on the terminal container, `.topTrailing` alignment with 8px padding

---

## 7. Tab Switch Crossfade

**File:** `MainWindow.swift`

- Wrap the `SessionView` content switch in `.animation(.easeInOut(duration: 0.15), value: appState.activeSessionId)`
- The `.id(activeSession.id)` already causes view replacement — adding animation will crossfade

---

## 8. Empty State Upgrade

**File:** `Sidebar.swift` (sidebar empty state), `MainWindow.swift` (`WelcomeView`)

### Sidebar empty state
- Replace single terminal icon with layered card illustration:
  - Three overlapping rounded rectangles (48x36px) at slight rotations (-8deg, 4deg, 0deg)
  - Each tinted with a different palette color at low opacity
  - Front card has a play triangle icon
- Text: "No sessions yet" (instead of "No sessions")
- Subtitle: "Start your first parallel Claude session"

### Keyboard shortcut keycap badges
- Replace plain "Press Cmd+T to start" with styled keycap badges:
  - Background: `Color.gray.opacity(0.08)`, border: `Color.gray.opacity(0.12)`, corner radius 4px
  - Two badges: `Cmd+T New Session` and `Cmd+Shift+P Add Project`

---

## Data Flow Summary

```
Project.colorIndex (persisted in JSON)
    ↓
ProjectColor.color(for:) → Color
    ↓
├── SessionTabBar → project color dot per tab
├── Sidebar → header band, badge, subtitle tint
├── ActivityDot(projectColor:) → ring color
└── StatusBar → mini dots (activity color, not project color)
```

## Files Changed (summary)

| File | Change |
|------|--------|
| `Project.swift` | Add `colorIndex: Int?` property |
| New: `ProjectColor.swift` | Color palette utility |
| `SessionTabBar.swift` | Underline, project dots, separators, animations |
| `Sidebar.swift` | Color bands, badges, empty state upgrade |
| `ActivityDot.swift` | Ring spinner, project color param, justFinished state |
| `StatusBar.swift` | Activity summary with mini dots |
| `MainWindow.swift` | Terminal inset padding, crossfade, branch overlay |
| `TerminalContentView.swift` | Rounded clip + border |
| `TerminalSession.swift` | justFinished transition logic |
| `AppState.swift` | Animation wrappers on session create/remove |
| `AddProjectSheet.swift` | Color picker row |
| `EditProjectSheet.swift` | Color picker row |

## Testing

- Visual verification: all embellishments are purely cosmetic — verify by launching the app
- Regression: ensure drag-and-drop still works with new tab structure
- Color persistence: verify project colorIndex survives save/load cycle
- Activity state transitions: verify working → justFinished → idle timer works
- Light/dark mode: verify all new colors work in both appearances
