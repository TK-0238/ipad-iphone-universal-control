import Foundation
import XCTest
@testable import MouseLinkCore

final class HIDPeerRegistryTests: XCTestCase {
    func testNoReceiverBeforeActualSubscription() {
        let registry=HIDPeerRegistry();XCTAssertTrue(registry.mouseReceivers.isEmpty);XCTAssertTrue(registry.keyboardReceivers.isEmpty)
    }
    func testReportAndBootAreDifferentReadinessPaths() {
        var r=HIDPeerRegistry();let p=UUID();r.subscribe(.keyboardBoot,peer:p)
        XCTAssertFalse(r.keyboardReceivers.contains(p))
        r.setProtocol(0,peer:p);XCTAssertTrue(r.keyboardReceivers.contains(p))
        r.setProtocol(1,peer:p);XCTAssertFalse(r.keyboardReceivers.contains(p))
        r.subscribe(.keyboardReport,peer:p);XCTAssertTrue(r.keyboardReceivers.contains(p))
    }
    func testMouseAndKeyboardDoNotShareReportIdentity() {
        var r=HIDPeerRegistry();let p=UUID();r.subscribe(.mouseReport,peer:p)
        XCTAssertEqual(r.mouseReceivers,[p]);XCTAssertTrue(r.keyboardReceivers.isEmpty)
        r.subscribe(.keyboardReport,peer:p);r.unsubscribe(.mouseReport,peer:p)
        XCTAssertEqual(r.keyboardReceivers,[p]);XCTAssertTrue(r.mouseReceivers.isEmpty)
    }
    func testSuspendSurvivesAdditionalSubscriptions() {
        var r=HIDPeerRegistry();let p=UUID();r.subscribe(.mouseReport,peer:p);r.setSuspended(true,peer:p)
        r.subscribe(.keyboardReport,peer:p);r.subscribe(.mouseBoot,peer:p)
        XCTAssertTrue(r.mouseReceivers.isEmpty);XCTAssertTrue(r.keyboardReceivers.isEmpty)
        r.setSuspended(false,peer:p);XCTAssertEqual(r.mouseReceivers,[p]);XCTAssertEqual(r.keyboardReceivers,[p])
    }
    func testSuspendBeforeSubscriptionIsPreserved() {
        var r=HIDPeerRegistry();let p=UUID();r.setSuspended(true,peer:p);r.subscribe(.keyboardReport,peer:p)
        XCTAssertTrue(r.keyboardReceivers.isEmpty)
    }
    func testSamePeerReconnectionChangesEpoch() {
        var r=HIDPeerRegistry();let p=UUID();r.subscribe(.keyboardReport,peer:p);let old=r.epoch
        r.unsubscribe(.keyboardReport,peer:p);r.forget(p);r.subscribe(.keyboardReport,peer:p)
        XCTAssertNotEqual(old,r.epoch);XCTAssertEqual(r.keyboardReceivers,[p])
    }
    func testResetInvalidatesEpochEvenIfSamePeerReturns() {
        var r=HIDPeerRegistry();let p=UUID();r.subscribe(.keyboardReport,peer:p);let old=r.epoch
        r.reset();r.subscribe(.keyboardReport,peer:p);XCTAssertNotEqual(r.epoch,old)
    }
    func testDuplicateSubscribeDoesNotInterruptSession() {
        var r=HIDPeerRegistry();let p=UUID();r.subscribe(.keyboardReport,peer:p);let old=r.epoch
        r.subscribe(.keyboardReport,peer:p);XCTAssertEqual(r.epoch,old)
    }
    func testInvalidProtocolDoesNotMutateReadiness() {
        var r=HIDPeerRegistry();let p=UUID();r.subscribe(.keyboardReport,peer:p);let old=r.epoch
        XCTAssertFalse(r.setProtocol(2,peer:p));XCTAssertEqual(r.epoch,old);XCTAssertEqual(r.keyboardReceivers,[p])
    }
    func testSuspendOnePeerDoesNotEnableOrDisableAnother() {
        var r=HIDPeerRegistry();let a=UUID(),b=UUID();r.subscribe(.keyboardReport,peer:a);r.subscribe(.keyboardReport,peer:b)
        r.setSuspended(true,peer:a);XCTAssertEqual(r.keyboardReceivers,[b])
    }
    func testUnsubscribeBootDoesNotEraseReportOrMode() {
        var r=HIDPeerRegistry();let p=UUID();r.subscribe(.keyboardReport,peer:p);r.subscribe(.keyboardBoot,peer:p)
        r.unsubscribe(.keyboardBoot,peer:p);XCTAssertEqual(r.keyboardReceivers,[p]);XCTAssertEqual(r.protocolMode(for:p),1)
    }
    func testSeededPeerTransitionsNeverMakeSuspendedPeerReady() {
        var r=HIDPeerRegistry();let peers=(0..<4).map{_ in UUID()};var suspended=Set<UUID>();var rng:UInt64=32
        for _ in 0..<10_000 {
            rng=rng &* 6364136223846793005 &+ 1;let p=peers[Int((rng >> 8)%4)]
            switch rng%6 {
            case 0:r.setSuspended(true,peer:p);suspended.insert(p)
            case 1:r.setSuspended(false,peer:p);suspended.remove(p)
            case 2:r.subscribe(.keyboardReport,peer:p)
            case 3:r.subscribe(.mouseReport,peer:p)
            case 4:r.unsubscribe(.keyboardReport,peer:p)
            default:r.reset();suspended.removeAll()
            }
            XCTAssertTrue(r.mouseReceivers.isDisjoint(with:suspended));XCTAssertTrue(r.keyboardReceivers.isDisjoint(with:suspended))
        }
    }
}
