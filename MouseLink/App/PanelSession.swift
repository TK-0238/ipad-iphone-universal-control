// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import Combine
import UIKit

@MainActor
protocol PanelMouseSending: AnyObject {
    var mouseReceivers: Set<UUID> { get }
    var inputEpoch: UInt64 { get }
    func sendPanelMouse(_ frame: MouseFrame, to peer: UUID) -> MouseSendResult
    func hardDisconnect()
}
extension HIDPeripheral: PanelMouseSending {
    func sendPanelMouse(_ frame: MouseFrame, to peer: UUID) -> MouseSendResult {
        tryRelayMouse(MouseReport(buttons:MouseButtons(rawValue:frame.buttons),dX:frame.x,dY:frame.y,wheel:frame.wheel),to:peer)
    }
}

/// A local, visible control surface. No GCMouse handlers and no pointer lock are installed here.
@MainActor
final class PanelSession: ObservableObject {
    // Give Combine storage for its synthesized, nonisolated objectWillChange witness.
    // Actual state is synchronous below; sends are explicit so lifecycle redraws can
    // be deferred without mutating a property wrapper during reentrant callbacks.
    @Published private var presentationPublisherStorage: UInt8 = 0
    private(set) var isEnabled = false { willSet { if newValue != isEnabled { notifyPresentation() } } }
    private(set) var isInside = false { willSet { if newValue != isInside { notifyPresentation() } } }
    private(set) var status = "他のアプリの隣に置き、パッドを有効にしてください。" {
        willSet { if newValue != status { notifyPresentation() } }
    }
    var surfaceIsUsable: () -> Bool = { false }
    var sensitivity: Double = 1
    var reverseScroll = false
    private let sender: PanelMouseSending
    private let clock: () -> TimeInterval
    private var foreground = true
    private var peer: UUID?
    private var epoch: UInt64?
    private var pointer = LocalPadPointer()
    private var buffer = RelayBuffer()
    private var pumping = false
    private var disabling = false
    private var leaving = false
    private var inputSurfaceOwner: UUID?
    private var presentationDeferralDepth = 0
    private var presentationUpdateQueued = false
    private var subscriptions = Set<AnyCancellable>()

