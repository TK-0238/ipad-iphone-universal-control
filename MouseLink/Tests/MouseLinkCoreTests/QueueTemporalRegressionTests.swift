import Foundation
import XCTest
@testable import MouseLinkCore

final class QueueTemporalRegressionTests: XCTestCase {
    private func started() -> RelayBuffer {
        var b = RelayBuffer(); b.begin(peer: UUID(), at: 10); b.acceptNext(); return b
    }
    func testNegativeEnqueueRejectedAfterBaselineDrained() {
        var b = started()
        XCTAssertThrowsError(try b.enqueue([MouseFrame(buttons: 1)], at: -1))
        XCTAssertFalse(b.isActive); XCTAssertEqual(b.next?.frame, .zero)
    }
    func testEnqueueBeforeSessionStartRejected() {
        var b = started()
        XCTAssertThrowsError(try b.enqueue([MouseFrame(x: 1)], at: 9))
        XCTAssertFalse(b.isActive); XCTAssertEqual(b.count, 1)
    }
    func testEnqueueBeforeLastEventRejectedEvenWithEmptyQueue() throws {
        var b = started(); try b.enqueue([MouseFrame(x: 2)], at: 11); b.acceptNext()
        XCTAssertThrowsError(try b.enqueue([MouseFrame(buttons: 1)], at: 10.5))
        XCTAssertFalse(b.isActive); XCTAssertEqual(b.next?.frame, .zero)
    }
    func testClockRegressionDetectedEvenWhenNoFramesPending() {
        var b = started()
        XCTAssertTrue(b.expire(at: 9)); XCTAssertFalse(b.isActive)
        XCTAssertEqual(b.next?.frame, .zero)
    }
    func testClockRegressionAgainstLatestNotJustOldestFrame() throws {
        var b = started(); try b.enqueue([MouseFrame(x: 1)], at: 11)
        try b.enqueue([MouseFrame(x: 2)], at: 12)
        XCTAssertTrue(b.expire(at: 11.2)); XCTAssertEqual(b.count, 1)
        XCTAssertEqual(b.next?.frame, .zero)
    }
    func testInvalidBatchDoesNotLeakAnyOfItsFrames() throws {
        var b = started(); try b.enqueue([MouseFrame(x: 1)], at: 10.1)
        XCTAssertThrowsError(try b.enqueue([MouseFrame(buttons: 1), MouseFrame(x: 7)], at: 9))
        XCTAssertEqual(b.count, 1); XCTAssertEqual(b.next?.frame, .zero)
    }
    func testSameTimestampIsAllowedForOrderedButtonEdges() throws {
        var b = started()
        let frames = [MouseFrame(buttons: 1), MouseFrame.zero]
        for frame in frames { try b.enqueue([frame], at: 10) }
        for frame in frames { XCTAssertEqual(b.next?.frame, frame); b.acceptNext() }
        XCTAssertTrue(b.isActive); XCTAssertNil(b.next)
    }
    func testNewSessionHasItsOwnClockOrigin() throws {
        var b = started(); b.disconnect(); b.begin(peer: UUID(), at: 1); b.acceptNext()
        try b.enqueue([MouseFrame(x: 2)], at: 1)
        XCTAssertEqual(b.next?.frame.x, 2)
    }
    func testInvalidBeginPreservesPendingRelease() {
        var b = started(); b.pause(at: 10.1); let pending = b.next
        b.begin(peer: UUID(), at: .infinity)
        XCTAssertEqual(b.next, pending); XCTAssertFalse(b.isActive)
    }
    func testEmptyInputStillCannotMoveEventClockBackwards() throws {
        var b = started(); try b.enqueue([], at: 12)
        XCTAssertThrowsError(try b.enqueue([MouseFrame(x: 3)], at: 11))
        XCTAssertFalse(b.isActive)
    }
}
