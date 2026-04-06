# Tab Sorting & Drag-and-Drop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add persistent tab sorting (by name, project, creation date, directory) and manual drag-and-drop reordering to the tab bar and sidebar.

**Architecture:** Add a `TabSortMode` enum and `tabSortMode` property to `AppState`, with a computed `orderedSessions` that all views read. Drag-and-drop in the tab bar uses `draggable()`/`dropDestination()` with swap animation; the sidebar uses `.onMove`. Dragging reverts sort mode to `.manual`. Sort controls appear in both the tab bar and the app's menu bar.

**Tech Stack:** Swift 6.0, SwiftUI (macOS 14+), Swift Testing

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `Tempo/App/AppState.swift` | Modify | Add `TabSortMode` enum, `tabSortMode` property, `orderedSessions` computed property, `moveSession(fromIndex:toIndex:)`, sorted insertion logic |
| `Tempo/Views/SessionTabBar.swift` | Modify | Add `draggable()`/`dropDestination()` to tabs, add sort menu button next to `+` |
| `Tempo/Views/Sidebar.swift` | Modify | Add `.onMove` to session `ForEach` lists, use `orderedSessions` for ordering within groups |
| `Tempo/App/TempoApp.swift` | Modify | Add `CommandMenu("Tabs")` with sort mode picker |
| `Tests/AppStateTests.swift` | Modify | Add tests for sorting, ordering, and mode switching |

---

### Task 1: TabSortMode Enum and orderedSessions

**Files:**
- Modify: `Tempo/App/AppState.swift`
- Modify: `Tests/AppStateTests.swift`

- [ ] **Step 1: Write failing tests for TabSortMode and orderedSessions**

Add to `Tests/AppStateTests.swift`:

```swift
// MARK: - Tab Sorting

@Test @MainActor func defaultSortModeIsManual() {
    let state = AppState()
    #expect(state.tabSortMode == .manual)
}

@Test @MainActor func orderedSessionsManualReturnsInsertionOrder() {
    let state = AppState()
    state.createSession(name: "Zebra", directory: "/tmp/z")
    state.createSession(name: "Apple", directory: "/tmp/a")
    state.createSession(name: "Mango", directory: "/tmp/m")

    #expect(state.orderedSessions.map(\.name) == ["Zebra", "Apple", "Mango"])
}

@Test @MainActor func orderedSessionsSortedByName() {
    let state = AppState()
    state.createSession(name: "Zebra", directory: "/tmp/z")
    state.createSession(name: "Apple", directory: "/tmp/a")
    state.createSession(name: "Mango", directory: "/tmp/m")
    state.tabSortMode = .name

    #expect(state.orderedSessions.map(\.name) == ["Apple", "Mango", "Zebra"])
}

@Test @MainActor func orderedSessionsSortedByCreationDate() {
    let state = AppState()
    state.createSession(name: "First", directory: "/tmp/1")
    state.createSession(name: "Second", directory: "/tmp/2")
    state.createSession(name: "Third", directory: "/tmp/3")
    state.tabSortMode = .creationDate

    // Creation order is oldest first
    #expect(state.orderedSessions.map(\.name) == ["First", "Second", "Third"])
}

@Test @MainActor func orderedSessionsSortedByDirectory() {
    let state = AppState()
    state.createSession(name: "C", directory: "/tmp/zebra")
    state.createSession(name: "A", directory: "/tmp/apple")
    state.createSession(name: "B", directory: "/tmp/mango")
    state.tabSortMode = .workingDirectory

    #expect(state.orderedSessions.map(\.name) == ["A", "B", "C"])
}

@Test @MainActor func orderedSessionsSortedByProject() {
    let state = AppState()
    let projectA = Project(name: "Alpha", repositoryPath: "/tmp/alpha")
    let projectB = Project(name: "Beta", repositoryPath: "/tmp/beta")
    state.addProject(projectA)
    state.addProject(projectB)

    // Create sessions with project associations
    let s1 = SessionInfo(name: "B-session", workingDirectory: "/tmp/b", projectId: projectB.id)
    let s2 = SessionInfo(name: "A-session", workingDirectory: "/tmp/a", projectId: projectA.id)
    let s3 = SessionInfo(name: "Plain", workingDirectory: "/tmp/p")
    state.sessions = [s1, s2, s3]

    state.tabSortMode = .project

    let names = state.orderedSessions.map(\.name)
    // Alpha project first, then Beta, then ungrouped
    #expect(names == ["A-session", "B-session", "Plain"])
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter TempoTests 2>&1 | tail -20`
Expected: Compilation errors — `tabSortMode` and `orderedSessions` don't exist yet.

