// SPDX-License-Identifier: AGPL-3.0-only
import SwiftUI
import Combine
import CoreBluetooth
import GameController
import UIKit

@MainActor
final class MouseSession: ObservableObject {
    let bluetooth: HIDPeripheral
    let typing: TypingSession
    @Published private(set) var isRelaying = false
    @Published private(set) var mouseName: String?
    @Published private(set) var receivers: [UUID] = []
    @Published private(set) var selected: UUID?
    @Published private(set) var message = "マウスをiPadに接続し、iPhoneとのペアリングを開始してください。"
    @Published var sensitivity: Double = 1
    @Published var reverseScroll = false
    // Read UIKit's resolved state at each event, not just our requested preference.
    var pointerIsLocked: (() -> Bool)?
    private var pointerGate = PointerLockGate()
    private var foreground = true
    private var capturedMouse: GCMouse?
    private var buffer = RelayBuffer()
    private var motion = MotionAccumulator()
    private var held: UInt8 = 0
    private var blocked = false
    private var draining = false
    private var mouseEpoch: UInt64 = 0
    private var subscriptions = Set<AnyCancellable>()
    private var oldIdleTimer = false
    private var ownsIdleTimer = false
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    init() {
        let transport = HIDPeripheral()
        bluetooth = transport
        typing = TypingSession(sender: transport)
        bluetooth.advertiseLocalName = "MouseLink"
        bluetooth.onMouseWritable = { [weak self] in
            self?.blocked = false
            self?.drain()
        }
        bluetooth.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        bluetooth.$mouseReceivers.combineLatest(bluetooth.$keyboardReceivers).receive(on: DispatchQueue.main).sink { [weak self] mouse, keyboard in
            self?.updateReceivers(mouse, keyboard: keyboard)
        }.store(in: &subscriptions)
        bluetooth.$lastError.compactMap { $0 }.receive(on: DispatchQueue.main).sink { [weak self] error in
            self?.pause(reason: "Bluetooth: \(error)")
        }.store(in: &subscriptions)
        for name: Notification.Name in [.GCMouseDidConnect, .GCMouseDidDisconnect] {
            NotificationCenter.default.publisher(for: name).receive(on: DispatchQueue.main).sink { [weak self] _ in
                guard let self else { return }
                if self.isRelaying { self.pause(reason: "マウス接続が変わったため停止しました。") }
                self.refreshMouse()
            }.store(in: &subscriptions)
        }
        Timer.publish(every: 0.1, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.tick() }.store(in: &subscriptions)
        refreshMouse()
    }

