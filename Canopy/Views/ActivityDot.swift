import SwiftUI

/// Animated activity indicator for session status.
struct ActivityDot: View {
    let activity: SessionActivity

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let phase = phase(for: timeline.date)

            ZStack {
                if activity == .working {
                    Circle()
                        .fill(Color.green.opacity(0.3 * phase))
                        .frame(width: 14, height: 14)
                        .blur(radius: 4)

                    Circle()
                        .fill(Color.green.opacity(0.5 * phase))
                        .frame(width: 10, height: 10)
                        .blur(radius: 2)
                }

                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                    .opacity(activity == .idle ? 0.35 : (0.7 + 0.3 * phase))
            }
            .frame(width: 14, height: 14)
            .help(activity.label)
        }
    }

    private var color: Color {
        switch activity {
        case .idle: return .gray
        case .working: return .green
        }
    }

    private func phase(for date: Date) -> Double {
        switch activity {
        case .idle: return 0
        case .working: return 0.5 + 0.5 * sin(date.timeIntervalSinceReferenceDate * 2.0 * .pi / 1.5)
        }
    }
}
