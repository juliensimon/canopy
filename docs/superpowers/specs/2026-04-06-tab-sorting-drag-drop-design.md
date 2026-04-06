# Tab Sorting & Drag-and-Drop Reordering

**Date:** 2026-04-06
**Status:** Approved

## Overview

Add persistent tab sorting (by name, project, creation date, working directory) and manual drag-and-drop reordering to Tempo's tab bar and sidebar. Sorting is a persistent mode — tabs stay sorted as new sessions are created. Dragging a tab reverts to manual ordering.

## Data Model

### TabSortMode Enum

```swift
enum TabSortMode: String, CaseIterable {
    case manual = "Manual"
    case name = "Name"
    case project = "Project"
    case creationDate = "Creation Date"
    case workingDirectory = "Directory"
}
```

### AppState Changes

- Add `@Published var tabSortMode: TabSortMode = .manual`
- Add computed `var orderedSessions: [SessionInfo]` that returns:
  - `.manual`: the raw `sessions` array as-is
  - `.name`: sorted alphabetically by `session.name`
  - `.project`: sorted by project name (via `projectId` lookup), then by session name within each project
  - `.creationDate`: sorted by `session.createdAt` (oldest first)
  - `.workingDirectory`: sorted alphabetically by `session.workingDirectory`
- All views read `orderedSessions` instead of `sessions` directly
- When `tabSortMode != .manual`, new sessions are inserted in sorted position (not appended)

## Drag and Drop

### Tab Bar (SessionTabBar)

- Uses `draggable()` and `dropDestination()` modifiers (macOS 13+) on each `SessionTab`
- **Swap animation:** when a dragged tab hovers over another, the two swap positions in the `sessions` array with `withAnimation(.easeInOut(duration: 0.2))`
- Dragged tab gets slight opacity reduction during drag
- On drop, `tabSortMode` is set to `.manual` if it wasn't already

### Sidebar

- Uses `.onMove` on the `ForEach` inside the `List` for standard macOS reorder behavior
- On move, `tabSortMode` is set to `.manual` if it wasn't already
- Both tab bar and sidebar mutate the same `sessions` array in `AppState`, staying in sync

### Sort Mode Interaction

- Dragging a tab in either tab bar or sidebar automatically switches `tabSortMode` to `.manual`
- Sort controls update to reflect the mode change

## Sort Controls

### Tab Bar Control

- A compact `Menu` button positioned next to the existing `+` (new session) button
- Icon: `arrow.up.arrow.down`
- Contains a `Picker` with all `TabSortMode` cases, showing a checkmark next to the active mode

### Menu Bar

- A `CommandMenu("Tabs")` added to the app's commands in `TempoApp`
- Lists all sort modes with the current one checked
- Keyboard shortcut `⌘⇧S` to cycle through sort modes

## Sidebar Structure

The sidebar always maintains its current grouped layout regardless of sort mode:

- **Plain sessions** section (sessions with no `projectId`)
- **Project groups** (collapsible sections with worktree sessions nested under their project)

Sort mode affects only the **order within these groups**, not the grouping structure itself. For example, sorting by name reorders sessions alphabetically within the plain sessions list and within each project group independently.

## Components Affected

| File | Changes |
|------|---------|
| `AppState.swift` | Add `TabSortMode` enum, `tabSortMode` property, `orderedSessions` computed property, sorted insertion logic |
| `SessionTabBar.swift` | Add `draggable()`/`dropDestination()` to `SessionTab`, add sort menu button, read `orderedSessions` |
| `Sidebar.swift` | Add `.onMove` to session `ForEach`, read `orderedSessions` for ordering within groups |
| `TempoApp.swift` | Add `CommandMenu("Tabs")` with sort mode picker and keyboard shortcut |

## Edge Cases

- **Single tab:** Drag-and-drop is a no-op. Sort controls still available but have no visible effect.
- **All tabs in one project:** Sort by project groups everything together; name sub-sort applies within.
- **Mixed plain + worktree tabs with sort by project:** Plain sessions appear in their own group, worktree sessions under their project group. Each group sorted internally.
- **Empty state:** Sort controls hidden when no sessions exist (tab bar is already hidden).
