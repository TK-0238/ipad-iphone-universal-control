import Foundation
import XCTest
@testable import MouseLinkCore

final class SafetyRegressionTests: XCTestCase {
    func testRepeatedPauseCannotPostponeReleaseDeadline() throws {
        var buffer = RelayBuffer(); buffer.begin(peer: UUID(), at: 1); buffer.acceptNext()
        try buffer.enqueue([MouseFrame(buttons: 1)], at: 1.1)
        buffer.pause(at: 1.2)
        let first = buffer.next
        buffer.pause(at: 1.8)
        XCTAssertEqual(buffer.next, first, "Repeated stop must preserve the release deadline and generation")
    }
    func testRepeatedPauseAfterReleaseDoesNotCreateAnotherWrite() {
        var buffer = RelayBuffer(); buffer.begin(peer: UUID(), at: 1); buffer.acceptNext()
        buffer.pause(at: 1.2); buffer.acceptNext(); buffer.pause(at: 2)
        XCTAssertNil(buffer.next, "Idle UI updates must not inject more button-up reports")
    }
    func testInvalidBeginMustNotDiscardOldRelease() {
        var buffer = RelayBuffer(); buffer.begin(peer: UUID(), at: 1); buffer.pause(at: 1.1)
        let pending = buffer.next
        buffer.begin(peer: UUID(), at: .nan)
        XCTAssertEqual(buffer.next, pending)
    }
    func testLockGrantedAfterDeadlineMustNotForward() {
        var gate = PointerLockGate(); gate.request(at: 1)
        XCTAssertTrue(gate.observe(locked: true, at: 2.001))
        XCTAssertFalse(gate.canForward)
    }
    func testKeyboardRejectsUnrepresentablePacingClock() {
        for time in [-1.0, Double.greatestFiniteMagnitude] {
            var transaction = KeyboardTransaction()
            XCTAssertThrowsError(try transaction.begin(.key(.enter), peer: UUID(), at: time))
            XCTAssertFalse(transaction.isActive)
        }
    }
    func testKeyboardAllControlScalarsRejectAtomically() throws {
        for code in Array(0...31) + [127] {
            let value = "ok" + String(UnicodeScalar(code)!) + "tail"
            for mode in KeyboardTextMode.allCases {
                XCTAssertThrowsError(try KeyboardPlan.text(value, mode: mode, enter: true))
            }
        }
    }
    func testUnicodeBoundariesRejectWithoutEnter() {
        for text in ["😀", "e\u{301}", "あ\u{200d}", "\u{202e}abc", "hi\u{00a0}", "ＡＢ", "ｱｲ", "日本", "\u{feff}"] {
            XCTAssertThrowsError(try KeyboardPlan.text(text, mode: .ascii, enter: true))
        }
    }
    func testExactTextLimitsAndExpansion() throws {
        XCTAssertEqual(try KeyboardPlan.text(String(repeating:"a",count:256), mode:.ascii, enter:true).reports.count, 515)
        XCTAssertThrowsError(try KeyboardPlan.text(String(repeating:"a",count:257), mode:.ascii, enter:true))
        XCTAssertEqual(try KeyboardPlan.text(String(repeating:"ん",count:256), mode:.kanaReading, enter:false).wireText.count, 512)
    }
    func testKeyboardMaximumPlanStaysOrderedUnderSeededPressure() throws {
        var rng: UInt64 = 0x5150
        let plan = try KeyboardPlan.text(String(repeating: "Ab!z", count:64),mode:.ascii,enter:true)
        let target = UUID(); var tx = KeyboardTransaction(); var now = 1.0; var received: [KeyboardStroke] = []
        try tx.begin(plan,peer:target,at:now)
        for _ in 0..<100_000 {
            if !tx.isActive { break }
            now += 0.007
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            if let stroke = tx.due(at:now), rng % 5 != 0 {
                XCTAssertEqual(tx.peer, target); received.append(stroke); tx.accept(at:now)
            }
        }
        XCTAssertEqual(received, plan.reports); XCTAssertFalse(tx.isActive)
        XCTAssertEqual(received.filter { $0 == .enter }.count, 1)
    }
    func testCancelAtEveryReportNeverReplaysRemainder() throws {
        let plan = try KeyboardPlan.text("Repeat!!",mode:.ascii,enter:true)
        for prefix in 0..<plan.reports.count {
            var tx=KeyboardTransaction(); var now=1.0; let target=UUID()
            try tx.begin(plan,peer:target,at:now)
            for _ in 0..<prefix { XCTAssertNotNil(tx.due(at:now));tx.accept(at:now);now+=0.021 }
            XCTAssertEqual(tx.cancel(),target)
            for step in 0..<20 { XCTAssertNil(tx.due(at:now+Double(step)));tx.accept(at:now+Double(step)) }
            XCTAssertFalse(tx.isActive);XCTAssertEqual(tx.remaining,0)
        }
    }
    func testSeededMotionConservationWithFractionalNegativeInputs() throws {
        var rng:UInt64=76543; var accumulator=MotionAccumulator();var sx=0.0,sy=0.0,sw=0.0;var rx=0,ry=0,rw=0
        for _ in 0..<20_000 {
            rng=rng &* 6364136223846793005 &+ 1
            let dx=Double(Int(rng % 1025)-512)/4
            rng=rng &* 6364136223846793005 &+ 1
            let dy=Double(Int(rng % 1025)-512)/4
            let wheel=Double(Int(rng % 9)-4)/4
            sx+=dx;sy+=dy;sw+=wheel
            let frames=try accumulator.add(x:dx,y:dy,wheel:wheel,buttons:3)
            for frame in frames { rx+=Int(frame.x);ry+=Int(frame.y);rw+=Int(frame.wheel);XCTAssertEqual(frame.buttons,3) }
            XCTAssertLessThan(abs(sx-Double(rx)),1);XCTAssertLessThan(abs(sy-Double(ry)),1);XCTAssertLessThan(abs(sw-Double(rw)),1)
        }
    }
    func testMalformedMotionNeverCorruptsFractionalState() throws {
        for bad in [Double.nan, .infinity, -.infinity, 8192.01, -8192.01] {
            var a=MotionAccumulator();_ = try a.add(x:0.5,y:0.5,wheel:0.5,buttons:0)
            XCTAssertThrowsError(try a.add(x:0.5,y:bad,wheel:0.5,buttons:0))
            XCTAssertEqual(try a.add(x:0.5,y:0.5,wheel:0.5,buttons:0),[MouseFrame(x:1,y:1,wheel:1)])
        }
    }
}