- [ ] **Step 3: Implement TabSortMode and orderedSessions**

In `Tempo/App/AppState.swift`, add the enum before the `AppState` class:

```swift
/// Controls how tabs are ordered in the tab bar and sidebar.
enum TabSortMode: String, CaseIterable {
    case manual = "Manual"
    case name = "Name"
    case project = "Project"
    case creationDate = "Creation Date"
    case workingDirectory = "Directory"
}
```

Inside `AppState`, add after the existing `@Published` properties:

```swift
@Published var tabSortMode: TabSortMode = .manual
```

Add the computed property after `activeSession`:

```swift
var orderedSessions: [SessionInfo] {
    switch tabSortMode {
    case .manual:
        return sessions
    case .name:
        return sessions.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    case .creationDate:
        return sessions.sorted { $0.createdAt < $1.createdAt }
    case .workingDirectory:
        return sessions.sorted { $0.workingDirectory.localizedCaseInsensitiveCompare($1.workingDirectory) == .orderedAscending }
    case .project:
        return sessions.sorted { a, b in
            let aProject = projects.first { $0.id == a.projectId }
            let bProject = projects.first { $0.id == b.projectId }
            let aName = aProject?.name ?? "\u{FFFF}" // ungrouped sorts last
            let bName = bProject?.name ?? "\u{FFFF}"
            if aName != bName { return aName.localizedCaseInsensitiveCompare(bName) == .orderedAscending }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter TempoTests 2>&1 | tail -20`
Expected: All new sorting tests pass.

- [ ] **Step 5: Commit**

```bash
git add Tempo/App/AppState.swift Tests/AppStateTests.swift
git commit -m "feat: add TabSortMode enum and orderedSessions computed property"
```

---

### Task 2: Sorted Insertion for New Sessions

**Files:**
- Modify: `Tempo/App/AppState.swift`
- Modify: `Tests/AppStateTests.swift`

- [ ] **Step 1: Write failing test for sorted insertion**

Add to `Tests/AppStateTests.swift`:

```swift
@Test @MainActor func newSessionInsertedInSortedPosition() {
    let state = AppState()
    state.createSession(name: "Apple", directory: "/tmp/a")
    state.createSession(name: "Cherry", directory: "/tmp/c")
    state.tabSortMode = .name

    state.createSession(name: "Banana", directory: "/tmp/b")

    // In manual mode the underlying array has Banana in sorted position
    #expect(state.sessions.map(\.name) == ["Apple", "Banana", "Cherry"])
}

@Test @MainActor func newSessionAppendsInManualMode() {
    let state = AppState()
    state.createSession(name: "Apple", directory: "/tmp/a")
    state.createSession(name: "Cherry", directory: "/tmp/c")
    state.tabSortMode = .manual

    state.createSession(name: "Banana", directory: "/tmp/b")

    #expect(state.sessions.map(\.name) == ["Apple", "Cherry", "Banana"])
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter TempoTests 2>&1 | tail -20`
Expected: `newSessionInsertedInSortedPosition` fails — Banana is appended, not inserted.

- [ ] **Step 3: Implement sorted insertion**

In `Tempo/App/AppState.swift`, modify the `createSession` method. Replace `sessions.append(session)` with:

```swift
if tabSortMode == .manual {
    sessions.append(session)
} else {
    // Insert in sorted position by re-sorting the array
    sessions.append(session)
    sessions = orderedSessions
}
```

Apply the same pattern in `createWorktreeSession`. Replace `sessions.append(session)` (line 165) with:

```swift
if tabSortMode == .manual {
    sessions.append(session)
} else {
    sessions.append(session)
    sessions = orderedSessions
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter TempoTests 2>&1 | tail -20`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add Tempo/App/AppState.swift Tests/AppStateTests.swift
git commit -m "feat: insert new sessions in sorted position when sort mode is active"
```

---

### Task 3: Move Session Helper and Sort-Mode Revert

**Files:**
- Modify: `Tempo/App/AppState.swift`
- Modify: `Tests/AppStateTests.swift`

- [ ] **Step 1: Write failing tests**

Add to `Tests/AppStateTests.swift`:

```swift
@Test @MainActor func moveSession() {
    let state = AppState()
    state.createSession(name: "A", directory: "/tmp/a")
    state.createSession(name: "B", directory: "/tmp/b")
    state.createSession(name: "C", directory: "/tmp/c")

    state.moveSession(from: IndexSet(integer: 2), to: 0)

    #expect(state.sessions.map(\.name) == ["C", "A", "B"])
}

@Test @MainActor func moveSessionRevertsSortMode() {
    let state = AppState()
    state.createSession(name: "A", directory: "/tmp/a")
    state.createSession(name: "B", directory: "/tmp/b")
    state.tabSortMode = .name

    state.moveSession(from: IndexSet(integer: 1), to: 0)

    #expect(state.tabSortMode == .manual)
}

@Test @MainActor func swapSessions() {
    let state = AppState()
    state.createSession(name: "A", directory: "/tmp/a")
    state.createSession(name: "B", directory: "/tmp/b")
    state.createSession(name: "C", directory: "/tmp/c")
    let idA = state.sessions[0].id
    let idC = state.sessions[2].id

    state.swapSessions(idA, idC)

    #expect(state.sessions.map(\.name) == ["C", "B", "A"])
}

