import XCTest
import Combine
import UIKit
@testable import MouseLink

@MainActor
private final class PanelSender: PanelMouseSending {
    var mouseReceivers:Set<UUID>=[]
    var inputEpoch:UInt64=1
    var accepted:[(UUID,MouseFrame)]=[]
    var response:MouseSendResult = .accepted
    var disconnects=0
    func sendPanelMouse(_ frame:MouseFrame,to peer:UUID)->MouseSendResult {
        if response == .accepted { accepted.append((peer,frame)) }; return response
    }
    func hardDisconnect() { disconnects+=1;inputEpoch+=1;mouseReceivers=[] }
}
@MainActor
final class PanelSessionTests: XCTestCase {
    private var time:Double=1
    private var usable=true
    private func make()->(PanelSession,PanelSender,UUID) {
        let s=PanelSender();let peer=UUID();s.mouseReceivers=[peer,UUID()]
        let p=PanelSession(sender:s,clock:{self.time},ticks:Empty<Date,Never>().eraseToAnyPublisher())
        p.surfaceIsUsable={self.usable};p.enable(peer:peer);return(p,s,peer)
    }
    private func enter(_ p:PanelSession) { p.move(x:20,y:20,width:300,height:200) }
    func testEnableDoesNotSendUntilLocalEvent() { let (p,s,_)=make();p.pump();XCTAssertTrue(p.isEnabled);XCTAssertTrue(s.accepted.isEmpty) }
    func testOnlySelectedReceiverGetsLocalMouse() {
        let (p,s,id)=make();enter(p);p.move(x:30,y:25,width:300,height:200);p.tap()
        XCTAssertEqual(s.accepted.map{$0.1},[.zero,MouseFrame(x:10,y:5),MouseFrame(buttons:1),.zero])
        XCTAssertTrue(s.accepted.allSatisfy{$0.0==id})
    }
    func testPointerLeavingReleasesAndNeverReplaysMovement() {
        let (p,s,_)=make();enter(p);p.buttons(1);s.response = .busy
        p.move(x:40,y:30,width:300,height:200);s.response = .accepted;p.leave();p.pump()
        XCTAssertEqual(s.accepted.last?.1,.zero);XCTAssertTrue(p.isEnabled);XCTAssertFalse(p.isInside)
        let n=s.accepted.count;p.move(x:200,y:100,width:300,height:200)
        XCTAssertEqual(s.accepted.count,n+1);XCTAssertEqual(s.accepted.last?.1,.zero)
    }
    func testHiddenOrInactiveSurfaceRejectsBeforeSending() {
        let (p,s,_)=make();enter(p);p.buttons(1);usable=false;p.move(x:30,y:30,width:300,height:200)
        XCTAssertFalse(p.isEnabled);XCTAssertEqual(s.accepted.last?.1,.zero)
        let count=s.accepted.count;usable=true;p.pump();XCTAssertEqual(count,s.accepted.count)
    }
    func testResizeDisablesAndReleases() { let(p,s,_)=make();enter(p);p.buttons(1);p.geometryChanged();XCTAssertFalse(p.isEnabled);XCTAssertEqual(s.accepted.last?.1,.zero) }
    func testSameUUIDNewConnectionDiscardsAllOldInput() {
        let(p,s,_)=make();enter(p);p.buttons(1);let n=s.accepted.count;s.inputEpoch+=1;p.pump()
        XCTAssertFalse(p.isEnabled);XCTAssertEqual(s.accepted.count,n);XCTAssertEqual(s.disconnects,1)
    }
    func testMixedButtonsStayOrderedUnderPressure() {
        let(p,s,_)=make();enter(p);s.response = .busy;p.buttons(1);p.buttons(3);p.buttons(2);p.buttons(0)
        s.response = .accepted;p.pump()
        XCTAssertEqual(s.accepted.map{$0.1.buttons},[0,1,3,2,0])
    }
    func testTimeoutDropsQueuedClicks() {
        let(p,s,_)=make();enter(p);s.response = .busy;p.buttons(1);time+=0.51;s.response = .accepted;p.pump()
        XCTAssertFalse(p.isEnabled);XCTAssertFalse(s.accepted.contains{$0.1.buttons != 0})
    }
    func testFailedReleaseDisconnects() {
        let(p,s,_)=make();enter(p);p.buttons(1);s.response = .busy;p.leave()
        XCTAssertFalse(p.isEnabled);XCTAssertEqual(s.disconnects,1)
    }
    func testOutsideClickCannotGoToPhone() {
        let(p,s,_)=make();p.buttons(1);p.tap();p.scroll(2);XCTAssertTrue(s.accepted.isEmpty)
    }
    func testExplicitReenableDoesNotReusePosition() {
        let(p,s,id)=make();enter(p);p.disable();let n=s.accepted.count;p.enable(peer:id)
        p.move(x:280,y:180,width:300,height:200);XCTAssertEqual(s.accepted.count,n+1);XCTAssertEqual(s.accepted.last?.1,.zero)
    }
    func testUIKitDeactivationStopsSynchronously() {
        let(p,s,_)=make();enter(p);p.buttons(1)
        NotificationCenter.default.post(name:UIApplication.willResignActiveNotification,object:UIApplication.shared)
        XCTAssertFalse(p.isEnabled);XCTAssertEqual(s.accepted.last?.1,.zero)
    }
    func testUnknownReceiverCannotEnable() {
        let(p,s,_)=make();p.enable(peer:UUID());enter(p);XCTAssertFalse(p.isEnabled);XCTAssertTrue(s.accepted.isEmpty)
    }
    func testInvalidClockNeverSendsNonzeroInput() {
        let(p,s,_)=make();enter(p);time = .nan;p.buttons(1)
        XCTAssertFalse(p.isEnabled);XCTAssertFalse(s.accepted.contains{$0.1.buttons != 0})
    }
}
