import XCTest
import Combine
import UIKit
@testable import MouseLink

@MainActor
private final class ReentrantKeyboardSender: KeyboardSending {
    var keyboardReceivers: Set<UUID> = []
    var inputEpoch: UInt64 = 1
    var writes: [(UUID, Data)] = []
    var onSend: (() -> Void)?
    var disconnects = 0
    func sendKeyboardBytes(_ bytes: Data, to peer: UUID) -> KeyboardSendResult {
        writes.append((peer, bytes))
        let action = onSend; onSend = nil; action?()
        return .accepted
    }
    func hardDisconnect() { disconnects += 1; inputEpoch &+= 1; keyboardReceivers = [] }
}

/// Injected callbacks exercise production TypingSession, never a real iPhone.
@MainActor
final class TypingReentrancyRegressionTests: XCTestCase {
    private var now: Double = 1
    private var visible = true
    private func fixture() -> (TypingSession, ReentrantKeyboardSender, UUID) {
        let sender = ReentrantKeyboardSender(), peer = UUID(); sender.keyboardReceivers = [peer]
        let model = TypingSession(sender: sender, clock: { self.now },
            ticks: Empty<Date, Never>().eraseToAnyPublisher(), inputSurfaceCheck: { self.visible })
        model.open(peer: peer); return (model, sender, peer)
    }
    private func tick(_ model: TypingSession, count: Int = 12) {
        for _ in 0..<count { now += 0.021; model.pump() }
    }
    func testCancelCannotStartAnotherTransactionInsideRelease() {
        let (model, sender, _) = fixture(); model.draft = "ab"; model.sendDraft(enter: true); tick(model, count: 1)
        let count = sender.writes.count
        sender.onSend = { model.sendKey(.enter) }
        model.cancel(); tick(model)
        XCTAssertEqual(sender.writes.dropFirst(count).map { $0.1 }, [KeyboardStroke.zero.data])
        XCTAssertFalse(model.isSending); XCTAssertEqual(model.remaining, 0)
        XCTAssertEqual(sender.disconnects, 0)
    }
    func testCloseCannotStartAnotherTransactionInsideRelease() {
        let (model, sender, _) = fixture(); model.sendKey(.space); tick(model, count: 1)
        let count = sender.writes.count
        sender.onSend = { model.sendCharacter("q") }
        model.close(); tick(model)
        XCTAssertEqual(sender.writes.dropFirst(count).map { $0.1 }, [KeyboardStroke.zero.data])
        XCTAssertFalse(model.canSend); XCTAssertFalse(model.isSending)
    }
    func testSwitchingReceiverRejectsReleaseCallbackSubmission() {
        let (model, sender, old) = fixture(); model.draft = "ab"; model.sendDraft(enter: true)
        let new = UUID(); sender.keyboardReceivers.insert(new)
        let count = sender.writes.count
        sender.onSend = { model.sendKey(.enter) }
        model.open(peer: new); tick(model)
        XCTAssertEqual(sender.writes.dropFirst(count).map { $0.0 }, [old])
        XCTAssertEqual(sender.writes.last?.1, KeyboardStroke.zero.data)
        XCTAssertFalse(model.isSending)
    }
    func testNewExplicitSubmitAfterCancelStillWorks() {
        let (model, sender, peer) = fixture(); model.sendKey(.space); model.cancel()
        let count = sender.writes.count
        model.sendKey(.enter); tick(model)
        XCTAssertEqual(sender.writes.dropFirst(count).map { $0.1 },
            [KeyboardStroke.zero.data, KeyboardStroke.enter.data, KeyboardStroke.zero.data])
        XCTAssertTrue(sender.writes.allSatisfy { $0.0 == peer }); XCTAssertFalse(model.isSending)
    }
    func testConnectionChangeInsideWriteStopsBeforePumpReturns() {
        let (model, sender, _) = fixture(); model.draft = "ab"; model.sendDraft(enter: true)
        sender.onSend = { sender.inputEpoch &+= 1 }
        tick(model, count: 1)
        XCTAssertFalse(model.isSending); XCTAssertEqual(model.remaining, 0)
        XCTAssertEqual(sender.disconnects, 1)
        let count = sender.writes.count; tick(model); XCTAssertEqual(sender.writes.count, count)
        XCTAssertFalse(sender.writes.contains { $0.1 == KeyboardStroke.enter.data })
    }
    func testSurfaceLossInsideWriteReleasesBeforePumpReturns() {
        let (model, sender, _) = fixture(); model.draft = "ab"; model.sendDraft(enter: true)
        sender.onSend = { self.visible = false }
        tick(model, count: 1)
        XCTAssertFalse(model.isSending); XCTAssertEqual(sender.writes.last?.1, KeyboardStroke.zero.data)
        let count = sender.writes.count; visible = true; tick(model)
        XCTAssertEqual(sender.writes.count, count)
        XCTAssertFalse(sender.writes.contains { $0.1 == KeyboardStroke.enter.data })
    }
}