    var canStart: Bool {
        ReceiverPolicy.canStart(foreground: foreground, mouse: mouseName != nil,
            selectedIsAvailable: selected.map { bluetooth.mouseReceivers.contains($0) } ?? false)
    }
    var bluetoothStatus: String {
        switch bluetooth.state {
        case .poweredOn: return bluetooth.isAdvertising ? "iPhoneから接続できます" : (receivers.isEmpty ? "接続待ちを開始してください" : "ペアリング済み")
        case .poweredOff: return "Bluetoothがオフです"
        case .unauthorized: return "設定でBluetoothの使用を許可してください"
        case .unsupported: return "この環境はBluetoothの実機転送に対応していません"
        case .resetting: return "Bluetoothを復旧しています"
        default: return "接続待ちを開始するとBluetoothを使用します"
        }
    }
    func advertise() {
        guard foreground, !isRelaying else { return }
        message = "iPhoneのAssistiveTouch → デバイス → Bluetoothデバイスで「MouseLink」を選んでください。"
        bluetooth.start()
    }
    func select(_ id: UUID) {
        guard receivers.contains(id) else { return }
        if selected != id { pause(reason: "受信先を変更しました。開始ボタンで転送を許可してください。") }
        selected = id
    }
    func start() {
        typing.close()
        refreshMouse()
        guard canStart, let peer = selected, let mouse = GCMouse.current ?? GCMouse.mice().first else {
            message = "マウスと受信先iPhoneの接続を確認してください。"; return
        }
        pause(reason: "")
        // Never replace an outstanding release with a new host's movement queue.
        guard buffer.next == nil else {
            buffer.disconnect(); bluetooth.hardDisconnect()
            message = "停止通知を送れなかったため切断しました。接続を確認して再開してください。"; return
        }
        bluetooth.stop()
        motion = MotionAccumulator(); held = 0; blocked = false
        buffer.begin(peer: peer, at: now)
        mouseEpoch = bluetooth.inputEpoch
        pointerGate.request(at: now)
        isRelaying = true; capturedMouse = mouse
        let generation = buffer.generation
        mouse.handlerQueue = .main
        let input = mouse.mouseInput
        input?.mouseMovedHandler = { [weak self] _, dx, dy in
            MainActor.assumeIsolated { self?.move(dx: Double(dx), dy: Double(dy), wheel: 0, generation: generation) }
        }
        input?.leftButton.pressedChangedHandler = { [weak self] _, _, pressed in
            MainActor.assumeIsolated { self?.button(mask: 1, pressed: pressed, generation: generation) }
        }
        input?.rightButton?.pressedChangedHandler = { [weak self] _, _, pressed in
            MainActor.assumeIsolated { self?.button(mask: 2, pressed: pressed, generation: generation) }
        }
        input?.middleButton?.pressedChangedHandler = { [weak self] _, _, pressed in
            MainActor.assumeIsolated {
                guard pressed, let self, self.buffer.generation == generation else { return }
                self.pause(reason: "iPad操作に戻りました。再開には開始ボタンを押してください。")
            }
        }
        input?.scroll.valueChangedHandler = { [weak self] _, _, y in
            MainActor.assumeIsolated { self?.move(dx: 0, dy: 0, wheel: Double(y), generation: generation) }
        }
        oldIdleTimer = UIApplication.shared.isIdleTimerDisabled
        ownsIdleTimer = true; UIApplication.shared.isIdleTimerDisabled = true
        message = "iPhoneへ転送中。中央ボタンを押すとiPad操作に戻ります。"
        drain()
    }
    func openTyping() {
        pause(reason: "文字入力画面ではiPad側のマウスを操作します。")
        bluetooth.stop()
        typing.open(peer: selected)
    }
    func pause(reason: String = "転送を停止しました。") {
        typing.cancel(reason: reason)
        detachMouse()
        isRelaying = false; held = 0; motion = MotionAccumulator(); pointerGate.stop()
        buffer.pause(at: now)
        if ownsIdleTimer { UIApplication.shared.isIdleTimerDisabled = oldIdleTimer; ownsIdleTimer = false }
        if !reason.isEmpty { message = reason }
        blocked = false; drain()
    }
    func disconnect() {
        pause(reason: "切断しました。再接続しても自動では転送しません。")
        buffer.disconnect(); bluetooth.hardDisconnect(); selected = nil; receivers = []
    }
    func setForeground(_ value: Bool) {
        foreground = value
        typing.setForeground(value)
        if !value {
            pause(reason: "アプリが非アクティブになったため停止しました。")
            // Background suspension can prevent the timer or write-ready callback from running.
            if buffer.next != nil { buffer.disconnect(); bluetooth.hardDisconnect() }
        }
        else { refreshMouse() }
    }
    private func refreshMouse() {
        let mouse = GCMouse.current ?? GCMouse.mice().first
        let name = mouse.map { $0.vendorName ?? "接続済みマウス" }
        if name != mouseName { mouseName = name }
    }
    private func updateReceivers(_ peers: Set<UUID>, keyboard: Set<UUID>) {
        if isRelaying, let id = buffer.peer, !peers.contains(id) {
            pause(reason: "iPhoneとの接続が切れたため停止しました。")
            buffer.disconnect()
        }
        let all = peers.union(keyboard)
        selected = ReceiverPolicy.choose(previous: selected, available: all)
        receivers = all.sorted { $0.uuidString < $1.uuidString }
    }
    func pointerLockChanged() {
        _ = inputLockReady()
    }
    private func inputLockReady() -> Bool {
        guard isRelaying else { return false }
        if pointerGate.observe(locked: pointerIsLocked?() == true, at: now) {
            pause(reason: "マウスのロックが解除されたため停止しました。フルスクリーンで再開してください。")
            return false
        }
        return pointerGate.canForward
    }
    private func move(dx: Double, dy: Double, wheel: Double, generation: UInt64) {
        guard isRelaying, foreground, generation == buffer.generation, inputLockReady() else { return }
        do {
            let gain = sensitivity.isFinite ? min(3, max(0.25, sensitivity)) : 1
            let frames = try motion.add(x: dx * gain, y: -dy * gain,
                wheel: reverseScroll ? -wheel : wheel, buttons: held)
            try buffer.enqueue(frames, at: now); drain()
        } catch { pause(reason: error.localizedDescription) }
    }
    private func button(mask: UInt8, pressed: Bool, generation: UInt64) {
        guard isRelaying, foreground, generation == buffer.generation, inputLockReady() else { return }
        if pressed { held |= mask } else { held &= ~mask }
        do { try buffer.enqueue([MouseFrame(buttons: held)], at: now); drain() }
        catch { pause(reason: error.localizedDescription) }
    }
    private func discardMouseTransfer() {
        buffer.disconnect(); detachMouse(); isRelaying = false
        held = 0; motion = MotionAccumulator(); pointerGate.stop(); blocked = false
        if ownsIdleTimer { UIApplication.shared.isIdleTimerDisabled = oldIdleTimer; ownsIdleTimer = false }
    }
    private func drain() {
        guard !draining else { return }
        draining = true; defer { draining = false }
        while let item = buffer.next {
            let decision = MouseDispatchSafety.decide(item, at: now, active: buffer.isActive,
                foreground: foreground, locked: pointerIsLocked?() == true,
                sameConnection: item.generation == buffer.generation && mouseEpoch == bluetooth.inputEpoch)
            switch decision {
            case .discard:
                bluetooth.hardDisconnect()
                discardMouseTransfer()
                message = "接続が変わったため停止しました。古い入力は再送しません。"; return
            case .disconnect:
                discardMouseTransfer(); bluetooth.hardDisconnect()
                message = "停止通知の期限を過ぎたため接続を解除しました。"; return
            case .release:
                pause(reason: "入力が遅延、または操作許可が解除されたため停止しました。")
                continue
            case .send: break
            }
            guard !blocked else { return }
            let report = MouseReport(buttons: MouseButtons(rawValue: item.frame.buttons), dX: item.frame.x, dY: item.frame.y, wheel: item.frame.wheel)
            switch bluetooth.tryRelayMouse(report, to: item.peer) {
            case .accepted: buffer.acceptNext()
            case .busy: blocked = true; return
            case .unavailable:
                discardMouseTransfer()
                message = "受信先に送信できません。iPhoneの接続状態を確認してください。"; return
            }
        }
    }
    private func tick() {
        if isRelaying && mouseEpoch != bluetooth.inputEpoch {
            discardMouseTransfer(); bluetooth.hardDisconnect()
            message = "接続が変わったため停止しました。再開には開始ボタンを押してください。"
        }
        if !isRelaying { refreshMouse() } else { _ = inputLockReady() }
        if buffer.expire(at: now) { pause(reason: RelayFailure.stale.localizedDescription) }
        if !isRelaying, let first = buffer.next, now - first.queuedAt > 0.7 {
            buffer.disconnect(); bluetooth.hardDisconnect()
            message = "停止通知を送信できなかったためBluetooth接続を解除しました。"
        }
    }
    private func detachMouse() {
        guard let input = capturedMouse?.mouseInput else { capturedMouse = nil; return }
        input.mouseMovedHandler = nil; input.leftButton.pressedChangedHandler = nil
        input.rightButton?.pressedChangedHandler = nil; input.middleButton?.pressedChangedHandler = nil
        input.scroll.valueChangedHandler = nil; capturedMouse = nil
    }
}
