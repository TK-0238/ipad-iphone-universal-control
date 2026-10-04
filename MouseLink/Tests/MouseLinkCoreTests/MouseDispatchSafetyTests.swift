import Foundation
import XCTest
@testable import MouseLinkCore
final class MouseDispatchSafetyTests: XCTestCase {
    private func pending(_ frame: MouseFrame = MouseFrame(buttons:1),active:Bool=true) throws -> PendingMouseFrame {
        var b=RelayBuffer();b.begin(peer:UUID(),at:1);b.acceptNext();try b.enqueue([frame],at:1)
        if !active { b.pause(at:1) }; return b.next!
    }
    func testLateWriteReadyMustReleaseNotSendOldClick() throws {
        XCTAssertEqual(MouseDispatchSafety.decide(try pending(),at:1.501,active:true,foreground:true,locked:true,sameConnection:true),.release)
    }
    func testUnlockBetweenQueueAndCallbackMustRelease() throws {
        XCTAssertEqual(MouseDispatchSafety.decide(try pending(),at:1.1,active:true,foreground:true,locked:false,sameConnection:true),.release)
    }
    func testDifferentConnectionMustDiscardEvenNeutral() throws {
        XCTAssertEqual(MouseDispatchSafety.decide(try pending(active:false),at:1.1,active:false,foreground:true,locked:false,sameConnection:false),.discard)
    }
    func testUnsentReleaseDeadlineDisconnects() throws {
        XCTAssertEqual(MouseDispatchSafety.decide(try pending(active:false),at:1.701,active:false,foreground:true,locked:false,sameConnection:true),.disconnect)
    }
    func testNeutralBootstrapAllowedBeforeLock() throws {
        XCTAssertEqual(MouseDispatchSafety.decide(try pending(.zero),at:1.1,active:true,foreground:true,locked:false,sameConnection:true),.send)
    }
    func testFreshAuthorizedClickAllowed() throws {
        XCTAssertEqual(MouseDispatchSafety.decide(try pending(),at:1.499,active:true,foreground:true,locked:true,sameConnection:true),.send)
    }
    func testNonfiniteClockNeverSendsAnything() throws {
        for t in [Double.nan, .infinity, -.infinity, 0.999] {
            XCTAssertEqual(MouseDispatchSafety.decide(try pending(),at:t,active:true,foreground:true,locked:true,sameConnection:true),.disconnect)
        }
    }
    func testForegroundLossBetweenQueueAndCallbackReleases() throws {
        XCTAssertEqual(MouseDispatchSafety.decide(try pending(),at:1.1,active:true,foreground:false,locked:true,sameConnection:true),.release)
    }
}
