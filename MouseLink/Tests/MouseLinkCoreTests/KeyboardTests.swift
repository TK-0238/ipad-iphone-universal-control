import Foundation
import XCTest
@testable import MouseLinkCore

final class KeyboardTests: XCTestCase {
    func testASCIIUppercaseDigitsAndSymbols() throws {
        let plan = try KeyboardPlan.text("aA1!?@", mode: .ascii, enter: false)
        XCTAssertEqual(plan.strokes.map(\.usage), [4,4,30,30,56,31])
        XCTAssertEqual(plan.strokes.map(\.modifiers), [0,2,0,2,2,2])
    }
    func testAllPrintableASCIIHaveMapping() throws {
        for value in 32...126 {
            let p = try KeyboardPlan.text(String(UnicodeScalar(value)!), mode: .ascii, enter: false)
            XCTAssertEqual(p.strokes.count, 1)
            XCTAssertTrue((4...56).contains(Int(p.strokes[0].usage)))
        }
    }
    func testReturnIsHID28NotLineFeed() {
        XCTAssertEqual(KeyboardStroke.enter.data, Data([0,0,0x28,0,0,0,0,0]))
        XCTAssertEqual(KeyboardStroke.shiftEnter.data, Data([2,0,0x28,0,0,0,0,0]))
    }
    func testTextPlusEnterAppendsOneEnter() throws {
        let p = try KeyboardPlan.text("ab", mode: .ascii, enter: true)
        XCTAssertEqual(p.strokes.map(\.usage), [4,5,0x28])
    }
    func testRepeatedKeysAlwaysHaveReleaseBetween() throws {
        let p = try KeyboardPlan.text("aa", mode: .ascii, enter: false)
        XCTAssertEqual(p.reports, [.zero, KeyboardStroke(usage:4), .zero, KeyboardStroke(usage:4), .zero])
    }
    func testEmptyTextIsNotImplicitEnter() {
        XCTAssertThrowsError(try KeyboardPlan.text("", mode: .ascii, enter: true))
    }
    func testUnsupportedUnicodeIsRejectedNotSilentlyDropped() {
        for text in ["hello日本", "🙂", "é", "👨‍👩‍👧‍👦", "a\u{200b}b"] {
            XCTAssertThrowsError(try KeyboardPlan.text(text, mode: .ascii, enter: true))
        }
    }
    func testPastedControlsDoNotSubmitOrNavigate() {
        for text in ["hi\n", "a\r\nb", "a\t", "a\0", "a\u{1b}", "a\u{7f}"] {
            XCTAssertThrowsError(try KeyboardPlan.text(text, mode: .ascii, enter: false))
        }
    }
    func testOversizeTextIsRejected() {
        XCTAssertThrowsError(try KeyboardPlan.text(String(repeating:"a", count:257), mode:.ascii, enter:false))
    }
    func testKanaReadingIsExplicitAndDoesNotGuessKanji() throws {
        XCTAssertEqual(try KeyboardPlan.text("にほんご", mode:.kanaReading, enter:false).wireText, "nihon'go")
        XCTAssertThrowsError(try KeyboardPlan.text("日本語", mode:.kanaReading, enter:false))
        XCTAssertThrowsError(try KeyboardPlan.text("にほんご", mode:.ascii, enter:false))
    }
    func testKatakanaAndDecomposedDakutenBecomeReading() throws {
        XCTAssertEqual(try KeyboardPlan.text("ガッコウ", mode:.kanaReading, enter:false).wireText, "gaxtukou")
        XCTAssertEqual(try KeyboardPlan.text("きゃー、んあ。", mode:.kanaReading, enter:false).wireText, "kixya-,n'a.")
    }
    func testKanaModeNeverAddsConversionOrEnterImplicitly() throws {
        let p = try KeyboardPlan.text("ねこ", mode:.kanaReading, enter:false)
        XCTAssertFalse(p.strokes.contains(.enter))
        XCTAssertEqual(p.wireText,"neko")
    }
    func testControlSpaceForInputSourceSwitch() {
        XCTAssertEqual(KeyboardStroke.inputSource.data,Data([1,0,44,0,0,0,0,0]))
    }
    func testStandaloneSpecialKeysArePairedWithRelease() {
        for key in [KeyboardStroke.enter, .backspace, .tab, .space, .escape, .left, .right, .up, .down, .shiftEnter, .inputSource] {
            XCTAssertEqual(KeyboardPlan.key(key).reports, [.zero,key,.zero])
        }
    }
    func testTransactionStartsNeutralAndPreservesTarget() throws {
        var q=KeyboardTransaction(); let peer=UUID()
        try q.begin(KeyboardPlan.text("a",mode:.ascii,enter:true), peer:peer, at:1)
        XCTAssertEqual(q.peer,peer); XCTAssertTrue(q.isActive)
        XCTAssertEqual(q.due(at:1), .zero)
    }
    func testTransactionDoesNotAdvanceUnderBackpressure() throws {
        var q=KeyboardTransaction();try q.begin(.key(.enter),peer:UUID(),at:1)
        XCTAssertEqual(q.due(at:1),q.due(at:1.01));XCTAssertEqual(q.remaining,3)
    }
    func testReportsArePacedFromActualAcceptance() throws {
        var q=KeyboardTransaction();try q.begin(.key(.enter),peer:UUID(),at:1)
        q.accept(at:1)
        XCTAssertNil(q.due(at:1.01));XCTAssertEqual(q.due(at:1.021), .enter)
        q.accept(at:1.021)
        XCTAssertNil(q.due(at:1.03));XCTAssertEqual(q.due(at:1.042), .zero)
        q.accept(at:1.042);XCTAssertFalse(q.isActive)
    }
    func testCannotOverwriteInFlightText() throws {
        var q=KeyboardTransaction(); let peer=UUID()
        try q.begin(.key(.enter),peer:peer,at:1)
        XCTAssertThrowsError(try q.begin(.key(.space),peer:UUID(),at:1.1))
        XCTAssertEqual(q.peer,peer);XCTAssertEqual(q.remaining,3)
    }
    func testCancelDropsUnsentEnter() throws {
        var q=KeyboardTransaction();try q.begin(KeyboardPlan.text("hi",mode:.ascii,enter:true),peer:UUID(),at:1)
        let peer=q.peer;let cancelled=q.cancel()
        XCTAssertEqual(cancelled,peer);XCTAssertFalse(q.isActive);XCTAssertNil(q.due(at:2));XCTAssertEqual(q.remaining,0)
    }
    func testStallIsBasedOnLastProgressNotTotalLength() throws {
        var q=KeyboardTransaction();try q.begin(KeyboardPlan.text(String(repeating:"a",count:100),mode:.ascii,enter:false),peer:UUID(),at:1)
        for n in 0..<50 { let t=1+Double(n)*0.04;XCTAssertFalse(q.isStalled(at:t));q.accept(at:t) }
        XCTAssertTrue(q.isActive);XCTAssertTrue(q.isStalled(at:4))
    }
    func testInvalidClockIsStalled() throws {
        for t in [Double.nan, .infinity, 0.9, 1.501] {
            var q=KeyboardTransaction();try q.begin(.key(.enter),peer:UUID(),at:1)
            XCTAssertTrue(q.isStalled(at:t))
        }
    }
    func testIdleClockNeverTriggersRemoteRelease() { let q=KeyboardTransaction();XCTAssertFalse(q.isStalled(at:999)) }
    func testMissingOrDifferentKeyboardTargetCannotSend() {
        let a=UUID(),b=UUID()
        XCTAssertFalse(KeyboardPolicy.canSend(peer:nil,receivers:[a],foreground:true,mouseRelaying:false))
        XCTAssertFalse(KeyboardPolicy.canSend(peer:a,receivers:[b],foreground:true,mouseRelaying:false))
        XCTAssertFalse(KeyboardPolicy.canSend(peer:a,receivers:[a],foreground:false,mouseRelaying:false))
        XCTAssertFalse(KeyboardPolicy.canSend(peer:a,receivers:[a],foreground:true,mouseRelaying:true))
        XCTAssertTrue(KeyboardPolicy.canSend(peer:a,receivers:[a,b],foreground:true,mouseRelaying:false))
    }
}
