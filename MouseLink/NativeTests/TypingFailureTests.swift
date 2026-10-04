import XCTest
import Combine
@testable import MouseLink

@MainActor
private final class FaultSender: KeyboardSending {
    var inputEpoch: UInt64 = 0
    var keyboardReceivers: Set<UUID> = []
    var writes: [(UUID, Data)] = []
    var response: KeyboardSendResult = .accepted
    var disconnectCount = 0
    func sendKeyboardBytes(_ bytes: Data, to peer: UUID) -> KeyboardSendResult {
        if response == .accepted { writes.append((peer, bytes)) }
        return response
    }
    func hardDisconnect() { disconnectCount += 1; inputEpoch &+= 1; keyboardReceivers = [] }
}

@MainActor
final class TypingFailureTests: XCTestCase {
    private var now: TimeInterval = 1
    private func model() -> (TypingSession, FaultSender, UUID) {
        let sender = FaultSender(); let peer = UUID(); sender.keyboardReceivers = [peer]
        let session = TypingSession(sender: sender, clock: { self.now }, ticks: Empty<Date, Never>().eraseToAnyPublisher())
        session.open(peer: peer)
        return (session, sender, peer)
    }
    private func advance(_ session: TypingSession, count: Int = 100) {
        for _ in 0..<count { now += 0.021; session.pump() }
    }
    func testSameUUIDReconnectBetweenTicksNeverReceivesOldEnter() {
        let (session, sender, peer) = model()
        session.draft = "ab"; session.sendDraft(enter: true)
        advance(session, count: 1)
        // Subscription loss and reappearance can occur before the next 20ms timer tick.
        sender.keyboardReceivers = []; sender.inputEpoch &+= 1; sender.keyboardReceivers = [peer]
        let before = sender.writes.count
        advance(session)
        XCTAssertFalse(session.isSending)
        XCTAssertTrue(sender.writes.dropFirst(before).isEmpty, "Old transaction must not even release keys onto a new connection")
        XCTAssertFalse(sender.writes.contains { $0.1 == KeyboardStroke.enter.data })
    }
    func testCancelAfterReconnectDoesNotReleaseIntoNewConnection() {
        let (session, sender, _) = model()
        session.sendKey(.enter); advance(session, count: 1)
        sender.inputEpoch &+= 1
        let before = sender.writes.count
        session.cancel()
        XCTAssertEqual(sender.writes.count, before)
        XCTAssertFalse(session.isSending)
    }
    func testExplicitNewSubmitAfterReconnectStillWorks() {
        let (session, sender, peer) = model()
        sender.inputEpoch &+= 1
        session.sendKey(.enter); advance(session)
        XCTAssertEqual(sender.writes.map { $0.1 }, [.init(repeating: 0, count: 8), KeyboardStroke.enter.data, .init(repeating: 0, count: 8)])
        XCTAssertTrue(sender.writes.allSatisfy { $0.0 == peer })
    }
    func testRepeatedSubmitCannotReplaceInFlightText() {
        let (session, sender, _) = model()
        session.draft = "aa"; session.sendDraft(enter: false)
        session.sendKey(.enter); advance(session)
        XCTAssertFalse(sender.writes.contains { $0.1 == KeyboardStroke.enter.data })
        XCTAssertEqual(sender.writes.filter { $0.1 == KeyboardStroke(usage: 4).data }.count, 2)
    }
    func testUnavailableAfterKeyDownDiscardsRemainingEnter() {
        let (session, sender, _) = model()
        session.draft = "ab"; session.sendDraft(enter: true); advance(session, count: 1)
        sender.response = .unavailable; advance(session)
        XCTAssertFalse(session.isSending); XCTAssertEqual(sender.disconnectCount, 1)
        XCTAssertFalse(sender.writes.contains { $0.1 == KeyboardStroke.enter.data })
    }
    func testNoSendWhileClosedOrBackgrounded() {
        let (session, sender, _) = model(); session.close()
        session.draft = "a"; session.sendDraft(enter: true); session.sendCharacter("a"); session.sendKey(.enter)
        advance(session); XCTAssertTrue(sender.writes.isEmpty)
    }
    func testMaximumDraftPressurePreservesEveryKeyAndSingleEnter() {
        let (session, sender, peer) = model(); session.draft = String(repeating: "A", count: 256)
        session.sendDraft(enter: true)
        for step in 0..<2500 {
            now += 0.011; sender.response = step % 7 == 0 ? .busy : .accepted; session.pump()
        }
        XCTAssertFalse(session.isSending)
        XCTAssertEqual(sender.writes.filter { $0.1 == KeyboardStroke(usage: 4, modifiers: 2).data }.count, 256)
        XCTAssertEqual(sender.writes.filter { $0.1 == KeyboardStroke.enter.data }.count, 1)
        XCTAssertTrue(sender.writes.allSatisfy { $0.0 == peer })
    }
    func testAllUnsupportedDraftsAreAtomicWithEnterRequested() {
        for draft in ["ok\n", "ok\t", "hello😀", "日本", String(repeating: "a", count: 257)] {
            let (session, sender, _) = model(); session.draft = draft; session.sendDraft(enter: true)
            XCTAssertTrue(sender.writes.isEmpty); XCTAssertFalse(session.isSending); XCTAssertNotNil(session.validation)
        }
    }
    func testPartialSendThenCancelLeavesOnlyRelease() {
        for prefix in 0..<6 {
            let (session, sender, _) = model(); session.draft = "abcd"; session.sendDraft(enter: true)
            advance(session, count: prefix); session.cancel(); let count = sender.writes.count; advance(session)
            XCTAssertEqual(sender.writes.count, count); XCTAssertEqual(sender.writes.last?.1, KeyboardStroke.zero.data)
            XCTAssertFalse(sender.writes.contains { $0.1 == KeyboardStroke.enter.data })
        }
    }
}