@Test @MainActor func swapSessionsRevertsSortMode() {
    let state = AppState()
    state.createSession(name: "A", directory: "/tmp/a")
    state.createSession(name: "B", directory: "/tmp/b")
    state.tabSortMode = .name
    let idA = state.sessions[0].id
    let idB = state.sessions[1].id

    state.swapSessions(idA, idB)

    #expect(state.tabSortMode == .manual)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter TempoTests 2>&1 | tail -20`
Expected: Compilation errors — `moveSession` and `swapSessions` don't exist.

- [ ] **Step 3: Implement moveSession and swapSessions**

In `Tempo/App/AppState.swift`, add after `renameSession`:

```swift
/// Moves sessions using IndexSet (for sidebar .onMove).
func moveSession(from source: IndexSet, to destination: Int) {
    sessions.move(fromOffsets: source, toOffset: destination)
    tabSortMode = .manual
}

/// Swaps two sessions by ID (for tab bar drag-and-drop).
func swapSessions(_ idA: UUID, _ idB: UUID) {
    guard let indexA = sessions.firstIndex(where: { $0.id == idA }),
          let indexB = sessions.firstIndex(where: { $0.id == idB }),
          indexA != indexB else { return }
    sessions.swapAt(indexA, indexB)
    tabSortMode = .manual
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter TempoTests 2>&1 | tail -20`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add Tempo/App/AppState.swift Tests/AppStateTests.swift
git commit -m "feat: add moveSession and swapSessions with sort mode revert"
```

---

### Task 4: Tab Bar Sort Menu

**Files:**
- Modify: `Tempo/Views/SessionTabBar.swift`

- [ ] **Step 1: Add sort menu button to SessionTabBar**

In `Tempo/Views/SessionTabBar.swift`, inside the `SessionTabBar` body, add a sort menu between the `Spacer()` and the new session button:

```swift
HStack(spacing: 0) {
    ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 1) {
            ForEach(appState.sessions) { session in
                SessionTab(
                    session: session,
                    isActive: session.id == appState.activeSessionId,
                    onSelect: { appState.activeSessionId = session.id },
                    onClose: { appState.closeSession(id: session.id) }
                )
            }
        }
    }

    Spacer()

    // Sort menu
    Menu {
        Picker("Sort By", selection: $appState.tabSortMode) {
            ForEach(TabSortMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
    } label: {
        Image(systemName: "arrow.up.arrow.down")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(appState.tabSortMode == .manual ? .secondary : .accentColor)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .help("Sort tabs")

    // New session button
    Button(action: { appState.createSessionWithPicker() }) {
        Image(systemName: "plus")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help("New Session (⌘T)")
}
.padding(.horizontal, 8)
.frame(height: 36)
.background(.bar)
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Tempo/Views/SessionTabBar.swift
git commit -m "feat: add sort mode picker menu to tab bar"
```

---

### Task 5: Tab Bar Drag and Drop

**Files:**
- Modify: `Tempo/Views/SessionTabBar.swift`

- [ ] **Step 1: Update SessionTabBar to use orderedSessions and add drag-and-drop**

In `Tempo/Views/SessionTabBar.swift`, replace the entire `SessionTabBar` struct with:

```swift
struct SessionTabBar: View {
    @EnvironmentObject var appState: AppState
    @State private var draggingSessionId: UUID?

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(appState.orderedSessions) { session in
                        SessionTab(
                            session: session,
                            isActive: session.id == appState.activeSessionId,
                            onSelect: { appState.activeSessionId = session.id },
                            onClose: { appState.closeSession(id: session.id) }
                        )
                        .opacity(draggingSessionId == session.id ? 0.5 : 1.0)
                        .draggable(session.id.uuidString) {
                            // Drag preview
                            Text(session.name)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 6).fill(.bar))
                        }
                        .dropDestination(for: String.self) { items, _ in
                            guard let droppedIdString = items.first,
                                  let droppedId = UUID(uuidString: droppedIdString) else { return false }
                            withAnimation(.easeInOut(duration: 0.2)) {
                                appState.swapSessions(droppedId, session.id)
                            }
                            return true
                        } isTargeted: { isTargeted in
                            if isTargeted {
                                draggingSessionId = draggingSessionId // keep current
                            }
                        }
                    }
                }
            }

            Spacer()

            // Sort menu
            Menu {
                Picker("Sort By", selection: $appState.tabSortMode) {
                    ForEach(TabSortMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(appState.tabSortMode == .manual ? .secondary : .accentColor)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Sort tabs")

            // New session button
            Button(action: { appState.createSessionWithPicker() }) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New Session (⌘T)")
        }
        .padding(.horizontal, 8)
        .frame(height: 36)
        .background(.bar)
    }
}
```

Also update `SessionTab` to track the drag state via `onDrag`:

```swift
struct SessionTab: View {
    let session: SessionInfo
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isActive ? Color.green : Color.gray.opacity(0.4))
                .frame(width: 6, height: 6)

            Text(session.name)
                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                .lineLimit(1)

            if isHovering || isActive {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 16, height: 16)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color.accentColor.opacity(0.15) : (isHovering ? Color.gray.opacity(0.1) : Color.clear))
        )
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Tempo/Views/SessionTabBar.swift
git commit -m "feat: add drag-and-drop tab reordering with swap animation"
```

---

### Task 6: Sidebar Reordering with .onMove

**Files:**
- Modify: `Tempo/Views/Sidebar.swift`

- [ ] **Step 1: Update Sidebar to use ordered sessions and add .onMove**

In `Tempo/Views/Sidebar.swift`, update the `plainSessions` computed property to use `orderedSessions`:

```swift
private var plainSessions: [SessionInfo] {
    appState.orderedSessions.filter { $0.projectId == nil }
}
```

Update the plain sessions section in the `body` to add `.onMove`:

```swift
if !plainSessions.isEmpty {
    Section("Sessions") {
        ForEach(plainSessions) { session in
            sessionRow(session)
        }
        .onMove { source, destination in
            appState.moveSession(from: source, to: destination)
        }
    }
}
```

Update the `projectSection` method to use `orderedSessions` for filtering and add `.onMove`:

```swift
@ViewBuilder
private func projectSection(_ project: Project) -> some View {
    let sessions = appState.orderedSessions.filter { $0.projectId == project.id }

    Section(isExpanded: appState.projectExpandedBinding(for: project.id)) {
        if sessions.isEmpty {
            Text("No sessions")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.vertical, 2)
        } else {
            ForEach(sessions) { session in
                sessionRow(session)
            }
            .onMove { source, destination in
                appState.moveSession(from: source, to: destination)
            }
        }
    } header: {
        HStack(spacing: 5) {
            Image(systemName: "folder.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            Text(project.name)
                .font(.system(size: 12, weight: .medium))
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            appState.activeSessionId = nil
            appState.selectedProjectId = project.id
        }
        .contextMenu { projectContextMenu(project) }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Tempo/Views/Sidebar.swift
git commit -m "feat: add .onMove reordering to sidebar session lists"
```

---

### Task 7: Menu Bar Sort Commands

**Files:**
- Modify: `Tempo/App/TempoApp.swift`

- [ ] **Step 1: Add CommandMenu for tab sorting**

In `Tempo/App/TempoApp.swift`, add a new `CommandMenu` inside the `.commands` block, after the existing `CommandGroup(after: .appSettings)`:

```swift
CommandMenu("Tabs") {
    Picker("Sort By", selection: $appState.tabSortMode) {
        ForEach(TabSortMode.allCases, id: \.self) { mode in
            Text(mode.rawValue).tag(mode)
        }
    }
    .pickerStyle(.inline)

    Divider()

    Button("Cycle Sort Mode") {
        let allCases = TabSortMode.allCases
        let currentIndex = allCases.firstIndex(of: appState.tabSortMode) ?? 0
        let nextIndex = (currentIndex + 1) % allCases.count
        appState.tabSortMode = allCases[nextIndex]
    }
    .keyboardShortcut("s", modifiers: [.command, .shift])
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Tempo/App/TempoApp.swift
git commit -m "feat: add Tabs menu with sort mode picker and keyboard shortcut"
```

---

### Task 8: Final Integration Test

**Files:**
- Modify: `Tests/AppStateTests.swift`

- [ ] **Step 1: Add integration-style tests**

Add to `Tests/AppStateTests.swift`:

```swift
@Test @MainActor func dragRevertsThenNewSessionAppends() {
    let state = AppState()
    state.createSession(name: "Banana", directory: "/tmp/b")
    state.createSession(name: "Apple", directory: "/tmp/a")
    state.tabSortMode = .name

    // orderedSessions is sorted
    #expect(state.orderedSessions.map(\.name) == ["Apple", "Banana"])

    // Swap reverts to manual
    let idA = state.sessions[0].id
    let idB = state.sessions[1].id
    state.swapSessions(idA, idB)
    #expect(state.tabSortMode == .manual)

    // New session appends (manual mode)
    state.createSession(name: "Cherry", directory: "/tmp/c")
    #expect(state.sessions.last?.name == "Cherry")
}

@Test @MainActor func cycleSortModes() {
    let state = AppState()
    let allModes = TabSortMode.allCases
    #expect(allModes.count == 5)
    #expect(allModes[0] == .manual)
    #expect(allModes[1] == .name)
    #expect(allModes[2] == .project)
    #expect(allModes[3] == .creationDate)
    #expect(allModes[4] == .workingDirectory)
}
```

- [ ] **Step 2: Run full test suite**

Run: `swift test 2>&1 | tail -20`
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add Tests/AppStateTests.swift
git commit -m "test: add integration tests for sort mode cycling and drag revert"
```
