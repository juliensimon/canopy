import SwiftUI

/// A horizontal tab bar showing all open sessions with close buttons.
///
/// Modeled after browser tabs: click to switch, X to close, + to create.
/// Each tab shows the session name and a subtle status indicator.
struct SessionTabBar: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
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

            // New session button
            Button(action: { appState.createSession() }) {
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

/// A single tab in the session tab bar.
struct SessionTab: View {
    let session: SessionInfo
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            // Status dot
            Circle()
                .fill(isActive ? Color.green : Color.gray.opacity(0.4))
                .frame(width: 6, height: 6)

            Text(session.name)
                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                .lineLimit(1)

            // Close button (visible on hover or when active)
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
