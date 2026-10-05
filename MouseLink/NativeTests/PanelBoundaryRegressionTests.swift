import XCTest
import Combine
import UIKit
@testable import MouseLink

@MainActor
private final class BoundaryMouseSender: PanelMouseSending {
    var mouseReceivers: Set<UUID> = []
    var inputEpoch: UInt64 = 1
    var response: MouseSendResult = .accepted
    var accepted: [(UUID, MouseFrame)] = []
    var onSend: ((MouseFrame) -> Void)?
    var disconnects = 0
    func sendPanelMouse(_ frame: MouseFrame, to peer: UUID) -> MouseSendResult {
        let result = response
        if result == .accepted { accepted.append((peer, frame)) }
        let callback = onSend; onSend = nil; callback?(frame)
        return result
    }
    func hardDisconnect() { disconnects += 1; inputEpoch &+= 1; mouseReceivers = [] }
}

/// Real UIKit windows and clipping; the sender is injected, not a Bluetooth device.
@MainActor
final class InputSurfaceGeometryTests: XCTestCase {
    private var window: UIWindow?
    private weak var original: UIWindow?
    override func tearDown() {
        window?.isHidden = true; window = nil; original?.makeKeyAndVisible()
        super.tearDown()
    }
    private func fixture() throws -> (UIView, UIView) {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        original = scene.windows.first { $0.isKeyWindow }
        let win = UIWindow(windowScene: scene)
        let root = UIViewController(); win.rootViewController = root; window = win
        win.makeKeyAndVisible(); root.view.layoutIfNeeded()
        let surface = UIView(frame: CGRect(x: 20, y: 20, width: 200, height: 120))
        root.view.addSubview(surface)
        XCTAssertTrue(InputWindowState.allowsInput(in: surface), "Visible fixture must be authorized first")
        return (root.view, surface)
    }
    func testOffWindowSurfaceCannotAuthorizeInput() throws {
        let (root, surface) = try fixture()
        surface.frame.origin.x = root.bounds.maxX + 20
        XCTAssertFalse(InputWindowState.allowsInput(in: surface))
    }
    func testZeroSizeSurfaceCannotAuthorizeInput() throws {
        let (_, surface) = try fixture(); surface.bounds.size = .zero
        XCTAssertFalse(InputWindowState.allowsInput(in: surface))
    }
    func testFullyClippedSurfaceCannotAuthorizeInput() throws {
        let (root, surface) = try fixture()
        let clip = UIView(frame: CGRect(x: 20, y: 20, width: 100, height: 100))
        clip.clipsToBounds = true; root.addSubview(clip); clip.addSubview(surface)
        surface.frame = CGRect(x: 0, y: 150, width: 80, height: 80)
        XCTAssertFalse(InputWindowState.allowsInput(in: surface))
    }
    func testScrollBoundsHideSurfaceWithoutChangingHiddenFlag() throws {
        let (root, surface) = try fixture()
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 250, height: 250))
        root.addSubview(scroll); scroll.addSubview(surface)
        scroll.contentSize = CGSize(width: 250, height: 1000)
        scroll.contentOffset = CGPoint(x: 0, y: 400)
        XCTAssertFalse(surface.isHidden)
        XCTAssertFalse(InputWindowState.allowsInput(in: surface))
    }
    func testPartiallyVisibleSurfaceRemainsUsable() throws {
        let (root, surface) = try fixture()
        let clip = UIView(frame: CGRect(x: 20, y: 20, width: 100, height: 100))
        clip.clipsToBounds = true; root.addSubview(clip); clip.addSubview(surface)
        surface.frame = CGRect(x: 50, y: 20, width: 80, height: 60)
        XCTAssertTrue(InputWindowState.allowsInput(in: surface))
    }
    func testUnclippedOverflowStillVisibleInWindowIsAllowed() throws {
        let (root, surface) = try fixture()
        let parent = UIView(frame: CGRect(x: 20, y: 20, width: 50, height: 50))
        parent.clipsToBounds = false; root.addSubview(parent); parent.addSubview(surface)
        surface.frame = CGRect(x: 70, y: 0, width: 80, height: 60)
        XCTAssertTrue(InputWindowState.allowsInput(in: surface))
    }
    func testHiddenAncestorBlocksSurface() throws {
        let (root, surface) = try fixture(); root.isHidden = true
        XCTAssertFalse(InputWindowState.allowsInput(in: surface))
    }
    func testAlphaHiddenAncestorBlocksSurface() throws {
        let (root, surface) = try fixture(); root.alpha = 0
        XCTAssertFalse(InputWindowState.allowsInput(in: surface))
    }
    func testDetachedSurfaceBlocksInput() throws {
        let (_, surface) = try fixture(); surface.removeFromSuperview()
        XCTAssertFalse(InputWindowState.allowsInput(in: surface))
    }
    func testClippingDuringDragReleasesWithoutReplayingMovement() throws {
        let (root, _) = try fixture()
        let sender = BoundaryMouseSender(), peer = UUID(); sender.mouseReceivers = [peer]
        let panel = PanelSession(sender: sender, clock: { 1 }, ticks: Empty<Date, Never>().eraseToAnyPublisher())
        let pad = LocalPadView(panel: panel)
        pad.frame = CGRect(x: 10, y: 10, width: 200, height: 120); root.addSubview(pad)
        panel.enable(peer: peer); panel.move(x: 20, y: 20, width: 200, height: 120); panel.buttons(1)
        XCTAssertEqual(sender.accepted.last?.1.buttons, 1)
        pad.frame.origin.y = root.bounds.maxY + 50
        panel.pump()
        XCTAssertFalse(panel.isEnabled)
        XCTAssertEqual(sender.accepted.last?.1, .zero)
        let count = sender.accepted.count
        pad.frame.origin.y = 10; panel.pump()
        XCTAssertEqual(sender.accepted.count, count)
    }
}

