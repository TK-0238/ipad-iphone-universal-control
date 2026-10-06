import XCTest
import Combine
import UIKit
@testable import MouseLink

/// Only location/type are synthesized. The actual LocalPadView event handlers,
/// PanelSession, report queue and UIKit window visibility gates run unchanged.
@MainActor
private final class PadContact: UITouch {
    var point = CGPoint(x: 20, y: 20)
    var inputType: UITouch.TouchType = .direct
    override var type: UITouch.TouchType { inputType }
    override func location(in view: UIView?) -> CGPoint { point }
}
@MainActor
private final class ContactSender: PanelMouseSending {
    let peer = UUID()
    var mouseReceivers: Set<UUID> = []
    var inputEpoch: UInt64 = 1
    var writes: [(UUID, MouseFrame)] = []
    init() { mouseReceivers = [peer] }
    func sendPanelMouse(_ frame: MouseFrame, to peer: UUID) -> MouseSendResult {
        writes.append((peer, frame)); return .accepted
    }
    func hardDisconnect() { inputEpoch &+= 1; mouseReceivers = [] }
}
@MainActor
final class PanelContactLifecycleTests: XCTestCase {
    private var window: UIWindow?
    private var retainedPanel: PanelSession?
    private weak var originalWindow: UIWindow?
    override func tearDown() {
        window?.isHidden = true; window = nil; retainedPanel = nil
        originalWindow?.makeKeyAndVisible(); super.tearDown()
    }
    private func fixture(enabled: Bool = true) throws -> (PanelSession, ContactSender, LocalPadView) {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        originalWindow = scene.windows.first { $0.isKeyWindow }
        let sender = ContactSender()
        let panel = PanelSession(sender: sender, clock: { 1 }, ticks: Empty<Date, Never>().eraseToAnyPublisher())
        retainedPanel = panel // LocalPadView intentionally holds only a weak model reference.
        let win = UIWindow(windowScene: scene), controller = UIViewController()
        win.rootViewController = controller; window = win; win.makeKeyAndVisible()
        let pad = LocalPadView(panel: panel)
        pad.frame = CGRect(x: 20, y: 80, width: 320, height: 200)
        controller.view.addSubview(pad); controller.view.layoutIfNeeded(); pad.layoutIfNeeded()
        XCTAssertTrue(pad.usable)
        if enabled { panel.enable(peer: sender.peer); XCTAssertTrue(panel.isEnabled) }
        return (panel, sender, pad)
    }
    private func begin(_ pad: LocalPadView, mouse: Bool = false) -> PadContact {
        let touch = PadContact(); touch.inputType = mouse ? .indirectPointer : .direct
        pad.touchesBegan([touch], with: nil); return touch
    }
    private func reenable(_ panel: PanelSession, _ sender: ContactSender) {
        panel.disable(); panel.enable(peer: sender.peer)
        panel.move(x: 100, y: 100, width: 320, height: 200)
        XCTAssertTrue(panel.isEnabled); XCTAssertTrue(panel.isInside)
        sender.writes = []
    }
    func testNormalFingerTapPressesOnceAndReleasesSelectedPeer() throws {
        let (_, sender, pad) = try fixture(); let t = begin(pad)
        pad.touchesEnded([t], with: nil)
        XCTAssertEqual(sender.writes.filter { $0.1.buttons == 1 }.count, 1)
        XCTAssertEqual(sender.writes.last?.1, .zero)
        XCTAssertTrue(sender.writes.allSatisfy { $0.0 == sender.peer })
    }
    func testFinalOnlyFingerDisplacementIsMovementNotClick() throws {
        let (_, sender, pad) = try fixture(); let t = begin(pad)
        t.point = CGPoint(x: 60, y: 35); pad.touchesEnded([t], with: nil)
        XCTAssertEqual(sender.writes.reduce(0) { $0 + Int($1.1.x) }, 40)
        XCTAssertEqual(sender.writes.reduce(0) { $0 + Int($1.1.y) }, 15)
        XCTAssertFalse(sender.writes.contains { $0.1.buttons != 0 })
    }
    func testTerminalFingerSampleIsNotLostAfterEarlierMove() throws {
        let (_, sender, pad) = try fixture(); let t = begin(pad)
        t.point = CGPoint(x: 30, y: 20); pad.touchesMoved([t], with: nil)
        t.point = CGPoint(x: 45, y: 25); pad.touchesEnded([t], with: nil)
        XCTAssertEqual(sender.writes.reduce(0) { $0 + Int($1.1.x) }, 25)
        XCTAssertEqual(sender.writes.reduce(0) { $0 + Int($1.1.y) }, 5)
        XCTAssertFalse(sender.writes.contains { $0.1.buttons != 0 })
    }
    func testTerminalMouseSamplePrecedesButtonRelease() throws {
        let (_, sender, pad) = try fixture(); let t = begin(pad, mouse: true)
        t.point = CGPoint(x: 40, y: 30); pad.touchesEnded([t], with: nil)
        XCTAssertTrue(sender.writes.contains { $0.1 == MouseFrame(buttons: 1, x: 20, y: 10) })
        XCTAssertEqual(sender.writes.last?.1, .zero)
    }
    func testLiftOutsidePadReleasesWithoutOutsideMovement() throws {
        let (_, sender, pad) = try fixture(); let t = begin(pad, mouse: true)
        t.point = CGPoint(x: 400, y: 20); pad.touchesEnded([t], with: nil)
        XCTAssertEqual(sender.writes.last?.1, .zero)
        XCTAssertFalse(sender.writes.contains { $0.1.x != 0 || $0.1.y != 0 })
    }
    func testOldFingerLiftCannotClickAfterExplicitReenable() throws {
        let (panel, sender, pad) = try fixture(); let t = begin(pad)
        reenable(panel, sender); pad.touchesEnded([t], with: nil)
        XCTAssertTrue(sender.writes.isEmpty); XCTAssertTrue(panel.isEnabled); XCTAssertTrue(panel.isInside)
    }
    func testOldMouseMoveCannotMoveNewVisit() throws {
        let (panel, sender, pad) = try fixture(); let t = begin(pad, mouse: true)
        reenable(panel, sender); t.point = CGPoint(x: 60, y: 40); pad.touchesMoved([t], with: nil)
        XCTAssertTrue(sender.writes.isEmpty); XCTAssertTrue(panel.isEnabled); XCTAssertTrue(panel.isInside)
    }
    func testOldMouseLiftCannotReleaseNewDrag() throws {
        let (panel, sender, pad) = try fixture(); let t = begin(pad, mouse: true)
        reenable(panel, sender); panel.buttons(1); sender.writes = []
        pad.touchesEnded([t], with: nil)
        XCTAssertTrue(sender.writes.isEmpty); XCTAssertTrue(panel.isEnabled); XCTAssertTrue(panel.isInside)
    }
    func testOldMouseCancellationCannotReleaseNewDrag() throws {
        let (panel, sender, pad) = try fixture(); let t = begin(pad, mouse: true)
        reenable(panel, sender); panel.buttons(1); sender.writes = []
        pad.touchesCancelled([t], with: nil)
        XCTAssertTrue(sender.writes.isEmpty); XCTAssertTrue(panel.isEnabled); XCTAssertTrue(panel.isInside)
    }
    func testTouchBeginningWhileDisabledCannotJoinLaterVisit() throws {
        let (panel, sender, pad) = try fixture(enabled: false); let t = begin(pad)
        panel.enable(peer: sender.peer); panel.move(x: 100, y: 100, width: 320, height: 200)
        sender.writes = []; pad.touchesEnded([t], with: nil)
        XCTAssertTrue(sender.writes.isEmpty); XCTAssertTrue(panel.isEnabled); XCTAssertTrue(panel.isInside)
    }
    func testOldContactCannotCrossSameUUIDReconnection() throws {
        let (panel, sender, pad) = try fixture(); let t = begin(pad)
        sender.inputEpoch &+= 1; panel.pump(); sender.mouseReceivers = [sender.peer]
        panel.enable(peer: sender.peer); panel.move(x: 100, y: 100, width: 320, height: 200)
        sender.writes = []; pad.touchesEnded([t], with: nil)
        XCTAssertTrue(sender.writes.isEmpty); XCTAssertTrue(panel.isEnabled)
    }
    func testHiddenSurfaceMouseLiftReleasesBeforeReturning() throws {
        let (panel, sender, pad) = try fixture(); let t = begin(pad, mouse: true)
        sender.writes = []; pad.isHidden = true; pad.touchesEnded([t], with: nil)
        XCTAssertEqual(sender.writes.map { $0.1 }, [.zero]); XCTAssertFalse(panel.isEnabled)
    }
    func testFreshContactAfterStaleLiftStillWorks() throws {
        let (panel, sender, pad) = try fixture(); let old = begin(pad)
        reenable(panel, sender); pad.touchesEnded([old], with: nil); sender.writes = []
        let fresh = begin(pad); pad.touchesEnded([fresh], with: nil)
        XCTAssertEqual(sender.writes.filter { $0.1.buttons == 1 }.count, 1)
        XCTAssertEqual(sender.writes.last?.1, .zero)
    }
    func testCancelledCurrentFingerNeverBecomesClick() throws {
        let (_, sender, pad) = try fixture(); let t = begin(pad)
        pad.touchesCancelled([t], with: nil); pad.touchesEnded([t], with: nil)
        XCTAssertFalse(sender.writes.contains { $0.1.buttons != 0 })
    }
}
