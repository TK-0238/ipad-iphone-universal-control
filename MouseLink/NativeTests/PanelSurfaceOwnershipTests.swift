import XCTest
import Combine
import UIKit
@testable import MouseLink

@MainActor
private final class SurfaceSender: PanelMouseSending {
    let peer = UUID()
    var connected = true
    var mouseReceivers: Set<UUID> { connected ? [peer] : [] }
    var inputEpoch: UInt64 = 1
    var writes: [MouseFrame] = []
    var response: MouseSendResult = .accepted
    var disconnects = 0
    func sendPanelMouse(_ frame: MouseFrame, to peer: UUID) -> MouseSendResult {
        XCTAssertEqual(peer, self.peer)
        writes.append(frame); return response
    }
    func hardDisconnect() { connected = false; inputEpoch &+= 1; disconnects += 1 }
}

/// Real UIKit attachment/detachment; output is injected, never sent over Bluetooth.
@MainActor
final class PanelSurfaceOwnershipTests: XCTestCase {
    private var window: UIWindow?
    private weak var previousWindow: UIWindow?
    override func tearDown() {
        window?.isHidden = true; window = nil
        previousWindow?.makeKeyAndVisible()
        super.tearDown()
    }
    private func fixture() throws -> (PanelSession, SurfaceSender, UIView, LocalPadView) {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        previousWindow = scene.windows.first { $0.isKeyWindow }
        let win = UIWindow(windowScene: scene), controller = UIViewController()
        win.rootViewController = controller; window = win; win.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        let sender = SurfaceSender()
        let panel = PanelSession(sender: sender, clock: { 1 }, ticks: Empty<Date, Never>().eraseToAnyPublisher())
        let pad = LocalPadView(panel: panel)
        pad.frame = CGRect(x: 20, y: 40, width: 320, height: 200)
        controller.view.addSubview(pad); pad.layoutIfNeeded()
        XCTAssertTrue(pad.usable, "Fixture must be visible and focused")
        startDrag(panel, sender)
        return (panel, sender, controller.view, pad)
    }
    private func startDrag(_ panel: PanelSession, _ sender: SurfaceSender) {
        panel.enable(peer: sender.peer)
        panel.move(x: 20, y: 20, width: 320, height: 200); panel.buttons(1)
        XCTAssertTrue(panel.isEnabled); XCTAssertTrue(panel.isInside)
        XCTAssertEqual(sender.writes.last, MouseFrame(buttons: 1))
    }
    private func replacement(_ panel: PanelSession, _ sender: SurfaceSender, _ root: UIView) -> LocalPadView {
        let view = LocalPadView(panel: panel)
        view.frame = CGRect(x: 20, y: 260, width: 320, height: 200)
        root.addSubview(view); view.layoutIfNeeded()
        // Explicit reauthorization is required even when both views briefly coexist.
        panel.disable(); startDrag(panel, sender); sender.writes = []
        return view
    }
    func testConstructingUnattachedPadDoesNotRevokeVisiblePad() throws {
        let (panel, sender, _, old) = try fixture()
        let candidate = LocalPadView(panel: panel)
        defer { withExtendedLifetime(candidate) {} }
        XCTAssertTrue(panel.surfaceIsUsable(), "Construction alone cannot steal surface ownership")
        let count = sender.writes.count; panel.pump()
        XCTAssertTrue(panel.isEnabled); XCTAssertTrue(old.usable)
        XCTAssertEqual(sender.writes.count, count)
    }
    func testAttachingReplacementReleasesOldDragAndRequiresExplicitEnable() throws {
        let (panel, sender, root, old) = try fixture()
        let next = LocalPadView(panel: panel)
        next.frame = CGRect(x: 20, y: 260, width: 320, height: 200); root.addSubview(next)
        XCTAssertFalse(panel.isEnabled)
        XCTAssertFalse(panel.isInside)
        XCTAssertEqual(sender.writes.last, .zero)
        XCTAssertFalse(old.usable, "Only one UIKit surface may originate input")
        XCTAssertTrue(next.usable)
    }
    func testRemovingOldPadDoesNotCancelNewDrag() throws {
        let (panel, sender, root, old) = try fixture()
        let next = replacement(panel, sender, root)
        old.removeFromSuperview()
        XCTAssertTrue(panel.isEnabled); XCTAssertTrue(panel.isInside); XCTAssertTrue(next.usable)
        XCTAssertTrue(sender.writes.isEmpty)
    }
    func testDismantlingOldPadDoesNotCancelNewDrag() throws {
        let (panel, sender, root, old) = try fixture()
        let next = replacement(panel, sender, root)
        PanelPadView.dismantleUIView(old, coordinator: ())
        XCTAssertTrue(panel.isEnabled); XCTAssertTrue(next.usable)
        XCTAssertTrue(sender.writes.isEmpty)
    }
    func testStaleLayoutCannotCancelNewDrag() throws {
        let (panel, sender, root, old) = try fixture()
        let next = replacement(panel, sender, root)
        old.frame.size.width = 250; old.setNeedsLayout(); old.layoutIfNeeded()
        XCTAssertTrue(panel.isEnabled); XCTAssertTrue(next.usable)
        XCTAssertTrue(sender.writes.isEmpty)
    }
    func testStaleCancellationCannotReleaseNewDrag() throws {
        let (panel, sender, root, old) = try fixture()
        let next = replacement(panel, sender, root)
        old.touchesCancelled([], with: nil)
        XCTAssertTrue(panel.isEnabled); XCTAssertTrue(panel.isInside); XCTAssertTrue(next.usable)
        XCTAssertTrue(sender.writes.isEmpty)
    }
    func testRemovingCurrentPadReleasesBeforeReturning() throws {
        let (panel, sender, _, pad) = try fixture()
        sender.writes = []; pad.removeFromSuperview()
        XCTAssertEqual(sender.writes, [.zero]); XCTAssertFalse(panel.isEnabled)
        XCTAssertFalse(panel.surfaceIsUsable())
        panel.enable(peer: sender.peer)
        XCTAssertFalse(panel.isEnabled)
    }
    func testDismantlingCurrentPadRevokesPermissionBeforePhysicalRemoval() throws {
        let (panel, sender, _, pad) = try fixture()
        sender.writes = []
        PanelPadView.dismantleUIView(pad, coordinator: ())
        XCTAssertNotNil(pad.window, "Dismantle precedes physical removal")
        XCTAssertEqual(sender.writes, [.zero])
        XCTAssertFalse(pad.usable); XCTAssertFalse(panel.surfaceIsUsable())
        panel.enable(peer: sender.peer)
        XCTAssertFalse(panel.isEnabled)
    }
    func testReattachingSamePadDoesNotResumeOldClick() throws {
        let (panel, sender, root, pad) = try fixture()
        pad.removeFromSuperview(); sender.writes = []
        root.addSubview(pad); panel.pump()
        XCTAssertTrue(pad.usable); XCTAssertFalse(panel.isEnabled)
        XCTAssertTrue(sender.writes.isEmpty)
        startDrag(panel, sender)
        XCTAssertEqual(sender.writes, [.zero, MouseFrame(buttons: 1)])
    }
    func testReplacementWithBlockedReleaseDisconnectsInsteadOfHoldingButton() throws {
        let (panel, sender, root, _) = try fixture(); sender.response = .busy
        let next = LocalPadView(panel: panel)
        next.frame = CGRect(x: 20, y: 260, width: 320, height: 200); root.addSubview(next)
        XCTAssertEqual(sender.disconnects, 1)
        XCTAssertFalse(panel.isEnabled); XCTAssertEqual(sender.writes.last, .zero)
    }
}
