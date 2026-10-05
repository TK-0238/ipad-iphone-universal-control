import XCTest
@testable import MouseLinkCore

final class PanelPointerTests: XCTestCase {
    func testFirstPointIsBaselineNotRemoteJump() throws {
        var p = LocalPadPointer()
        XCTAssertEqual(try p.move(x: 150, y: 80, width: 300, height: 200), [])
        XCTAssertTrue(p.isInside)
    }
    func testRelativeMotionUsesLocalDownwardY() throws {
        var p = LocalPadPointer()
        _ = try p.move(x: 20, y: 20, width: 300, height: 200)
        XCTAssertEqual(try p.move(x: 27, y: 31, width: 300, height: 200), [MouseFrame(x: 7, y: 11)])
    }
    func testEntryWhileAlreadyDraggingIsIgnored() throws {
        var p = LocalPadPointer()
        XCTAssertTrue(try p.move(x: 20, y: 20, width: 300, height: 200, externalButtonsDown: true).isEmpty)
        XCTAssertFalse(p.isInside)
        XCTAssertTrue(try p.move(x: 30, y: 20, width: 300, height: 200).isEmpty)
    }
    func testLeavingDropsPositionAndReleasesHeldButtons() throws {
        var p = LocalPadPointer()
        _ = try p.move(x: 20, y: 20, width: 300, height: 200)
        XCTAssertEqual(p.buttons(1), [MouseFrame(buttons: 1)])
        XCTAssertEqual(p.leave(), [.zero]); XCTAssertFalse(p.isInside)
        XCTAssertEqual(p.leave(), [])
        XCTAssertEqual(try p.move(x: 220, y: 120, width: 300, height: 200), [])
    }
    func testOutsidePointNeverMovesAndReleases() throws {
        var p = LocalPadPointer()
        _ = try p.move(x: 20, y: 20, width: 300, height: 200); _ = p.buttons(1)
        XCTAssertEqual(try p.move(x: 300, y: 20, width: 300, height: 200), [.zero])
        XCTAssertFalse(p.isInside)
    }
    func testNoButtonBeforePointerEntry() { var p = LocalPadPointer(); XCTAssertEqual(p.buttons(1), []) }
    func testRepeatedButtonStateDoesNotDuplicateClick() throws {
        var p = LocalPadPointer(); _ = try p.move(x: 1, y: 1, width: 300, height: 200)
        XCTAssertEqual(p.buttons(2), [MouseFrame(buttons: 2)])
        XCTAssertEqual(p.buttons(2), []); XCTAssertEqual(p.buttons(0), [.zero])
    }
    func testFractionalMotionAndSensitivity() throws {
        var p = LocalPadPointer(); _ = try p.move(x: 1, y: 1, width: 300, height: 200)
        XCTAssertTrue(try p.move(x: 1.25, y: 1, width: 300, height: 200, gain: 2).isEmpty)
        XCTAssertEqual(try p.move(x: 1.5, y: 1, width: 300, height: 200, gain: 2), [MouseFrame(x: 1)])
    }
    func testExitResetsFractionalRemainder() throws {
        var p = LocalPadPointer(); _ = try p.move(x: 1, y: 1, width: 300, height: 200)
        _ = try p.move(x: 1.75, y: 1, width: 300, height: 200); _ = p.leave()
        _ = try p.move(x: 1, y: 1, width: 300, height: 200)
        XCTAssertTrue(try p.move(x: 1.25, y: 1, width: 300, height: 200).isEmpty)
    }
    func testResizeReleasesInsteadOfReusingOldCoordinate() throws {
        var p = LocalPadPointer(); _ = try p.move(x: 10, y: 10, width: 300, height: 200); _ = p.buttons(1)
        XCTAssertEqual(try p.move(x: 10, y: 10, width: 200, height: 200), [.zero])
        XCTAssertFalse(p.isInside)
    }
    func testNonfiniteGeometryIsRejected() {
        for value in [Double.nan, .infinity, -.infinity] {
            var p = LocalPadPointer()
            XCTAssertThrowsError(try p.move(x: value, y: 1, width: 300, height: 200))
            XCTAssertFalse(p.isInside)
        }
    }
    func testInvalidGainOrDimensionsAreRejected() {
        for gain in [Double.nan, 0, -1, 4] {
            var p = LocalPadPointer()
            XCTAssertThrowsError(try p.move(x: 1, y: 1, width: 300, height: 200, gain: gain))
        }
        var p = LocalPadPointer()
        XCTAssertThrowsError(try p.move(x: 1, y: 1, width: 0, height: 200))
    }
    func testWheelDoesNotRunOutsidePad() throws {
        var p = LocalPadPointer(); XCTAssertEqual(try p.scroll(2), [])
        _ = try p.move(x: 1, y: 1, width: 300, height: 200)
        XCTAssertEqual(try p.scroll(-2), [MouseFrame(wheel: -2)])
    }
    func testLargeMovementPreservesDistance() throws {
        var p = LocalPadPointer(); _ = try p.move(x: 1, y: 1, width: 900, height: 600)
        let frames = try p.move(x: 701, y: 500, width: 900, height: 600)
        XCTAssertEqual(frames.reduce(0) { $0 + Int($1.x) }, 700)
        XCTAssertEqual(frames.reduce(0) { $0 + Int($1.y) }, 499)
    }
}
