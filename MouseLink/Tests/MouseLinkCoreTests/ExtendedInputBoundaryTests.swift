import Foundation
import XCTest
@testable import MouseLinkCore

final class ExtendedInputBoundaryTests: XCTestCase {
    // Numerical layout cases, not claims of running on these physical screens.
    private let sizes: [(Double, Double)] = [(320,568),(568,320),(393,852),(852,393),
        (600,834),(504,1210),(834,1210),(1210,834),(699,400),(700,400)]
    func testPortraitLandscapeAndPanelSizesPreserveAxisAndDistance() throws {
        for (w,h) in sizes {
            var p = LocalPadPointer()
            XCTAssertTrue(try p.move(x: 20,y:20,width:w,height:h).isEmpty)
            let frames = try p.move(x:120,y:70,width:w,height:h)
            XCTAssertEqual(frames.reduce(0) {$0 + Int($1.x)},100)
            XCTAssertEqual(frames.reduce(0) {$0 + Int($1.y)},50)
            XCTAssertTrue(frames.allSatisfy {$0.buttons == 0})
        }
    }
    func testEveryExitEdgeReleasesEverySupportedButtonCombination() throws {
        for (w,h) in sizes { for mask:UInt8 in [1,2,3] {
            for point in [(-1.0,50.0),(w,50.0),(50.0,-1.0),(50.0,h)] {
                var p=LocalPadPointer();_ = try p.move(x:20,y:20,width:w,height:h);_ = p.buttons(mask)
                XCTAssertEqual(try p.move(x:point.0,y:point.1,width:w,height:h),[.zero])
                XCTAssertFalse(p.isInside);XCTAssertTrue(p.buttons(1).isEmpty)
            }
        } }
    }
    func testRotationDoesNotTurnOldPositionIntoLargeRemoteJump() throws {
        for (w,h) in sizes {
            var p=LocalPadPointer();_ = try p.move(x:20,y:20,width:w,height:h);_ = p.buttons(1)
            XCTAssertEqual(try p.move(x:50,y:50,width:h,height:w),[.zero])
            XCTAssertFalse(p.isInside)
            XCTAssertTrue(try p.move(x:60,y:60,width:h,height:w).isEmpty)
            XCTAssertEqual(try p.move(x:61,y:62,width:h,height:w),[MouseFrame(x:1,y:2)])
        }
    }
    func testExternalDragCannotEnterPadUntilButtonReleased() throws {
        for (w,h) in sizes {
            var p=LocalPadPointer()
            for i in 0..<20 { XCTAssertTrue(try p.move(x:Double(10+i),y:20,width:w,height:h,externalButtonsDown:true).isEmpty) }
            XCTAssertFalse(p.isInside)
            XCTAssertTrue(try p.move(x:50,y:50,width:w,height:h).isEmpty)
            XCTAssertEqual(try p.move(x:51,y:50,width:w,height:h),[MouseFrame(x:1)])
        }
    }
    func testInvalidGeometryAndGainDoNotMutatePreviousPosition() throws {
        let invalid:[Double] = [.nan,.infinity,-.infinity]
        for bad in invalid {
            var p=LocalPadPointer();_ = try p.move(x:20,y:20,width:300,height:200)
            XCTAssertThrowsError(try p.move(x:bad,y:20,width:300,height:200))
            XCTAssertEqual(try p.move(x:21,y:22,width:300,height:200),[MouseFrame(x:1,y:2)])
        }
        for gain in [0.0,0.249,3.001,Double.nan] {
            var p=LocalPadPointer()
            XCTAssertThrowsError(try p.move(x:20,y:20,width:300,height:200,gain:gain))
            XCTAssertFalse(p.isInside)
        }
    }
    func testLeaveDiscardsAllFractionalRemainders() throws {
        var p=LocalPadPointer();_ = try p.move(x:20,y:20,width:300,height:200)
        _ = try p.move(x:20.75,y:20.75,width:300,height:200);_ = try p.scroll(0.75)
        p.leave();_ = try p.move(x:100,y:100,width:300,height:200)
        XCTAssertTrue(try p.move(x:100.5,y:100.5,width:300,height:200).isEmpty)
        XCTAssertTrue(try p.scroll(0.5).isEmpty)
    }
    func testAllButtonMasksAreRestrictedToTwoPanelButtons() throws {
        for mask in UInt8.min...UInt8.max {
            var p=LocalPadPointer();_ = try p.move(x:20,y:20,width:300,height:200)
            let frames=p.buttons(mask)
            XCTAssertEqual(frames.last?.buttons ?? 0, mask & 3)
            XCTAssertTrue(p.buttons(mask).isEmpty)
        }
    }
    func testMaximumKeyboardPlanCanBeCancelledAtEveryBoundary() throws {
        let plan=try KeyboardPlan.text(String(repeating:"a",count:256),mode:.ascii,enter:true)
        for stop in 0...plan.reports.count {
            var tx=KeyboardTransaction();let peer=UUID();var time=1.0
            try tx.begin(plan,peer:peer,at:time)
            for _ in 0..<stop { XCTAssertNotNil(tx.due(at:time));tx.accept(at:time);time+=0.021 }
            let target=tx.cancel()
            XCTAssertEqual(target,stop == plan.reports.count ? nil : peer)
            XCTAssertNil(tx.due(at:time+0.1));XCTAssertFalse(tx.isActive);XCTAssertEqual(tx.remaining,0)
        }
    }
    func testUnicodeRejectedAtomicallyAtEveryDraftPosition() {
        for value in ["漢","🧑‍💻","\u{202E}","\u{200B}","é","\n","\t","\u{007F}","\u{0000}"] {
            for position in 0...20 {
                let text=String(repeating:"a",count:position)+value+String(repeating:"z",count:20-position)
                XCTAssertThrowsError(try KeyboardPlan.text(text,mode:.ascii,enter:true))
                XCTAssertThrowsError(try KeyboardPlan.text(text,mode:.kanaReading,enter:true))
            }
        }
    }
    func testPrintableASCIIReportsAreDistinctAndAlwaysReleased() throws {
        let all=String((32...126).map { Character(UnicodeScalar($0)!) })
        let plan=try KeyboardPlan.text(all,mode:.ascii,enter:false)
        XCTAssertEqual(Set(plan.strokes.map { $0.data }).count,95)
        for (index,report) in plan.reports.enumerated() {
            if index % 2 == 0 { XCTAssertEqual(report,.zero) }
            else { XCTAssertNotEqual(report.usage,0);XCTAssertNotEqual(report.usage,0x28) }
        }
    }
    func testSeededQueuePressurePreservesAcceptedPrefixAndBoundedStorage() throws {
        var seed:UInt64=991;var b=RelayBuffer(capacity:32);let peer=UUID();b.begin(peer:peer,at:0);b.acceptNext()
        var expected:[MouseFrame]=[];var time=0.0
        for _ in 0..<20000 {
            seed=seed &* 6364136223846793005 &+ 1;time+=0.001
            if seed % 3 == 0, !expected.isEmpty {
                XCTAssertEqual(b.next?.frame,expected.removeFirst());b.acceptNext()
            } else {
                let frame=MouseFrame(buttons:UInt8(seed % 4),x:Int8(Int(seed % 21)-10))
                if expected.count < 32 { try b.enqueue([frame],at:time);expected.append(frame) }
                else {
                    XCTAssertThrowsError(try b.enqueue([frame],at:time))
                    XCTAssertFalse(b.isActive);XCTAssertEqual(b.next?.frame,.zero)
                    b.disconnect();b.begin(peer:peer,at:time);b.acceptNext();expected=[]
                }
            }
            XCTAssertLessThanOrEqual(b.count,32)
        }
    }
}