@MainActor
final class TypingPresentationRegressionTests: XCTestCase {
    private func drainMainQueue() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
    private func fixture() -> (TypingSession, ReentrantKeyboardSender, UUID) {
        let sender = ReentrantKeyboardSender(), peer = UUID(); sender.keyboardReceivers = [peer]
        let model = TypingSession(sender: sender, clock: { 1 },
            ticks: Empty<Date, Never>().eraseToAnyPublisher())
        return (model, sender, peer)
    }
    func testIdleSurfaceAttachmentDoesNotPublishUnchangedState() async {
        let (model, sender, _) = fixture(); var publications = 0
        let token = model.objectWillChange.sink { publications += 1 }; defer { token.cancel() }
        let owner = UUID(); model.bindInputSurface(owner: owner, check: { false })
        model.cancel(); model.unbindInputSurface(owner: owner)
        XCTAssertEqual(publications, 0)
        await drainMainQueue(); XCTAssertEqual(publications, 0); XCTAssertTrue(sender.writes.isEmpty)
    }
    func testWindowBindingUpdatesPermissionImmediatelyButPublishesLater() async {
        let (model, sender, peer) = fixture(); model.open(peer: peer)
        await drainMainQueue()
        var publications = 0
        let token = model.objectWillChange.sink { publications += 1 }; defer { token.cancel() }
        model.bindInputSurface(owner: UUID(), check: { true })
        XCTAssertTrue(model.canSend); XCTAssertTrue(model.available)
        XCTAssertEqual(publications, 0, "Do not publish inside UIViewRepresentable attachment")
        await drainMainQueue(); XCTAssertEqual(publications, 1); XCTAssertTrue(sender.writes.isEmpty)
    }
    func testDetachStopsSynchronouslyBeforeDeferredPresentation() async {
        let (model, sender, peer) = fixture(); let owner = UUID()
        model.bindInputSurface(owner: owner, check: { true }); model.open(peer: peer); model.sendKey(.enter)
        await drainMainQueue()
        var publications = 0
        let token = model.objectWillChange.sink { publications += 1 }; defer { token.cancel() }
        model.unbindInputSurface(owner: owner)
        XCTAssertFalse(model.canSend); XCTAssertFalse(model.isSending); XCTAssertEqual(model.remaining, 0)
        XCTAssertEqual(sender.writes.last?.1, KeyboardStroke.zero.data)
        XCTAssertEqual(publications, 0, "Input stops now; UI invalidation waits until this update finishes")
        await drainMainQueue(); XCTAssertEqual(publications, 1)
        XCTAssertFalse(sender.writes.contains { $0.1 == KeyboardStroke.enter.data })
    }
    func testRapidOpenCloseCoalescesAndNeverRestoresOldPermission() async {
        let (model, sender, peer) = fixture(); model.bindInputSurface(owner: UUID(), check: { true })
        await drainMainQueue(); var publications = 0
        let token = model.objectWillChange.sink { publications += 1 }; defer { token.cancel() }
        for _ in 0..<50 { model.open(peer: peer); model.close() }
        XCTAssertFalse(model.canSend); XCTAssertEqual(publications, 0)
        await drainMainQueue(); XCTAssertEqual(publications, 1)
        XCTAssertFalse(model.available); XCTAssertTrue(sender.writes.isEmpty)
    }
    func testDeferredNotificationDoesNotRetainSession() async {
        let sender = ReentrantKeyboardSender(); let peer = UUID(); sender.keyboardReceivers = [peer]
        var model: TypingSession? = TypingSession(sender: sender, ticks: Empty<Date, Never>().eraseToAnyPublisher())
        weak var weakModel = model
        model?.open(peer: peer); model = nil
        XCTAssertNil(weakModel); await drainMainQueue(); XCTAssertTrue(sender.writes.isEmpty)
    }
    func testEditableDraftPublisherStillWorks() {
        let (model, sender, _) = fixture(); var values: [String] = []
        let token = model.$draft.sink { values.append($0) }; defer { token.cancel() }
        model.draft = "local only"
        XCTAssertEqual(values, ["", "local only"]); XCTAssertTrue(sender.writes.isEmpty)
    }
}

@MainActor
final class InputOpacityRegressionTests: XCTestCase {
    private var window: UIWindow?
    private weak var original: UIWindow?
    override func tearDown() { window?.isHidden = true; window = nil; original?.makeKeyAndVisible(); super.tearDown() }
    private func fixture() throws -> (UIView, UIView) {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        original = scene.windows.first { $0.isKeyWindow }
        let win = UIWindow(windowScene: scene); window = win
        let root = UIViewController(); win.rootViewController = root; win.makeKeyAndVisible(); root.view.layoutIfNeeded()
        let parent = UIView(frame: CGRect(x: 20, y: 20, width: 200, height: 160))
        let child = UIView(frame: CGRect(x: 10, y: 10, width: 120, height: 100))
        root.view.addSubview(parent); parent.addSubview(child)
        XCTAssertTrue(InputWindowState.allowsInput(in: child)); return (parent, child)
    }
    func testCombinedOpacityBelowVisibilityThresholdRejectsInput() throws {
        let (parent, child) = try fixture(); parent.alpha = 0.05; child.alpha = 0.05
        XCTAssertFalse(InputWindowState.allowsInput(in: child))
    }
    func testCombinedOpacityAboveThresholdRemainsUsable() throws {
        let (parent, child) = try fixture(); parent.alpha = 0.2; child.alpha = 0.2
        XCTAssertTrue(InputWindowState.allowsInput(in: child))
    }
}
