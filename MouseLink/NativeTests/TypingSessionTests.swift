import XCTest
import Combine
@testable import MouseLink

@MainActor
private final class CaptureSender: KeyboardSending {
    var keyboardReceivers:Set<UUID>=[]
    var accepted:[(UUID,Data)]=[]
    var attempts:[(UUID,Data)]=[]
    var response:KeyboardSendResult = .accepted
    var disconnected=false
    func sendKeyboardBytes(_ data:Data,to peer:UUID) -> KeyboardSendResult {
        attempts.append((peer,data))
        if response == .accepted { accepted.append((peer,data)) }
        return response
    }
    func hardDisconnect() { disconnected=true;keyboardReceivers=[] }
}
@MainActor
final class TypingSessionTests: XCTestCase {
    private var time:TimeInterval=1
    private func setup() -> (TypingSession,CaptureSender,UUID) {
        let sender=CaptureSender();let peer=UUID();sender.keyboardReceivers=[peer]
        let model=TypingSession(sender:sender,clock:{ self.time },ticks:Empty<Date,Never>().eraseToAnyPublisher())
        model.open(peer:peer);return (model,sender,peer)
    }
    private func finish(_ model:TypingSession) {
        for _ in 0..<100 { time += 0.021;model.pump();if !model.isSending { break } }
    }
    func testDraftNeverSendsUntilButtonAction() {
        let (model,sender,_)=setup();model.draft="Hello"
        time+=0.1;model.pump();XCTAssertTrue(sender.accepted.isEmpty)
    }
    func testTextThenExactlyOneEnterOnSelectedReceiver() {
        let (model,sender,peer)=setup();model.draft="ab";model.sendDraft(enter:true);finish(model)
        XCTAssertEqual(sender.accepted.map{$0.1},[KeyboardStroke.zero.data,KeyboardStroke(usage:4).data,KeyboardStroke.zero.data,KeyboardStroke(usage:5).data,KeyboardStroke.zero.data,KeyboardStroke.enter.data,KeyboardStroke.zero.data])
        XCTAssertTrue(sender.accepted.allSatisfy{$0.0==peer});XCTAssertFalse(model.isSending)
    }
    func testEnterOnlyNeverIncludesUnsentDraft() {
        let (model,sender,_)=setup();model.draft="must stay local";model.sendKey(.enter);finish(model)
        XCTAssertEqual(sender.accepted.map{$0.1},[KeyboardStroke.zero.data,KeyboardStroke.enter.data,KeyboardStroke.zero.data])
    }
    func testUnsupportedDraftIsAtomicEvenWithEnterRequested() {
        let (model,sender,_)=setup();model.draft="hello日本";model.sendDraft(enter:true)
        XCTAssertTrue(sender.attempts.isEmpty);XCTAssertFalse(model.isSending);XCTAssertNotNil(model.validation)
    }
    func testKanaReadingReachesSameRealSendPath() {
        let (model,sender,_)=setup();model.mode = .kanaReading;model.draft="ねこ";model.sendDraft(enter:false);finish(model)
        XCTAssertEqual(sender.accepted.map{$0.1},try! KeyboardPlan.text("neko",mode:.ascii,enter:false).reports.map(\.data))
    }
    func testCancelReleasesAndDiscardsQueuedEnter() {
        let (model,sender,_)=setup();model.draft="long";model.sendDraft(enter:true)
        time+=0.021;model.pump();model.cancel();finish(model)
        XCTAssertEqual(sender.accepted.last?.1,KeyboardStroke.zero.data)
        XCTAssertFalse(sender.accepted.contains{$0.1==KeyboardStroke.enter.data})
    }
    func testBackgroundReleaseDoesNotAutomaticallyResume() {
        let (model,sender,_)=setup();model.draft="hi";model.sendDraft(enter:true)
        time+=0.021;model.pump();model.setForeground(false)
        let count=sender.accepted.count;model.setForeground(true);finish(model)
        XCTAssertEqual(sender.accepted.count,count);XCTAssertFalse(model.isSending)
    }
    func testFailedReleaseDisconnectsInsteadOfLeavingHeldKey() {
        let (model,sender,_)=setup();model.sendKey(.enter)
        time+=0.021;model.pump();sender.response = .busy;model.cancel()
        XCTAssertTrue(sender.disconnected);XCTAssertFalse(model.isSending)
    }
    func testUnavailableTargetNeverReceivesAnyInput() {
        let (model,sender,_)=setup();sender.keyboardReceivers=[];model.sendKey(.enter)
        XCTAssertTrue(sender.attempts.isEmpty)
    }
    func testStallDoesNotEventuallySendAnOldEnter() {
        let (model,sender,_)=setup();sender.response = .busy;model.draft="hi";model.sendDraft(enter:true)
        time+=0.501;model.pump();XCTAssertFalse(model.isSending);XCTAssertTrue(sender.disconnected)
        sender.response = .accepted;finish(model);XCTAssertTrue(sender.accepted.isEmpty)
    }
    func testSwitchReceiverCannotLeakOldDraft() {
        let (model,sender,old)=setup();model.draft="hi";model.sendDraft(enter:true)
        let new=UUID();sender.keyboardReceivers.insert(new);model.open(peer:new);finish(model)
        XCTAssertTrue(sender.accepted.allSatisfy{$0.0==old});XCTAssertFalse(model.isSending)
    }
    func testCloseKeepsLocalDraftButStopsTransfer() {
        let (model,sender,_)=setup();model.draft="local";model.close();model.sendKey(.enter)
        XCTAssertTrue(sender.attempts.isEmpty);XCTAssertEqual(model.draft,"local");XCTAssertFalse(model.canSend)
    }
}
