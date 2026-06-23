import Testing
import Foundation
@testable import Canopy

// @MainActor: AboutView conforms to SwiftUI.View (main-actor isolated), so its
// static constants are main-actor isolated on toolchains without SE-0434's
// implicit-nonisolated relaxation (e.g. CI's Swift). Isolating the suite lets
// the tests read them on every supported toolchain — the same @MainActor
// isolation AppStateTests applies per-test.
@Suite("AboutView privacy statement")
@MainActor
struct AboutViewTests {

    // The strong, defensible claim must be present. This is what users read.
    @Test func headlineMakesZeroCollectionClaim() {
        let headline = AboutView.privacyHeadline.lowercased()
        #expect(headline.contains("zero telemetry"))
        #expect(headline.contains("zero data collection"))
    }

    // WHY this matters: the app does make exactly one outbound request — the
    // update check to GitHub. A bald "nothing leaves your Mac" claim would be
    // falsifiable with a packet sniffer. The detail line MUST disclose that
    // single exception, or the headline becomes a lie. This test fails if a
    // future copy edit tightens the wording and drops the disclosure.
    @Test func detailDisclosesUpdateCheckException() {
        let detail = AboutView.privacyDetail.lowercased()
        #expect(detail.contains("github"))
        #expect(detail.contains("update") || detail.contains("version"))
    }

    // The detail must still affirm the local-first guarantee.
    @Test func detailAffirmsDataStaysLocal() {
        let detail = AboutView.privacyDetail.lowercased()
        #expect(detail.contains("your mac") || detail.contains("your machine"))
    }
}
