import Foundation
import XCTest
@testable import MouseLinkCore

final class RelayCoreTests: XCTestCase {
    func testReportBytesUseSignedTwosComplement() {
        XCTAssertEqual(MouseFrame(buttons: 3, x: -127, y: 127, wheel: -1).data, Data([3, 129, 127, 255]))
    }
    func testUnsupportedButtonsMasked() { XCTAssertEqual(MouseFrame(buttons: 255).data.first, 7) }
    func testZeroReportReleasesEverything() { XCTAssertEqual(MouseFrame.zero.data, Data([0, 0, 0, 0])) }
    func testLargeMovementIsSplitWithoutLosingDistance() throws {
        var a = MotionAccumulator()
        let frames = try a.add(x: 300, y: -260, wheel: 130, buttons: 1)
        XCTAssertEqual(frames.reduce(0) { $0 + Int($1.x) }, 300)
        XCTAssertEqual(frames.reduce(0) { $0 + Int($1.y) }, -260)
        XCTAssertEqual(frames.reduce(0) { $0 + Int($1.wheel) }, 130)
        XCTAssertTrue(frames.allSatisfy { $0.buttons == 1 })
        XCTAssertEqual(frames.count, 3)
    }
    func testFractionalMotionAccumulates() throws {
        var a = MotionAccumulator()
        XCTAssertTrue(try a.add(x: 0.25, y: 0, wheel: 0, buttons: 0).isEmpty)
        XCTAssertTrue(try a.add(x: 0.25, y: 0, wheel: 0, buttons: 0).isEmpty)
        XCTAssertTrue(try a.add(x: 0.25, y: 0, wheel: 0, buttons: 0).isEmpty)
        XCTAssertEqual(try a.add(x: 0.25, y: 0, wheel: 0, buttons: 0), [MouseFrame(x: 1)])
    }
    func testNonfiniteOrHugeMotionIsRejectedAtomically() throws {
        for value in [Double.nan, Double.infinity, -Double.infinity, 8193] {
            var a = MotionAccumulator()
            XCTAssertThrowsError(try a.add(x: value, y: 1, wheel: 0, buttons: 0))
            XCTAssertEqual(try a.add(x: 0, y: 1, wheel: 0, buttons: 0), [MouseFrame(y: 1)])
        }
    }
    func testNegativeFractionsAccumulate() throws {
        var a = MotionAccumulator()
        _ = try a.add(x: -0.5, y: 0, wheel: 0, buttons: 0)
        XCTAssertEqual(try a.add(x: -0.5, y: 0, wheel: 0, buttons: 0), [MouseFrame(x: -1)])
    }
    func testOppositeFractionsCancel() throws {
        var a = MotionAccumulator()
        _ = try a.add(x: -0.5, y: 0, wheel: 0, buttons: 0)
        XCTAssertTrue(try a.add(x: 0.5, y: 0, wheel: 0, buttons: 0).isEmpty)
    }
    func testNoInputBeforeExplicitStart() throws {
        var b = RelayBuffer()
        XCTAssertThrowsError(try b.enqueue([MouseFrame(buttons: 1)], at: 1))
        XCTAssertNil(b.next)
    }
    func testStartAlwaysQueuesNeutralBaseline() {
        var b = RelayBuffer(); let id = UUID(); b.begin(peer: id, at: 0)
        XCTAssertEqual(b.next?.frame, .zero); XCTAssertEqual(b.next?.peer, id)
        XCTAssertTrue(b.isActive)
    }
    func testFIFOIsNotLatestValueCoalescing() throws {
        var b = RelayBuffer(); b.begin(peer: UUID(), at: 0); b.acceptNext()
        let frames = [MouseFrame(buttons: 1), MouseFrame(x: 4), MouseFrame.zero]
        try b.enqueue(frames, at: 0.1)
        for frame in frames { XCTAssertEqual(b.next?.frame, frame); b.acceptNext() }
        XCTAssertNil(b.next)
    }
    func testBackpressureDoesNotRemovePendingFrame() throws {
        var b = RelayBuffer(); b.begin(peer: UUID(), at: 0); b.acceptNext()
        try b.enqueue([MouseFrame(x: 8)], at: 0.1)
        XCTAssertEqual(b.next, b.next); XCTAssertEqual(b.count, 1)
    }
    func testOverflowFailsClosedWithReleaseOnly() throws {
        var b = RelayBuffer(capacity: 2); b.begin(peer: UUID(), at: 0); b.acceptNext()
        try b.enqueue([MouseFrame(buttons: 1), MouseFrame(x: 2)], at: 0.1)
        XCTAssertThrowsError(try b.enqueue([MouseFrame(x: 3)], at: 0.2))
        XCTAssertFalse(b.isActive); XCTAssertEqual(b.count, 1); XCTAssertEqual(b.next?.frame, .zero)
    }
    func testStopDropsOldMovementAndReleasesSamePeer() throws {
        var b = RelayBuffer(); let id = UUID(); b.begin(peer: id, at: 0); b.acceptNext()
        try b.enqueue([MouseFrame(buttons: 1), MouseFrame(x: 20)], at: 0.1)
        b.pause(at: 0.2)
        XCTAssertFalse(b.isActive); XCTAssertEqual(b.count, 1)
        XCTAssertEqual(b.next?.peer, id); XCTAssertEqual(b.next?.frame, .zero)
    }
    func testNewSessionDoesNotReusePreviousFrames() throws {
        var b = RelayBuffer(); let a = UUID(), c = UUID(); b.begin(peer: a, at: 0); b.acceptNext()
        try b.enqueue([MouseFrame(buttons: 1)], at: 0.1)
        let generation = b.generation
        b.begin(peer: c, at: 0.2)
        XCTAssertNotEqual(b.generation, generation)
        XCTAssertEqual(b.count, 1); XCTAssertEqual(b.next?.frame, .zero); XCTAssertEqual(b.next?.peer, c)
    }
    func testExpiredQueuePausesAndDoesNotReplay() throws {
        var b = RelayBuffer(); b.begin(peer: UUID(), at: 0); b.acceptNext()
        try b.enqueue([MouseFrame(buttons: 1), MouseFrame(x: 99)], at: 1)
        XCTAssertTrue(b.expire(at: 1.501)); XCTAssertFalse(b.isActive)
        XCTAssertEqual(b.next?.frame, .zero); XCTAssertEqual(b.count, 1)
    }
    func testFreshQueueDoesNotExpire() throws {
        var b = RelayBuffer(); b.begin(peer: UUID(), at: 0)
        XCTAssertFalse(b.expire(at: 0.499)); XCTAssertTrue(b.isActive)
    }
    func testClockAnomalyFailsClosed() {
        var b = RelayBuffer(); b.begin(peer: UUID(), at: 10)
        XCTAssertTrue(b.expire(at: 9)); XCTAssertFalse(b.isActive)
    }
    func testDisconnectClearsAllAndInvalidatesGeneration() {
        var b = RelayBuffer(); b.begin(peer: UUID(), at: 0); let generation = b.generation
        b.disconnect(); XCTAssertFalse(b.isActive); XCTAssertNil(b.next); XCTAssertNil(b.peer)
        XCTAssertNotEqual(b.generation, generation)
    }
    func testSelectionRequiresExactlyOneMouseReceiver() {
        let a = UUID(), b = UUID()
        XCTAssertEqual(ReceiverPolicy.choose(previous: nil, available: [a]), a)
        XCTAssertNil(ReceiverPolicy.choose(previous: nil, available: [a, b]))
        XCTAssertEqual(ReceiverPolicy.choose(previous: a, available: [a, b]), a)
        XCTAssertNil(ReceiverPolicy.choose(previous: a, available: [b]))
    }
    func testStartGateRequiresForegroundMouseAndPeer() {
        for foreground in [false, true] { for mouse in [false, true] { for peer in [false, true] {
            XCTAssertEqual(ReceiverPolicy.canStart(foreground: foreground, mouse: mouse, selectedIsAvailable: peer), foreground && mouse && peer)
        } } }
    }
    func testMovementFuzzPreservesIntegerDistances() throws {
        var rng: UInt64 = 12345
        for _ in 0..<3000 {
            rng = rng &* 6364136223846793005 &+ 1
            let x = Int(rng % 10001) - 5000
            rng = rng &* 6364136223846793005 &+ 1
            let y = Int(rng % 10001) - 5000
            var a = MotionAccumulator()
            let frames = try a.add(x: Double(x), y: Double(y), wheel: 0, buttons: 2)
            XCTAssertEqual(frames.reduce(0) { $0 + Int($1.x) }, x)
            XCTAssertEqual(frames.reduce(0) { $0 + Int($1.y) }, y)
            XCTAssertTrue(frames.count <= 40)
        }
    }
}