/// Adversarial synchronous sender callbacks exercise the same production queue.
@MainActor
final class PanelTransactionBoundaryTests: XCTestCase {
    private var time: Double = 1
    private func fixture() -> (PanelSession, BoundaryMouseSender, UUID) {
        let sender = BoundaryMouseSender(), peer = UUID(); sender.mouseReceivers = [peer]
        let panel = PanelSession(sender: sender, clock: { self.time }, ticks: Empty<Date, Never>().eraseToAnyPublisher())
        panel.surfaceIsUsable = { true }; panel.enable(peer: peer)
        panel.move(x: 20, y: 20, width: 300, height: 200)
        return (panel, sender, peer)
    }
    func testReentryDuringAcceptedWriteDoesNotConsumeNewBaseline() {
        let (panel, sender, _) = fixture()
        sender.response = .busy; panel.move(x: 30, y: 20, width: 300, height: 200)
        sender.response = .accepted
        sender.onSend = { _ in
            panel.leave()
            panel.move(x: 100, y: 100, width: 300, height: 200)
            panel.buttons(1)
        }
        panel.pump()
        XCTAssertFalse(sender.accepted.contains { $0.1.buttons == 1 }, "Old write must not drain a new pointer visit")
        let count = sender.accepted.count
        panel.pump()
        XCTAssertEqual(Array(sender.accepted.dropFirst(count).map { $0.1 }), [.zero, MouseFrame(buttons: 1)])
    }
    func testReenableDuringBusyWriteDoesNotCancelNewSession() {
        let (panel, sender, peer) = fixture()
        sender.response = .busy; panel.move(x: 30, y: 20, width: 300, height: 200)
        sender.response = .unavailable
        sender.onSend = { _ in
            sender.response = .accepted
            panel.disable(); panel.enable(peer: peer)
            panel.move(x: 100, y: 100, width: 300, height: 200)
        }
        panel.pump()
        XCTAssertTrue(panel.isEnabled, "A stale send result must not disable a newly authorized session")
        let count = sender.accepted.count; panel.pump()
        XCTAssertEqual(Array(sender.accepted.dropFirst(count).map { $0.1 }), [.zero])
    }
    func testNegativeClockAfterBaselineCannotSendClick() {
        let (panel, sender, _) = fixture(); time = -1; panel.buttons(1)
        XCTAssertFalse(sender.accepted.contains { $0.1.buttons == 1 })
        XCTAssertFalse(panel.isEnabled)
    }
    func testBackwardsClockAfterBaselineCannotSendClick() {
        let (panel, sender, _) = fixture(); time = 0.5; panel.buttons(1)
        XCTAssertFalse(sender.accepted.contains { $0.1.buttons == 1 })
        XCTAssertFalse(panel.isEnabled)
    }
    func testCancelInsideSendCannotRestartOldQueue() {
        let (panel, sender, _) = fixture()
        sender.response = .busy; panel.buttons(1); panel.buttons(0)
        sender.response = .accepted; sender.onSend = { _ in panel.disable() }
        panel.pump(); let count = sender.accepted.count; panel.pump()
        XCTAssertFalse(panel.isEnabled); XCTAssertEqual(sender.accepted.count, count)
        XCTAssertEqual(sender.accepted.last?.1, .zero)
    }
}
