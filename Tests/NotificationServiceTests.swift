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

    // MARK: - routeResponseUserInfo

    @Test func routeResponsePostsSelectSessionForValidId() async {
        let id = UUID()
        let received = await withCheckedContinuation { (cont: CheckedContinuation<UUID?, Never>) in
            let observer = NotificationCenter.default.addObserver(
                forName: .canopySelectSession,
                object: nil,
                queue: .main
            ) { note in
                cont.resume(returning: note.userInfo?["sessionId"] as? UUID)
            }
            NotificationService.routeResponseUserInfo(["sessionId": id.uuidString])
            // Observer removal happens after resume; schedule via main after a tick.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NotificationCenter.default.removeObserver(observer)
            }
        }
        #expect(received == id)
    }

    @Test func routeResponseIgnoresMissingSessionId() {
        var fired = false
        let observer = NotificationCenter.default.addObserver(
            forName: .canopySelectSession,
            object: nil,
            queue: .main
        ) { _ in fired = true }
        defer { NotificationCenter.default.removeObserver(observer) }

        NotificationService.routeResponseUserInfo([:])
        NotificationService.routeResponseUserInfo(["other": "value"])
        #expect(fired == false)
    }

    @Test func routeResponseIgnoresMalformedSessionId() {
        var fired = false
        let observer = NotificationCenter.default.addObserver(
            forName: .canopySelectSession,
            object: nil,
            queue: .main
        ) { _ in fired = true }
        defer { NotificationCenter.default.removeObserver(observer) }

        NotificationService.routeResponseUserInfo(["sessionId": "not-a-uuid"])
        #expect(fired == false)
    }

    // Note: we can't instantiate NotificationService.shared under `swift test` —
    // UNUserNotificationCenter.current() requires a bundled app and crashes
    // otherwise. The post methods are therefore only exercised via the real app.

    /// "Session finished" for a permission prompt is actively misleading:
    /// nothing finished, the agent is stalled and stays stalled.
    @Test func needsInputNotificationBodyDiffersFromFinished() {
        let id = UUID()
        let finished = NotificationService.makeContent(title: "p", subtitle: "s", sessionId: id)
        let needsInput = NotificationService.makeContent(
            title: "p", subtitle: "s", sessionId: id,
            body: NotificationService.needsInputBody
        )
        #expect(finished.body == NotificationService.finishedBody)
        #expect(needsInput.body != finished.body)
    }

    /// Routing must be identical so clicking either notification selects the
    /// same session.
    @Test func needsInputNotificationRoutesToSession() {
        let id = UUID()
        let content = NotificationService.makeContent(
            title: "p", subtitle: "s", sessionId: id,
            body: NotificationService.needsInputBody
        )
        #expect(content.threadIdentifier == id.uuidString)
        #expect(content.userInfo["sessionId"] as? String == id.uuidString)
    }

}
