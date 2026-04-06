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
