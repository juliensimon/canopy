import Testing
import Foundation
import UserNotifications
@testable import Canopy

@Suite("NotificationService")
struct NotificationServiceTests {

    @Test func contentCarriesTitleSubtitleAndBody() {
        let id = UUID()
        let content = NotificationService.makeContent(
            title: "MyProject",
            subtitle: "feature-branch",
            sessionId: id
        )

        #expect(content.title == "MyProject")
        #expect(content.subtitle == "feature-branch")
        #expect(content.body == "Session finished")
    }

    @Test func contentEncodesSessionIdForRoutingAndCoalescing() {
        let id = UUID()
        let content = NotificationService.makeContent(
            title: "P",
            subtitle: "S",
            sessionId: id
        )

        #expect(content.threadIdentifier == id.uuidString)
        #expect(content.userInfo["sessionId"] as? String == id.uuidString)
    }

    @Test func contentRequestsDefaultSound() {
        let content = NotificationService.makeContent(
            title: "P",
            subtitle: "S",
            sessionId: UUID()
        )
        #expect(content.sound != nil)
    }

    @Test func selectSessionNotificationNameIsStable() {
        // Stability matters: AppState observes this name. Renaming the constant
        // without updating the observer would silently break click-to-focus.
        #expect(Notification.Name.canopySelectSession.rawValue == "canopySelectSession")
    }
}
