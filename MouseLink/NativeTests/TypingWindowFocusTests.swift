import XCTest
import Combine
import SwiftUI
import UIKit
@testable import MouseLink

@MainActor
private final class FocusCaptureSender: KeyboardSending {
    var keyboardReceivers: Set<UUID> = []
    var inputEpoch: UInt64 = 1
    var reports: [Data] = []
    func sendKeyboardBytes(_ bytes: Data, to peer: UUID) -> KeyboardSendResult {
        reports.append(bytes); return .accepted
    }
    func hardDisconnect() { inputEpoch += 1; keyboardReceivers = [] }
}

@MainActor
final class TypingWindowFocusTests: XCTestCase {
    private var time: Double = 1
    private var window: UIWindow?
    private weak var originalWindow: UIWindow?
    override func tearDown() {
        window?.isHidden = true
        window = nil
        originalWindow?.makeKeyAndVisible()
        super.tearDown()
    }
    private func make() throws -> (TypingSession, FocusCaptureSender, UIWindow) {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        originalWindow = scene.windows.first { $0.isKeyWindow }
        let sender = FocusCaptureSender(), peer = UUID()
        sender.keyboardReceivers = [peer]
        let typing = TypingSession(sender: sender, clock: { self.time },
                                   ticks: Empty<Date, Never>().eraseToAnyPublisher())
        let win = UIWindow(windowScene: scene)
        win.rootViewController = UIHostingController(rootView: TypingView(session: typing))
        window = win
        win.makeKeyAndVisible()
        win.rootViewController?.view.layoutIfNeeded()
        typing.setForeground(true)
        typing.open(peer: peer)
        typing.draft = "hello"
        typing.sendDraft(enter: true)
        time += 0.021; typing.pump()
        XCTAssertTrue(typing.isSending, "The fixture must start actual TypingSession output first")
        XCTAssertTrue(sender.reports.contains { $0 != KeyboardStroke.zero.data })
        return (typing, sender, win)
    }
    func testOwningWindowResignKeyStopsBeforeNotificationReturns() throws {
        let (typing, sender, win) = try make()
        NotificationCenter.default.post(name: UIWindow.didResignKeyNotification, object: win)
        XCTAssertFalse(typing.isSending)
        XCTAssertEqual(sender.reports.last, KeyboardStroke.zero.data)
        let count = sender.reports.count
        time += 0.1; typing.pump()
        XCTAssertEqual(sender.reports.count, count)
        XCTAssertFalse(sender.reports.contains(KeyboardStroke.enter.data))
    }
    func testOwningSceneDeactivationStopsWithoutApplicationPhaseChange() throws {
        let (typing, sender, win) = try make()
        NotificationCenter.default.post(name: UIScene.willDeactivateNotification, object: win.windowScene!)
        XCTAssertFalse(typing.isSending)
        XCTAssertEqual(sender.reports.last, KeyboardStroke.zero.data)
        time += 0.1; typing.pump()
        XCTAssertFalse(sender.reports.contains(KeyboardStroke.enter.data))
    }
    func testUnrelatedWindowDoesNotCancelThisTransaction() throws {
        let (typing, sender, _) = try make()
        let other = UIWindow(frame: .zero)
        NotificationCenter.default.post(name: UIWindow.didResignKeyNotification, object: other)
        XCTAssertTrue(typing.isSending)
        for _ in 0..<50 { time += 0.021; typing.pump() }
        XCTAssertEqual(sender.reports.filter { $0 == KeyboardStroke.enter.data }.count, 1)
    }
    func testRegainingWindowFocusDoesNotReplayOldEnter() throws {
        let (typing, sender, win) = try make()
        NotificationCenter.default.post(name: UIWindow.didResignKeyNotification, object: win)
        let count = sender.reports.count
        NotificationCenter.default.post(name: UIWindow.didBecomeKeyNotification, object: win)
        typing.setForeground(true)
        for _ in 0..<30 { time += 0.021; typing.pump() }
        XCTAssertFalse(typing.isSending)
        XCTAssertEqual(sender.reports.count, count)
        XCTAssertFalse(sender.reports.contains(KeyboardStroke.enter.data))
    }
}
