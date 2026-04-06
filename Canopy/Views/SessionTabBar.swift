import SwiftUI

/// A horizontal tab bar showing all open sessions with close buttons.
///
/// Modeled after browser tabs: click to switch, X to close, + to create.
/// Each tab shows the session name and a subtle status indicator.
struct SessionTabBar: View {
    @EnvironmentObject var appState: AppState
    @State private var draggingSessionId: UUID?

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(Array(appState.orderedSessions.enumerated()), id: \.element.id) { index, session in
                        if index > 0 {
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
                    .foregroundStyle(appState.tabSortMode == .manual ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
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

    private func projectColorFor(_ session: SessionInfo) -> Color {
        guard let projectId = session.projectId,
              let project = appState.projects.first(where: { $0.id == projectId }) else {
            return .gray
        }
        return ProjectColor.color(for: project.colorIndex)
    }
}

/// A single tab in the session tab bar.
struct SessionTab: View {
    let session: SessionInfo
    let isActive: Bool
    var activity: SessionActivity = .idle
    let onSelect: () -> Void
    let onClose: () -> Void
    var projectColor: Color = .gray
    var onCopySession: (@MainActor () -> Void)?

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

            // Copy + Close buttons (visible on hover or when active)
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
}

/// Wrapper that observes TerminalSession for live activity updates in tabs.
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
        // Use a dummy session if none exists yet
        self._terminalSession = ObservedObject(wrappedValue: terminalSession ?? TerminalSession(id: session.id, workingDirectory: ""))
        self.onSelect = onSelect
        self.onClose = onClose
        self.projectColor = projectColor
    }

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
}
