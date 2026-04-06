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
