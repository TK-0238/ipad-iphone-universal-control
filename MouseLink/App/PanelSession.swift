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
    @Published private(set) var isEnabled = false
    @Published private(set) var isInside = false
    @Published private(set) var status = "他のアプリの隣に置き、パッドを有効にしてください。"
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
    func enable(peer: UUID?) {
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
        pointer.leave(); isInside=false
        // Discard queued nonzero motion immediately; do not replay it on re-entry.
        finishStroke()
    }
    func disable(reason:String? = nil) {
        isEnabled=false; pointer.leave(); isInside=false
        finishStroke(); peer=nil; epoch=nil
        if let reason { status=reason }
    }
    func geometryChanged() { disable(reason:"ウインドウの大きさが変わったため停止しました。") }
    private func authorized() -> Bool {
        guard isEnabled else { return false }
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
