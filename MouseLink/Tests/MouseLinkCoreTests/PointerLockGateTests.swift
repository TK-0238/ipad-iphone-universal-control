import XCTest
@testable import MouseLinkCore

final class PointerLockGateTests: XCTestCase {
    func testPreferenceAloneDoesNotAuthorizeInput() {
        var gate = PointerLockGate(); gate.request(at: 1)
        XCTAssertFalse(gate.canForward)
        XCTAssertFalse(gate.observe(locked: false, at: 1.2))
        XCTAssertFalse(gate.canForward)
    }
    func testActualLockPermitsForwarding() {
        var gate = PointerLockGate(); gate.request(at: 1)
        XCTAssertFalse(gate.observe(locked: true, at: 1.1))
        XCTAssertTrue(gate.canForward)
    }
    func testUnlockStopsAndDoesNotAutomaticallyResume() {
        var gate = PointerLockGate(); gate.request(at: 1)
        _ = gate.observe(locked: true, at: 1.1)
        XCTAssertTrue(gate.observe(locked: false, at: 1.2))
        XCTAssertFalse(gate.canForward)
        XCTAssertFalse(gate.observe(locked: true, at: 1.3))
        XCTAssertFalse(gate.canForward)
    }
    func testLockTimeoutStopsWaiting() {
        var gate = PointerLockGate(); gate.request(at: 1)
        XCTAssertTrue(gate.observe(locked: false, at: 2.001))
        XCTAssertFalse(gate.canForward)
    }
    func testStopDiscardsPriorLock() {
        var gate = PointerLockGate(); gate.request(at: 1)
        _ = gate.observe(locked: true, at: 1.1); gate.stop()
        _ = gate.observe(locked: true, at: 1.2)
        XCTAssertFalse(gate.canForward)
        gate.request(at: 2); XCTAssertFalse(gate.canForward)
    }
    func testInvalidOrBackwardsTimeFailsClosed() {
        for bad in [Double.nan, Double.infinity, 0.9] {
            var gate = PointerLockGate(); gate.request(at: 1)
            XCTAssertTrue(gate.observe(locked: true, at: bad))
            XCTAssertFalse(gate.canForward)
        }
    }
}
