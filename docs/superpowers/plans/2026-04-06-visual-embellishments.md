# Visual Embellishments Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 8 visual embellishments to Canopy — project colors, tab bar polish, sidebar hierarchy, activity ring spinner, status bar enhancement, terminal inset, tab crossfade, and empty state upgrade.

**Architecture:** Incremental in-place modifications to existing SwiftUI views. One new file (`ProjectColor.swift`) for the color palette utility. One model change (`colorIndex` on `Project`). All other changes are styling additions to existing views.

**Tech Stack:** Swift 6.0, SwiftUI, macOS 14+

**Spec:** `docs/superpowers/specs/2026-04-06-visual-embellishments-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `Canopy/Utilities/ProjectColor.swift` | Create | Color palette: 8 colors, auto-assign, lookup by index |
| `Canopy/Models/Project.swift` | Modify | Add `colorIndex: Int?` property |
| `Canopy/Services/TerminalSession.swift` | Modify | Add `.justFinished` activity case + transition timer |
| `Canopy/Views/ActivityDot.swift` | Modify | Ring spinner, project color param, justFinished state |
| `Canopy/Views/SessionTabBar.swift` | Modify | Underline, project dots, separators, tab animations |
| `Canopy/Views/Sidebar.swift` | Modify | Color bands, badges, empty state, subtitle tint |
| `Canopy/Views/StatusBar.swift` | Modify | Activity summary with mini dots |
| `Canopy/Views/MainWindow.swift` | Modify | Terminal inset, crossfade, branch overlay, empty state keycaps |
| `Canopy/Views/AddProjectSheet.swift` | Modify | Color picker row |
| `Canopy/Views/EditProjectSheet.swift` | Modify | Color picker row |
| `Canopy/App/AppState.swift` | Modify | Animation wrappers, color auto-assign helper |
| `Tests/ProjectColorTests.swift` | Create | Tests for color palette utility |
| `Tests/ProjectTests.swift` | Modify | Tests for colorIndex persistence |
| `Tests/TerminalSessionTests.swift` | Modify | Tests for justFinished transition |

---

### Task 1: Project Color Utility

**Files:**
- Create: `Canopy/Utilities/ProjectColor.swift`
- Create: `Tests/ProjectColorTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/ProjectColorTests.swift`:

```swift
import Testing
import SwiftUI
@testable import Canopy

@Suite("ProjectColor")
struct ProjectColorTests {

    @Test func paletteHasEightColors() {
        #expect(ProjectColor.allColors.count == 8)
    }

    @Test func colorForIndexReturnsCorrectColor() {
        let first = ProjectColor.color(for: 0)
        let second = ProjectColor.color(for: 1)
        #expect(first != second)
    }

    @Test func colorForIndexWrapsAround() {
        let first = ProjectColor.color(for: 0)
        let wrapped = ProjectColor.color(for: 8)
        #expect(first == wrapped)
    }

    @Test func colorForNilReturnsGray() {
        let color = ProjectColor.color(for: nil)
        #expect(color == Color.gray)
    }

    @Test func nextIndexWithEmptyProjects() {
        let index = ProjectColor.nextIndex(existingIndices: [])
        #expect(index == 0)
    }

    @Test func nextIndexIncrementsMax() {
        let index = ProjectColor.nextIndex(existingIndices: [0, 2, 1])
        #expect(index == 3)
    }

