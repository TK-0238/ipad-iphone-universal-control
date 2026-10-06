import XCTest
import Combine
import UIKit
@testable import MouseLink

@MainActor
private final class StopBoundarySender: PanelMouseSending {
    let peer = UUID()
    var mouseReceivers: Set<UUID> { connected ? [peer] : [] }
    var inputEpoch: UInt64 = 1
    var connected = true
    var writes: [MouseFrame] = []
    var targets: [UUID] = []
    var disconnects = 0
    var nextResult: MouseSendResult = .accepted
    var onWrite: (() -> Void)?
    func sendPanelMouse(_ frame: MouseFrame, to peer: UUID) -> MouseSendResult {
        writes.append(frame); targets.append(peer)
        let result = nextResult; nextResult = .accepted
        let action = onWrite; onWrite = nil; action?()
        return result
    }
    func hardDisconnect() { disconnects += 1; connected = false; inputEpoch &+= 1 }
}

/// Reentrant callbacks/observers are injected; no radio or user device is used.
@MainActor
final class PanelStopReentrancyTests: XCTestCase {
    private func fixture() -> (PanelSession, StopBoundarySender) {
        let sender = StopBoundarySender()
        let model = PanelSession(sender: sender, clock: { 1 },
            ticks: Empty<Date, Never>().eraseToAnyPublisher())
        model.surfaceIsUsable = { true }; model.enable(peer: sender.peer)
        model.move(x: 20, y: 20, width: 300, height: 200); model.buttons(1)
        XCTAssertEqual(sender.writes, [.zero, MouseFrame(buttons: 1)])
        sender.writes = []; sender.targets = []
        return (model, sender)
    }
    private func attemptInput(_ model: PanelSession, _ sender: StopBoundarySender, enable: Bool) {
        if enable { model.enable(peer: sender.peer) }
        model.move(x: 30, y: 30, width: 300, height: 200)
        model.move(x: 35, y: 35, width: 300, height: 200)
        model.buttons(1); model.scroll(1); model.tap(); model.pump()
    }
    func testDisableRejectsReentrantEnableAndInputDuringRelease() {
        let (model, sender) = fixture()
        sender.onWrite = { self.attemptInput(model, sender, enable: true) }
        model.disable(); model.pump()
        XCTAssertEqual(sender.writes, [.zero], "Stop must emit only one release, never a new click")
        XCTAssertFalse(model.isEnabled); XCTAssertFalse(model.isInside)
        XCTAssertEqual(sender.disconnects, 0)
        XCTAssertTrue(sender.targets.allSatisfy { $0 == sender.peer })
    }
    func testLeaveRejectsReleaseCallbackInputButAllowsLaterRealVisit() {
        let (model, sender) = fixture()
        sender.onWrite = { self.attemptInput(model, sender, enable: false) }
        model.leave(); model.pump()
        XCTAssertEqual(sender.writes, [.zero])
        XCTAssertTrue(model.isEnabled, "Leaving the pad alone does not revoke the visible session")
        XCTAssertFalse(model.isInside)
        sender.writes = []
        model.move(x: 50, y: 50, width: 300, height: 200); model.buttons(1); model.buttons(0)
        XCTAssertEqual(sender.writes, [.zero, MouseFrame(buttons: 1), .zero])
    }
    func testReleaseFailureCannotRestartBeforeDisconnect() {
        for result: MouseSendResult in [.busy, .unavailable] {
            let (model, sender) = fixture(); sender.nextResult = result
            sender.onWrite = { self.attemptInput(model, sender, enable: true) }
            model.disable(); model.pump()
            XCTAssertEqual(sender.writes, [.zero])
            XCTAssertEqual(sender.disconnects, 1)
            XCTAssertFalse(model.isEnabled); XCTAssertFalse(model.isInside)
        }
    }
    func testPublishedStopCannotInjectInputBeforeStoredValueChanges() {
        let (model, sender) = fixture(); var attempted = false
        let token = model.objectWillChange.sink {
            guard !attempted else { return }; attempted = true
            self.attemptInput(model, sender, enable: false)
        }
        defer { token.cancel() }
        model.disable(); model.pump()
        XCTAssertTrue(attempted)
        XCTAssertEqual(sender.writes, [.zero])
        XCTAssertFalse(model.isEnabled); XCTAssertFalse(model.isInside)
    }
    func testPublishedLeaveCannotRestartBeforeRelease() {
        let (model, sender) = fixture(); var attempted = false
        let token = model.objectWillChange.sink {
            guard !attempted else { return }; attempted = true
            self.attemptInput(model, sender, enable: false)
        }
        defer { token.cancel() }
        model.leave(); model.pump()
        XCTAssertTrue(attempted)
        XCTAssertEqual(sender.writes, [.zero])
        XCTAssertTrue(model.isEnabled); XCTAssertFalse(model.isInside)
    }
    func testWindowLossDuringLeaveIsNotOverriddenByRestart() {
        let (model, sender) = fixture()
        sender.onWrite = {
            model.setForeground(false)
            self.attemptInput(model, sender, enable: true)
        }
        model.leave(); model.setForeground(true); model.pump()
        XCTAssertEqual(sender.writes, [.zero])
        XCTAssertFalse(model.isEnabled); XCTAssertFalse(model.isInside)
    }
    func testExplicitEnableAfterStopRemainsUsableAndRepeatedStopIsIdempotent() {
        let (model, sender) = fixture(); model.disable(); model.disable(); model.leave()
        XCTAssertEqual(sender.writes, [.zero])
        sender.writes = []
        model.enable(peer: sender.peer)
        XCTAssertTrue(model.isEnabled); XCTAssertTrue(sender.writes.isEmpty)
        model.move(x: 20, y: 20, width: 300, height: 200); model.buttons(1); model.buttons(0)
        XCTAssertEqual(sender.writes, [.zero, MouseFrame(buttons: 1), .zero])
    }
}
