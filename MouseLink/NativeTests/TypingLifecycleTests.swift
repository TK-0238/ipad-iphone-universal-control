// SPDX-License-Identifier: AGPL-3.0-only
import XCTest
import Combine
import UIKit
@testable import MouseLink

@MainActor
private final class LifecycleSender: KeyboardSending {
    var keyboardReceivers: Set<UUID> = []
    var inputEpoch: UInt64 = 0
    var writes: [(UUID, Data)] = []
    var response: KeyboardSendResult = .accepted
    var disconnects = 0
    func sendKeyboardBytes(_ bytes: Data, to peer: UUID) -> KeyboardSendResult {
        if response == .accepted { writes.append((peer, bytes)) }
        return response
    }
    func hardDisconnect() { disconnects += 1; inputEpoch &+= 1; keyboardReceivers = [] }
}

/// Inject UIKit's real notification names while deliberately withholding SwiftUI's
/// setForeground(false). This is an ordering regression, not a radio/device test.
@MainActor
final class TypingLifecycleTests: XCTestCase {
    private var time: TimeInterval = 1
    private func make() -> (TypingSession, LifecycleSender, UUID) {
        let sender = LifecycleSender(), peer = UUID()
        sender.keyboardReceivers = [peer]
        let session = TypingSession(sender: sender, clock: { self.time },
            ticks: Empty<Date, Never>().eraseToAnyPublisher())
        session.open(peer: peer)
        return (session, sender, peer)
    }
    private func advance(_ session: TypingSession, count: Int = 1) {
        for _ in 0..<count { time += 0.021; session.pump() }
    }
    private func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: UIApplication.shared)
    }
    func testWillResignActiveReleasesBeforeNotificationReturns() {
        let (session, sender, peer) = make()
        session.draft = "ab"; session.sendDraft(enter: true); advance(session)
        XCTAssertEqual(sender.writes.last?.1, KeyboardStroke(usage: 4).data)
        post(UIApplication.willResignActiveNotification)
        XCTAssertFalse(session.isSending, "Do not wait for the next SwiftUI render or timer tick")
        XCTAssertEqual(sender.writes.last?.1, KeyboardStroke.zero.data)
        let afterStop = sender.writes.count
        advance(session, count: 20)
        XCTAssertEqual(sender.writes.count, afterStop)
        XCTAssertFalse(sender.writes.contains { $0.1 == KeyboardStroke.enter.data })
        XCTAssertTrue(sender.writes.allSatisfy { $0.0 == peer })
    }
    func testBackgroundNotificationRejectsNewEnterWithoutSwiftUIUpdate() {
        let (session, sender, _) = make()
        post(UIApplication.didEnterBackgroundNotification)
        session.sendKey(.enter); advance(session, count: 10)
        XCTAssertFalse(session.canSend)
        XCTAssertTrue(sender.writes.isEmpty)
    }
    func testReactivationDoesNotResumeCancelledText() {
        let (session, sender, _) = make()
        session.draft = "long"; session.sendDraft(enter: true); advance(session)
        post(UIApplication.willResignActiveNotification)
        let stopped = sender.writes.count
        session.setForeground(true); advance(session, count: 30)
        XCTAssertEqual(sender.writes.count, stopped)
        XCTAssertFalse(sender.writes.contains { $0.1 == KeyboardStroke.enter.data })
        XCTAssertEqual(session.draft, "long", "Draft is preserved locally, never auto-replayed")
    }
    func testDeactivationWithBackpressureTearsDownInsteadOfHoldingAKey() {
        let (session, sender, _) = make()
        session.sendKey(.enter); advance(session)
        XCTAssertEqual(sender.writes.last?.1, KeyboardStroke.enter.data)
        sender.response = .busy
        post(UIApplication.willResignActiveNotification)
        XCTAssertEqual(sender.disconnects, 1)
        XCTAssertFalse(session.isSending)
        sender.response = .accepted; advance(session, count: 20)
        XCTAssertEqual(sender.writes.filter { $0.1 == KeyboardStroke.enter.data }.count, 1)
    }
}