    @Test func nextIndexWrapsAfterSeven() {
        let index = ProjectColor.nextIndex(existingIndices: [5, 6, 7])
        #expect(index == 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ProjectColorTests 2>&1 | tail -20`
Expected: Compilation error — `ProjectColor` not defined

- [ ] **Step 3: Write minimal implementation**

Create `Canopy/Utilities/ProjectColor.swift`:

```swift
import SwiftUI

/// Eight-color palette for distinguishing projects visually.
enum ProjectColor {
    static let allColors: [Color] = [
        Color(.sRGB, red: 0.486, green: 0.416, blue: 0.937), // Purple
        Color(.sRGB, red: 0.165, green: 0.765, blue: 0.635), // Teal
        Color(.sRGB, red: 0.902, green: 0.522, blue: 0.243), // Orange
        Color(.sRGB, red: 0.878, green: 0.365, blue: 0.714), // Pink
        Color(.sRGB, red: 0.231, green: 0.510, blue: 0.965), // Blue
        Color(.sRGB, red: 0.937, green: 0.267, blue: 0.267), // Red
        Color(.sRGB, red: 0.831, green: 0.659, blue: 0.263), // Amber
        Color(.sRGB, red: 0.133, green: 0.773, blue: 0.369), // Green
    ]

    /// Returns the color for a given index, wrapping around the palette.
    /// Returns gray for nil (sessions without a project).
    static func color(for index: Int?) -> Color {
        guard let index else { return .gray }
        return allColors[index % allColors.count]
    }

    /// Returns the next color index to assign, based on existing project indices.
    static func nextIndex(existingIndices: [Int]) -> Int {
        guard let max = existingIndices.max() else { return 0 }
        return (max + 1) % allColors.count
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ProjectColorTests 2>&1 | tail -20`
Expected: All 7 tests pass

- [ ] **Step 5: Commit**

```bash
git add Canopy/Utilities/ProjectColor.swift Tests/ProjectColorTests.swift
git commit -m "feat: add ProjectColor palette utility with 8-color cycling"
```

---

### Task 2: Add colorIndex to Project Model

**Files:**
- Modify: `Canopy/Models/Project.swift:7-88`
- Modify: `Tests/ProjectTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `Tests/ProjectTests.swift` inside the `ProjectTests` suite:

```swift
    @Test func defaultColorIndexIsNil() {
        let project = Project(name: "test", repositoryPath: "/test")
        #expect(project.colorIndex == nil)
    }

    @Test func colorIndexCodableRoundTrip() throws {
        var project = Project(name: "test", repositoryPath: "/test")
        project.colorIndex = 3
        let data = try JSONEncoder().encode(project)
        let decoded = try JSONDecoder().decode(Project.self, from: data)
        #expect(decoded.colorIndex == 3)
    }

    @Test func colorIndexMissingInJsonDecodesToNil() throws {
        // Simulate existing JSON without colorIndex
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","name":"old","repositoryPath":"/old","filesToCopy":[],"symlinkPaths":[],"setupCommands":[]}
        """
        let decoded = try JSONDecoder().decode(Project.self, from: json.data(using: .utf8)!)
        #expect(decoded.colorIndex == nil)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ProjectTests 2>&1 | tail -20`
Expected: Compilation error — `colorIndex` not found on `Project`

- [ ] **Step 3: Write minimal implementation**

In `Canopy/Models/Project.swift`, add the property after `claudeFlags`:

```swift
    /// Color index into ProjectColor palette. Auto-assigned on creation, user-overridable.
    var colorIndex: Int?
```

Add `colorIndex` to the `init(from decoder:)` method, after the `claudeFlags` line:

```swift
        colorIndex = try container.decodeIfPresent(Int.self, forKey: .colorIndex)
```

Add `colorIndex` parameter to the main `init`, after `claudeFlags`:

```swift
        colorIndex: Int? = nil
```

And assign it in the body:

```swift
        self.colorIndex = colorIndex
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ProjectTests 2>&1 | tail -20`
Expected: All tests pass (existing + 3 new)

- [ ] **Step 5: Commit**

```bash
git add Canopy/Models/Project.swift Tests/ProjectTests.swift
git commit -m "feat: add colorIndex property to Project for palette assignment"
```

---

### Task 3: Auto-assign Color in AppState

**Files:**
- Modify: `Canopy/App/AppState.swift:319-325`

- [ ] **Step 1: Modify addProject to auto-assign colorIndex**

In `AppState.swift`, update the `addProject` method:

```swift
    func addProject(_ project: Project) {
        guard !projects.contains(where: { $0.repositoryPath == project.repositoryPath }) else { return }
        var newProject = project
        if newProject.colorIndex == nil {
            newProject.colorIndex = ProjectColor.nextIndex(
                existingIndices: projects.compactMap(\.colorIndex)
            )
        }
        projects.append(newProject)
        expandedProjects.insert(newProject.id)
        saveProjects()
    }
```

- [ ] **Step 2: Build to verify compilation**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Canopy/App/AppState.swift
git commit -m "feat: auto-assign project color on creation"
```

---

### Task 4: Activity Indicator — justFinished State + Ring Spinner

**Files:**
- Modify: `Canopy/Services/TerminalSession.swift:142-151,178-188`
- Modify: `Canopy/Views/ActivityDot.swift:1-47`

- [ ] **Step 1: Add justFinished case to SessionActivity**

In `Canopy/Services/TerminalSession.swift`, update the `SessionActivity` enum (line 178):

```swift
enum SessionActivity: String {
    case idle
    case working
    case justFinished

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .working: return "Working"
        case .justFinished: return "Just Finished"
        }
    }
}
```

- [ ] **Step 2: Add justFinished transition logic**

In `TerminalSession`, add a `justFinishedTimer` property after `idleTimer` (line 25):

```swift
    private var justFinishedTimer: Task<Void, Never>?
```

Replace the `restartIdleTimer` method (lines 142-151):

```swift
    private func restartIdleTimer() {
        idleTimer?.cancel()
        idleTimer = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            if self.activity == .working {
                self.activity = .justFinished
                self.startJustFinishedTimer()
            }
        }
    }

    private func startJustFinishedTimer() {
        justFinishedTimer?.cancel()
        justFinishedTimer = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            if self.activity == .justFinished {
                self.activity = .idle
            }
        }
    }
```

- [ ] **Step 3: Rewrite ActivityDot with ring spinner and project color**

Replace the entire contents of `Canopy/Views/ActivityDot.swift`:

```swift
import SwiftUI

/// Animated activity indicator with project-colored ring and center status dot.
struct ActivityDot: View {
    let activity: SessionActivity
    var projectColor: Color = .gray

    @State private var isSpinning = false

    var body: some View {
        ZStack {
            // Outer ring
            Circle()
                .stroke(projectColor.opacity(ringBaseOpacity), lineWidth: 1.5)
                .frame(width: 12, height: 12)

            // Spinning arc (working state only)
            if activity == .working {
                Circle()
                    .trim(from: 0, to: 0.25)
                    .stroke(projectColor, lineWidth: 1.5)
                    .frame(width: 12, height: 12)
                    .rotationEffect(.degrees(isSpinning ? 360 : 0))
                    .animation(
                        .linear(duration: 1.0).repeatForever(autoreverses: false),
                        value: isSpinning
                    )
                    .onAppear { isSpinning = true }
                    .onDisappear { isSpinning = false }
            }

            // Glow for justFinished
            if activity == .justFinished {
                Circle()
                    .fill(Color.blue.opacity(0.3))
                    .frame(width: 14, height: 14)
                    .blur(radius: 4)
            }

            // Center dot or checkmark
            if activity == .justFinished {
                Image(systemName: "checkmark")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(.blue)
            } else {
                Circle()
                    .fill(centerColor)
                    .frame(width: 5, height: 5)
                    .opacity(centerOpacity)
            }
        }
        .frame(width: 14, height: 14)
        .help(activity.label)
    }

    private var ringBaseOpacity: Double {
        switch activity {
        case .idle: return 0.15
        case .working: return 0.3
        case .justFinished: return 0.0
        }
    }

    private var centerColor: Color {
        switch activity {
        case .idle: return .gray
        case .working: return .green
        case .justFinished: return .blue
        }
    }

    private var centerOpacity: Double {
        switch activity {
        case .idle: return 0.4
        case .working: return 1.0
        case .justFinished: return 1.0
        }
    }
}
```

- [ ] **Step 4: Build to verify compilation**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds

- [ ] **Step 5: Commit**

```bash
git add Canopy/Services/TerminalSession.swift Canopy/Views/ActivityDot.swift
git commit -m "feat: ring spinner activity indicator with justFinished state"
```

---

### Task 5: Tab Bar — Underline, Project Dots, Separators, Animations

**Files:**
- Modify: `Canopy/Views/SessionTabBar.swift:1-171`
- Modify: `Canopy/App/AppState.swift` (animation wrappers)

- [ ] **Step 1: Update SessionTab to accept projectColor and show underline**

In `SessionTabBar.swift`, update the `SessionTab` struct. Replace the entire `SessionTab` body (lines 106-141):

```swift
    var projectColor: Color = .gray

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            // Project color dot (replaces ActivityDot in tabs)
            Circle()
                .fill(projectColor)
                .opacity(activity == .idle ? 0.5 : 1.0)
                .frame(width: 7, height: 7)

            Text(session.name)
                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                .lineLimit(1)

            if isHovering || isActive {
                Button(action: { onCopySession?() }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 14, height: 14)
                .help("Copy session output")

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 14, height: 14)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color.accentColor.opacity(0.10) : (isHovering ? Color.gray.opacity(0.1) : Color.clear))
        )
        .overlay(alignment: .bottom) {
            if isActive {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .padding(.horizontal, 4)
            }
        }
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
    }
```

- [ ] **Step 2: Update LiveSessionTab to pass projectColor**

Update `LiveSessionTab` to accept and pass `projectColor`. Add a property:

```swift
    var projectColor: Color = .gray
```

Pass it in the `body`:

```swift
    var body: some View {
        SessionTab(
            session: session,
            isActive: isActive,
            activity: terminalSession.activity,
            onSelect: onSelect,
            onClose: onClose,
            projectColor: projectColor,
            onCopySession: { terminalSession.copyFullSessionToClipboard() }
        )
    }
```

- [ ] **Step 3: Add tab separators in SessionTabBar**

In `SessionTabBar`, update the `ForEach` inside the `HStack(spacing: 1)` to include separators. Replace the ForEach block (lines 15-52) with:

```swift
                    ForEach(Array(appState.orderedSessions.enumerated()), id: \.element.id) { index, session in
                        if index > 0 {
                            // Separator — hidden adjacent to active tab
                            let prevSession = appState.orderedSessions[index - 1]
                            let hidesSeparator = session.id == appState.activeSessionId || prevSession.id == appState.activeSessionId
                            if !hidesSeparator {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.08))
                                    .frame(width: 1, height: 16)
                            }
                        }

                        let projectColor = projectColorFor(session)

                        LiveSessionTab(
                            session: session,
                            isActive: session.id == appState.activeSessionId,
                            terminalSession: appState.terminalSessions[session.id],
                            onSelect: { appState.activeSessionId = session.id },
                            onClose: { appState.closeSession(id: session.id) },
                            projectColor: projectColor
                        )
                        .opacity(draggingSessionId == session.id ? 0.5 : 1.0)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .opacity.combined(with: .scale(scale: 0.8))
                        ))
                        .draggable(session.id.uuidString) {
                            Text(session.name)
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.accentColor.opacity(0.15))
                                )
                        }
                        .dropDestination(for: String.self) { items, _ in
                            guard let droppedIdString = items.first,
                                  let droppedId = UUID(uuidString: droppedIdString),
                                  droppedId != session.id else { return false }
                            withAnimation {
                                appState.swapSessions(droppedId, session.id)
                            }
                            return true
                        } isTargeted: { _ in }
                        .onDrag {
                            draggingSessionId = session.id
                            return NSItemProvider(object: session.id.uuidString as NSString)
                        }
                    }
```

- [ ] **Step 4: Add projectColorFor helper to SessionTabBar**

Add this private method to the `SessionTabBar` struct:

```swift
    private func projectColorFor(_ session: SessionInfo) -> Color {
        guard let projectId = session.projectId,
              let project = appState.projects.first(where: { $0.id == projectId }) else {
            return .gray
        }
        return ProjectColor.color(for: project.colorIndex)
    }
```

- [ ] **Step 5: Add animation wrappers in AppState**

In `AppState.swift`, wrap the session mutations in `createSession` (line 139-144) and `performCloseSession` (line 267-275) with animation:

In `createSession`, replace:
```swift
        if tabSortMode == .manual {
            sessions.append(session)
        } else {
            sessions.append(session)
            sessions = orderedSessions
        }
```
with:
```swift
        withAnimation(.easeOut(duration: 0.25)) {
            if tabSortMode == .manual {
                sessions.append(session)
            } else {
                sessions.append(session)
                sessions = orderedSessions
            }
        }
```

In `performCloseSession`, wrap the removal:
```swift
    func performCloseSession(id: UUID) {
        terminalSessions[id]?.stop()
        terminalSessions.removeValue(forKey: id)
        withAnimation(.easeOut(duration: 0.25)) {
            sessions.removeAll { $0.id == id }
            if activeSessionId == id {
                activeSessionId = sessions.last?.id
            }
        }
        pendingCloseSessionId = nil
    }
```

Do the same in `createWorktreeSession` (lines 239-244):
```swift
            withAnimation(.easeOut(duration: 0.25)) {
                if tabSortMode == .manual {
                    sessions.append(session)
                } else {
                    sessions.append(session)
                    sessions = orderedSessions
                }
                activeSessionId = session.id
            }
```

- [ ] **Step 6: Update LiveSessionTab init to accept projectColor**

Update the `LiveSessionTab` init signature and property:

```swift
struct LiveSessionTab: View {
    let session: SessionInfo
    let isActive: Bool
    @ObservedObject var terminalSession: TerminalSession
    let onSelect: () -> Void
    let onClose: () -> Void
    var projectColor: Color = .gray

    init(session: SessionInfo, isActive: Bool, terminalSession: TerminalSession?, onSelect: @escaping () -> Void, onClose: @escaping () -> Void, projectColor: Color = .gray) {
        self.session = session
        self.isActive = isActive
        self._terminalSession = ObservedObject(wrappedValue: terminalSession ?? TerminalSession(id: session.id, workingDirectory: ""))
        self.onSelect = onSelect
        self.onClose = onClose
        self.projectColor = projectColor
    }
```

- [ ] **Step 7: Build to verify compilation**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds

- [ ] **Step 8: Commit**

```bash
git add Canopy/Views/SessionTabBar.swift Canopy/App/AppState.swift
git commit -m "feat: tab bar underline, project dots, separators, and animations"
```

---

### Task 6: Sidebar — Color Bands, Badges, Subtitle Tint

**Files:**
- Modify: `Canopy/Views/Sidebar.swift:202-242,306-357`

- [ ] **Step 1: Update projectHeaderView with color band and badge**

In `Sidebar.swift`, replace the `projectHeaderView` method (lines 227-242):

```swift
    @ViewBuilder
    private func projectHeaderView(_ project: Project) -> some View {
        let color = ProjectColor.color(for: project.colorIndex)
        let sessionCount = appState.orderedSessions.filter { $0.projectId == project.id }.count

        HStack(spacing: 5) {
            Image(systemName: "folder.fill")
                .font(.system(size: 11))
                .foregroundStyle(color)
            Text(project.name)
                .font(.system(size: 12, weight: .medium))

            if sessionCount > 0 {
                Text("\(sessionCount)")
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(color.opacity(0.2))
                    )
                    .foregroundStyle(color)
            }

            Spacer()
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(0.05))
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(color.opacity(0.4))
                .frame(width: 2)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            appState.activeSessionId = nil
            appState.selectedProjectId = project.id
        }
        .contextMenu { projectContextMenu(project) }
    }
```

- [ ] **Step 2: Update SidebarSessionRow to accept and use projectColor**

In `Sidebar.swift`, update the `SidebarSessionRow` struct (lines 322-357):

```swift
struct SidebarSessionRow: View {
    let session: SessionInfo
    var activity: SessionActivity = .idle
    var projectColor: Color = .gray

    var body: some View {
        HStack(spacing: 8) {
            ActivityDot(activity: activity, projectColor: projectColor)
                .frame(width: 10)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(session.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(session.isWorktreeSession ? projectColor.opacity(0.7) : .gray)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        if let branch = session.branchName {
            return branch
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var path = session.workingDirectory
        if path.hasPrefix(home) {
            path = "~" + path.dropFirst(home.count)
        }
        return path
    }
}
```

- [ ] **Step 3: Update LiveSessionRow to pass projectColor**

Update `LiveSessionRow` (lines 308-318):

```swift
struct LiveSessionRow: View {
    let session: SessionInfo
    @ObservedObject var terminalSession: TerminalSession
    var projectColor: Color = .gray

    var body: some View {
        SidebarSessionRow(
            session: session,
            activity: terminalSession.activity,
            projectColor: projectColor
        )
    }
}
```

- [ ] **Step 4: Update sessionRow to compute and pass projectColor**

Update the `sessionRow` method (lines 117-139) to pass project color:

```swift
    @ViewBuilder
    private func sessionRow(_ session: SessionInfo) -> some View {
        let color = projectColorFor(session)

        HStack(spacing: 6) {
            if let ts = appState.terminalSessions[session.id] {
                LiveSessionRow(session: session, terminalSession: ts, projectColor: color)
            } else {
                SidebarSessionRow(session: session, projectColor: color)
            }

            Spacer()

            Button(action: { appState.closeSession(id: session.id) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .help("Close session")
        }
        .tag(session.id)
        .contextMenu { sessionContextMenu(session) }
    }
```

- [ ] **Step 5: Add projectColorFor helper to Sidebar**

Add this private method to the `Sidebar` struct:

```swift
    private func projectColorFor(_ session: SessionInfo) -> Color {
        guard let projectId = session.projectId,
              let project = appState.projects.first(where: { $0.id == projectId }) else {
            return .gray
        }
        return ProjectColor.color(for: project.colorIndex)
    }
```

- [ ] **Step 6: Build to verify compilation**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds

- [ ] **Step 7: Commit**

```bash
git add Canopy/Views/Sidebar.swift
git commit -m "feat: sidebar project color bands, session badges, and tinted subtitles"
```

---

### Task 7: Status Bar — Activity Summary

**Files:**
- Modify: `Canopy/Views/StatusBar.swift:1-46`

- [ ] **Step 1: Replace session count with activity summary**

Replace the entire `StatusBar` body:

```swift
struct StatusBar: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            if let session = appState.activeSession {
                HStack(spacing: 4) {
                    Image(systemName: "terminal")
                        .font(.system(size: 10))
                    Text(session.name)
                        .font(.system(size: 11))
                }
                .foregroundStyle(.secondary)

                Divider()
                    .frame(height: 12)

                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                    Text(session.workingDirectory)
                        .font(.system(size: 11))
                        .lineLimit(1)
                }
                .foregroundStyle(.tertiary)
            }

            Spacer()

            // Activity summary with mini dots
            activitySummary
        }
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(.bar)
    }

    @ViewBuilder
    private var activitySummary: some View {
        let sessions = appState.sessions
        let activities: [(UUID, SessionActivity)] = sessions.map { session in
            let activity = appState.terminalSessions[session.id]?.activity ?? .idle
            return (session.id, activity)
        }
        let workingCount = activities.filter { $0.1 == .working }.count
        let totalCount = sessions.count

        HStack(spacing: 4) {
            ForEach(activities, id: \.0) { _, activity in
                Circle()
                    .fill(activity == .working ? Color.green : Color.gray.opacity(0.4))
                    .frame(width: 5, height: 5)
            }

            if totalCount > 0 {
                Text(summaryText(working: workingCount, total: totalCount))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func summaryText(working: Int, total: Int) -> String {
        if working == 0 {
            return "\(total) session\(total == 1 ? "" : "s")"
        } else if working == total {
            return "\(total) working"
        } else {
            return "\(working) working, \(total - working) idle"
        }
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Canopy/Views/StatusBar.swift
git commit -m "feat: status bar activity summary with mini dots"
```

---

### Task 8: Terminal Rounded Inset + Branch Overlay + Crossfade

**Files:**
- Modify: `Canopy/Views/MainWindow.swift:1-138`

- [ ] **Step 1: Add terminal inset and crossfade to SessionView area**

In `MainWindow.swift`, update the `MainWindow` body. Replace the detail content (the `VStack(spacing: 0)` inside `detail:`) with:

```swift
        } detail: {
            VStack(spacing: 0) {
                if !appState.sessions.isEmpty {
                    SessionTabBar()
                    Divider()
                }

                // Content with crossfade
                ZStack {
                    if let activeSession = appState.activeSession {
                        TerminalInsetView(session: activeSession, appState: appState)
                            .id(activeSession.id)
                            .transition(.opacity)
                    } else if let projectId = appState.selectedProjectId,
                              let project = appState.projects.first(where: { $0.id == projectId }) {
                        ProjectDetailView(project: project)
                            .id(project.id)
                    } else {
                        WelcomeView()
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: appState.activeSessionId)
            }
        }
```

- [ ] **Step 2: Create TerminalInsetView wrapper**

Add this new struct to `MainWindow.swift`, after `SessionView`:

```swift
/// Wraps SessionView with a rounded inset container and branch name overlay.
struct TerminalInsetView: View {
    let session: SessionInfo
    @ObservedObject var appState: AppState
    @State private var showBranchLabel = true

    var body: some View {
        ZStack(alignment: .topTrailing) {
            SessionView(
                session: session,
                terminalSession: appState.terminalSession(for: session)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.15), lineWidth: 1)
            )
            .padding(4)

            // Branch name overlay
            if let branch = session.branchName, showBranchLabel {
                Text(branch)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                    .padding(.top, 12)
                    .padding(.trailing, 12)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            showBranchLabel = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                withAnimation(.easeOut(duration: 0.5)) {
                    showBranchLabel = false
                }
            }
        }
    }
}
```

- [ ] **Step 3: Build to verify compilation**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add Canopy/Views/MainWindow.swift
git commit -m "feat: terminal rounded inset, branch overlay, and tab crossfade"
```

---

### Task 9: Empty State Upgrade

**Files:**
- Modify: `Canopy/Views/Sidebar.swift` (sidebar empty state)
- Modify: `Canopy/Views/MainWindow.swift` (`WelcomeView`)

- [ ] **Step 1: Update sidebar empty state**

In `Sidebar.swift`, replace the `emptyState` computed property (lines 287-302):

```swift
    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()

            // Layered card illustration
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(ProjectColor.allColors[0].opacity(0.1))
                    .stroke(ProjectColor.allColors[0].opacity(0.2), lineWidth: 1)
                    .frame(width: 48, height: 36)
                    .rotationEffect(.degrees(-8))

                RoundedRectangle(cornerRadius: 6)
                    .fill(ProjectColor.allColors[4].opacity(0.1))
                    .stroke(ProjectColor.allColors[4].opacity(0.2), lineWidth: 1)
                    .frame(width: 48, height: 36)
                    .rotationEffect(.degrees(4))
                    .offset(x: 8, y: -4)

                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(ProjectColor.allColors[7].opacity(0.15))
                        .stroke(ProjectColor.allColors[7].opacity(0.25), lineWidth: 1)
                    Image(systemName: "play.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(ProjectColor.allColors[7].opacity(0.6))
                }
                .frame(width: 48, height: 36)
                .offset(x: 16, y: -8)
            }
            .frame(width: 80, height: 60)

            Text("No sessions yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Start your first parallel Claude session")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            // Keycap badges
            HStack(spacing: 12) {
                keycapBadge(key: "\u{2318}T", label: "New Session")
                keycapBadge(key: "\u{2318}\u{21E7}P", label: "Add Project")
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func keycapBadge(key: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.08))
                        .stroke(Color.gray.opacity(0.12), lineWidth: 1)
                )
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }
```

- [ ] **Step 2: Update WelcomeView with keycap badges**

In `MainWindow.swift`, replace the `WelcomeView` body:

```swift
struct WelcomeView: View {
    @EnvironmentObject var appState: AppState
    @State private var showHelp = false

    var body: some View {
        VStack(spacing: 16) {
            Text("\u{1F333}")
                .font(.system(size: 56))

            Text("Canopy")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Parallel Claude Code sessions with git worktrees")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                Button(action: { appState.showAddProjectSheet = true }) {
                    HStack(spacing: 6) {
                        Text("Add Project")
                        keycap("\u{2318}\u{21E7}P")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: { appState.createSessionWithPicker() }) {
                    HStack(spacing: 6) {
                        Text("New Session")
                        keycap("\u{2318}T")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button("Getting Started \u{2318}?") {
                    showHelp = true
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .controlSize(.regular)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .sheet(isPresented: $showHelp) {
            HelpView()
        }
    }

    private func keycap(_ key: String) -> some View {
        Text(key)
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.1))
                    .stroke(Color.gray.opacity(0.15), lineWidth: 0.5)
            )
    }
}
```

- [ ] **Step 3: Build to verify compilation**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add Canopy/Views/Sidebar.swift Canopy/Views/MainWindow.swift
git commit -m "feat: upgraded empty state with layered cards and keycap badges"
```

---

### Task 10: Color Picker in Project Sheets

**Files:**
- Modify: `Canopy/Views/AddProjectSheet.swift`
- Modify: `Canopy/Views/EditProjectSheet.swift`

- [ ] **Step 1: Add color picker to AddProjectSheet**

In `AddProjectSheet.swift`, add a state variable after `validationMessage` (line 19):

```swift
    @State private var selectedColorIndex: Int = 0
```

Add a color picker section after the "Project Name" section (after line 63):

```swift
                    // Project color
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Project Color")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        HStack(spacing: 8) {
                            ForEach(0..<ProjectColor.allColors.count, id: \.self) { index in
                                Circle()
                                    .fill(ProjectColor.allColors[index])
                                    .frame(width: 20, height: 20)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.primary, lineWidth: selectedColorIndex == index ? 2 : 0)
                                            .padding(selectedColorIndex == index ? -2 : 0)
                                    )
                                    .onTapGesture { selectedColorIndex = index }
                            }
                        }
                    }
```

Update the `addProject` method to pass the color index. Replace the `let project = Project(...)` call:

```swift
        var project = Project(
            name: projectName,
            repositoryPath: repoPath,
            filesToCopy: parseCommaSeparated(filesToCopy),
            symlinkPaths: parseCommaSeparated(symlinkPaths),
            setupCommands: parseCommaSeparated(setupCommands),
            autoStartClaude: overrideClaude ? autoStartClaude : nil,
            claudeFlags: overrideClaude ? claudeFlags : nil
        )
        project.colorIndex = selectedColorIndex
```

Update `validateRepo` to auto-pick the next color when repo is validated. Inside the `if valid` branch (after line 177):

```swift
                    selectedColorIndex = ProjectColor.nextIndex(
                        existingIndices: appState.projects.compactMap(\.colorIndex)
                    )
```

- [ ] **Step 2: Add color picker to EditProjectSheet**

In `EditProjectSheet.swift`, add a state variable after `claudeFlags` (line 16):

```swift
    @State private var selectedColorIndex: Int
```

Update the `init` to initialize it (add after the `claudeFlags` init, line 26):

```swift
        self._selectedColorIndex = State(initialValue: project.colorIndex ?? 0)
```

Add the color picker section in the body, after the "Project Name" section (after line 54):

```swift
                    // Project color
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Project Color")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        HStack(spacing: 8) {
                            ForEach(0..<ProjectColor.allColors.count, id: \.self) { index in
                                Circle()
                                    .fill(ProjectColor.allColors[index])
                                    .frame(width: 20, height: 20)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.primary, lineWidth: selectedColorIndex == index ? 2 : 0)
                                            .padding(selectedColorIndex == index ? -2 : 0)
                                    )
                                    .onTapGesture { selectedColorIndex = index }
                            }
                        }
                    }
```

Update the `save` method to include color. Add after `updated.claudeFlags = ...` (line 135):

```swift
        updated.colorIndex = selectedColorIndex
```

- [ ] **Step 3: Build to verify compilation**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds

- [ ] **Step 4: Run all tests**

Run: `swift test 2>&1 | tail -20`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add Canopy/Views/AddProjectSheet.swift Canopy/Views/EditProjectSheet.swift
git commit -m "feat: project color picker in add/edit sheets"
```

---

### Task 11: Final Verification

- [ ] **Step 1: Run full test suite**

Run: `swift test 2>&1 | tail -30`
Expected: All tests pass

- [ ] **Step 2: Build the app**

Run: `swift build 2>&1 | tail -10`
Expected: Clean build with no warnings

- [ ] **Step 3: Commit any remaining changes**

```bash
git status
# If any unstaged changes remain, stage and commit them
```
