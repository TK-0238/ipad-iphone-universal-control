import XCTest
import Combine
@testable import MouseLink

@MainActor
final class EdgeSwitchControllerTests: XCTestCase {
    private var time: TimeInterval = 0
    private var epoch: UInt64 = 1
    private var allowed = true
    private var released = true
    private var starts = 0
    private func model() -> EdgeSwitchController {
        EdgeSwitchController(context: { side in EdgeHandoffContext(peer: "A", epoch: self.epoch, side: side) },
            allowed: { self.allowed }, buttonsReleased: { self.released }, start: { self.starts += 1 },
            clock: { self.time }, ticks: Empty<Date,Never>().eraseToAnyPublisher())
    }
    private func visit(_ m: EdgeSwitchController) {
        m.hover(EdgePointer(x:400,y:300,width:800,height:600))
        time += 0.1; m.hover(EdgePointer(x:795,y:300,width:800,height:600))
        for _ in 0..<8 { time += 0.1; m.poll() }
    }
    func testArmDoesNotStartOrReusePointer() { let m = model(); m.arm(); XCTAssertEqual(starts,0); XCTAssertTrue(m.isArmed) }
    func testIntentionalDwellStartsExactlyOnce() { let m = model(); m.arm(); visit(m); XCTAssertEqual(starts,1); visit(m); XCTAssertEqual(starts,1) }
    func testOfflineCannotArm() { allowed = false; let m = model(); m.arm(); visit(m); XCTAssertFalse(m.isArmed); XCTAssertEqual(starts,0) }
    func testModalDisarmPreventsTrigger() { let m = model(); m.arm(); m.disarm(); visit(m); XCTAssertEqual(starts,0) }
    func testReceiverEpochChangePreventsTrigger() { let m = model(); m.arm(); epoch += 1; visit(m); XCTAssertEqual(starts,0); XCTAssertFalse(m.isArmed) }
    func testPlacementChangeDisarms() { let m = model(); m.arm(); m.setPlacement(.left); visit(m); XCTAssertFalse(m.isArmed); XCTAssertEqual(starts,0) }
    func testButtonsHeldPreventsTrigger() { released = false; let m = model(); m.arm(); visit(m); XCTAssertEqual(starts,0) }
    func testLostForegroundCannotTriggerOnTimer() { let m = model(); m.arm(); allowed = false; visit(m); XCTAssertFalse(m.isArmed); XCTAssertEqual(starts,0) }
    func testLeavingWindowCancelsPendingDwell() {
        let m = model(); m.arm(); m.hover(EdgePointer(x:400,y:300,width:800,height:600))
        time += 0.1; m.hover(EdgePointer(x:795,y:300,width:800,height:600)); m.hover(nil)
        for _ in 0..<10 { time += 0.1; m.poll() }; XCTAssertEqual(starts,0); XCTAssertEqual(m.progress,0)
    }
}
