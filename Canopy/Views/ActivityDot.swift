import SwiftUI

/// Animated activity indicator with project-colored ring and center status dot.
struct ActivityDot: View {
    let activity: SessionActivity
    var projectColor: Color = .gray

    @State private var isSpinning = false
    /// Separate from isSpinning: sharing one flag let a working → needsInput
    /// transition deliver the spinner's onDisappear AFTER the ring's onAppear,
    /// leaving no value change to drive repeatForever and freezing both.
    @State private var isPulsing = false

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

            // Pulsing amber ring: a blocked session must be findable at a
            // glance across eight tabs, and must not look like the blue
            // checkmark of a finished one.
            if activity == .needsInput {
                Circle()
                    .stroke(Color.orange, lineWidth: 1.5)
                    .frame(width: 12, height: 12)
                    .opacity(isPulsing ? 0.35 : 1.0)
                    .animation(
                        .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                        value: isPulsing
                    )
                    .onAppear { isPulsing = true }
                    .onDisappear { isPulsing = false }
            }

            // Glow for justFinished
            if activity == .justFinished {
                Circle()
                    .fill(Color.blue.opacity(0.3))
                    .frame(width: 14, height: 14)
                    .blur(radius: 4)
            }

            // Center dot, checkmark, or raised hand
            if activity == .justFinished {
                Image(systemName: "checkmark")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(.blue)
            } else if activity == .needsInput {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(.orange)
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
        case .needsInput: return 0.0
        case .justFinished: return 0.0
        }
    }

    private var centerColor: Color {
        switch activity {
        case .idle: return .gray
        case .working: return .green
        case .needsInput: return .orange
        case .justFinished: return .blue
        }
    }

    private var centerOpacity: Double {
        switch activity {
        case .idle: return 0.4
        case .working: return 1.0
        case .needsInput: return 1.0
        case .justFinished: return 1.0
        }
    }
}