    init(sender: PanelMouseSending, clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         ticks: AnyPublisher<Date,Never> = Timer.publish(every:0.02,on:.main,in:.common).autoconnect().eraseToAnyPublisher()) {
        self.sender=sender; self.clock=clock
        ticks.sink { [weak self] _ in self?.pump() }.store(in:&subscriptions)
        for name in [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification] {
            NotificationCenter.default.publisher(for:name,object:UIApplication.shared).sink { [weak self] _ in
                MainActor.assumeIsolated { self?.setForeground(false) }
            }.store(in:&subscriptions)
        }
    }
    /// A newly allocated view has no authority until it is attached to a window.
    /// Replacing the actual surface revokes the previous visit before granting ownership;
    /// ownership alone does not enable remote input.
    func bindInputSurface(owner: UUID, check: @escaping () -> Bool) {
        guard !disabling, !leaving, inputSurfaceOwner != owner else { return }
        fromViewLifecycle {
            disable()
            inputSurfaceOwner = owner
            surfaceIsUsable = check
        }
    }
    func ownsInputSurface(_ owner: UUID) -> Bool { inputSurfaceOwner == owner }
    func unbindInputSurface(owner: UUID) {
        guard ownsInputSurface(owner) else { return }
        fromViewLifecycle {
            inputSurfaceOwner = nil
            surfaceIsUsable = { false }
            disable(reason: "操作パッドが非表示になったため停止しました。")
        }
    }
    func invalidateInputSurface(owner: UUID, reason: String) {
        guard ownsInputSurface(owner) else { return }
        fromViewLifecycle { disable(reason: reason) }
    }
    /// Revoke input and release held buttons synchronously, including during UIKit
    /// attachment/layout/removal. Only the SwiftUI redraw notification is deferred.
    private func fromViewLifecycle(_ change: () -> Void) {
        presentationDeferralDepth += 1
        defer { presentationDeferralDepth -= 1 }
        change()
    }
    private func notifyPresentation() {
        guard presentationDeferralDepth > 0 else { objectWillChange.send(); return }
        guard !presentationUpdateQueued else { return }
        presentationUpdateQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.presentationUpdateQueued = false
            self.objectWillChange.send()
        }
    }
    func enable(peer: UUID?) {
        guard !disabling, !leaving else { return }
        disable()
        let now=clock()
        guard foreground, surfaceIsUsable(), let peer, sender.mouseReceivers.contains(peer),
              now.isFinite, now >= 0 else {
            status = "受信先と操作パッドの表示状態を確認してください。"; return
        }
        self.peer=peer; epoch=sender.inputEpoch; isEnabled=true
        status = "パッドの中はiPhone、外はiPad。離れると移動・ドラッグを解除します。"
        // Authorization is not a keystroke/click. First local event creates the neutral baseline.
    }
    func setForeground(_ active: Bool) {
        foreground=active
        if !active { disable(reason:"別のウインドウへ移ったため停止しました。再開にはパッドを有効にしてください。") }
    }
    func move(x:Double,y:Double,width:Double,height:Double,externalButtonsDown:Bool = false) {
        guard authorized() else { return }
        do {
            let frames=try pointer.move(x:x,y:y,width:width,height:height,gain:sensitivity,externalButtonsDown:externalButtonsDown)
            guard pointer.isInside else { leave(); return }
            if !isInside { isInside=true }
            enqueue(frames)
        } catch { disable(reason:error.localizedDescription) }
    }
    func buttons(_ mask: UInt8) { guard authorized(), pointer.isInside else { return }; enqueue(pointer.buttons(mask)) }
    func scroll(_ amount:Double) {
        guard authorized(), pointer.isInside else { return }
        do { enqueue(try pointer.scroll(reverseScroll ? -amount : amount)) }
        catch { disable(reason:error.localizedDescription) }
    }
    func tap() { buttons(1); buttons(0) }
    func leave() {
        guard !disabling, !leaving else { return }
        leaving=true; defer { leaving=false }
        pointer.leave(); isInside=false
        // Discard queued nonzero motion immediately; do not replay it on re-entry.
        finishStroke()
    }
    func disable(reason:String? = nil) {
        // Close the gate before presentation notifications or transport callbacks can reenter.
        // A real window loss may still disable an in-progress leave.
        guard !disabling else { return }
        disabling=true; defer { disabling=false }
        isEnabled=false; pointer.leave(); isInside=false
        finishStroke(); peer=nil; epoch=nil
        if let reason { status=reason }
    }
    func geometryChanged() { disable(reason:"ウインドウの大きさが変わったため停止しました。") }
    private func authorized() -> Bool {
        guard !disabling, !leaving, isEnabled else { return false }
        guard foreground, surfaceIsUsable(), let peer, epoch == sender.inputEpoch,
              sender.mouseReceivers.contains(peer) else {
            disable(reason:"表示または接続が変わったため停止しました。古い入力は再送しません。"); return false
        }
        return true
    }
    private func enqueue(_ frames:[MouseFrame]) {
        guard let peer else { return }
        let time=clock()
        if !buffer.isActive { buffer.begin(peer:peer,at:time) }
        do { try buffer.enqueue(frames,at:time); pump() }
        catch { disable(reason:error.localizedDescription) }
    }
    func pump() {
        guard !pumping else { return }
        pumping=true; defer { pumping=false }
        guard authorized() else { return }
        while let item=buffer.next {
            guard authorized(), pointer.isInside else { return }
            let now=clock()
            guard now.isFinite, now >= item.queuedAt, now-item.queuedAt <= 0.5 else {
                disable(reason:"送信が遅れたため停止しました。iPhoneの表示を確認してください。"); return
            }
            let generation = buffer.generation
            let result = sender.sendPanelMouse(item.frame,to:item.peer)
            // A synchronous callback can leave/re-enter or disable/re-enable the pad.
            // Never consume a new visit's baseline or apply an old failure to its queue.
            guard generation == buffer.generation, authorized() else { return }
            switch result {
            case .accepted: buffer.acceptNext()
            case .busy: return
            case .unavailable: disable(reason:"受信先に送信できないため停止しました。"); return
            }
        }
    }
    private func finishStroke() {
        guard let target=buffer.peer else { return }
        buffer.disconnect()
        // UUID reuse after reconnect must never receive an old release.
        if epoch != sender.inputEpoch || sender.sendPanelMouse(.zero,to:target) != .accepted {
            sender.hardDisconnect(); isEnabled=false
            status="解除通知を送れなかったため接続を解除しました。再接続してください。"
        }
    }
}
