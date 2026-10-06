// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import Combine
import UIKit

// Kept injectable so native tests exercise the same UI-to-report path without a Bluetooth radio.
enum KeyboardSendResult { case accepted, busy, unavailable }
@MainActor
protocol KeyboardSending: AnyObject {
    var keyboardReceivers: Set<UUID> { get }
    /// Changes whenever the transport connection/subscription/protocol lifetime changes.
    var inputEpoch: UInt64 { get }
    func sendKeyboardBytes(_ bytes: Data, to peer: UUID) -> KeyboardSendResult
    func hardDisconnect()
}

@MainActor
final class TypingSession: ObservableObject {
    @Published var draft = ""
    @Published var mode: KeyboardTextMode = .ascii
    private(set) var isSending = false { didSet { if oldValue != isSending { schedulePresentationUpdate() } } }
    private(set) var available = false { didSet { if oldValue != available { schedulePresentationUpdate() } } }
    private(set) var status = "iPhone側で入力欄を選び、文字転送またはEnterを押してください。" {
        didSet { if oldValue != status { schedulePresentationUpdate() } }
    }
    private(set) var remaining = 0 { didSet { if oldValue != remaining { schedulePresentationUpdate() } } }
    private(set) var peer: UUID?
    private let sender: KeyboardSending
    private let clock: () -> TimeInterval
    private var timer: AnyCancellable?
    private var lifecycleSubscriptions = Set<AnyCancellable>()
    private var transaction = KeyboardTransaction()
    private var transactionEpoch: UInt64?
    private var pumping = false
    private var cancelling = false
    private var presentationUpdateQueued = false
    private var operation: UInt64 = 0
    private var foreground = true
    private var opened = false
    private var inputSurfaceCheck: () -> Bool
    private var inputSurfaceOwner: UUID?

    init(sender: KeyboardSending,
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         ticks: AnyPublisher<Date,Never> = Timer.publish(every:0.02,on:.main,in:.common).autoconnect().eraseToAnyPublisher(),
         inputSurfaceCheck: @escaping () -> Bool = { false }) {
        self.sender=sender;self.clock=clock;self.inputSurfaceCheck=inputSurfaceCheck
        timer=ticks.sink { [weak self] _ in self?.pump() }
        // UIKit delivers these notifications on the main thread. Cancel synchronously:
        // receive(on:) / Task would leave a gap before SwiftUI's scenePhase catches up.
        for name in [UIApplication.willResignActiveNotification,
                     UIApplication.didEnterBackgroundNotification] {
            NotificationCenter.default.publisher(for: name, object: UIApplication.shared)
                .sink { [weak self] _ in
                    MainActor.assumeIsolated { self?.setForeground(false) }
                }
                .store(in: &lifecycleSubscriptions)
        }
    }
    var canSend: Bool { !cancelling && opened && available && !isSending && foreground && inputSurfaceCheck() }

    /// The visible typing view owns this authorization; construction alone never grants it.
    func bindInputSurface(owner: UUID, check: @escaping () -> Bool) {
        if inputSurfaceOwner != owner { cancel() }
        inputSurfaceOwner=owner;inputSurfaceCheck=check
        inputSurfaceChanged()
    }
    func unbindInputSurface(owner: UUID) {
        guard inputSurfaceOwner == owner else { return }
        inputSurfaceOwner=nil;inputSurfaceCheck={ false }
        inputSurfaceChanged()
    }
    func inputSurfaceChanged() {
        if !inputSurfaceCheck() {
            cancel(reason:"文字入力ウインドウの操作が解除されたため停止しました。自動再送はしません。")
        }
        refreshAvailability()
    }
    var validation: String? {
        guard !draft.isEmpty else { return nil }
        do { _ = try KeyboardPlan.text(draft,mode:mode,enter:false); return nil }
        catch { return error.localizedDescription }
    }
    var wirePreview: String? {
        guard mode == .kanaReading else { return nil }
        return try? KeyboardPlan.text(draft,mode:mode,enter:false).wireText
    }
    func open(peer: UUID?) {
        guard !cancelling else { return }
        cancel()
        self.peer=peer;opened=true
        refreshAvailability()
        status=available ? "文字入力先はiPhone側で選んでください。転送はボタンを押したときだけ行います。" : "接続と文字入力ウインドウを確認してください。文章は送信せずに準備できます。"
    }
    func close() { cancel();opened=false;available=false }
    func setForeground(_ active: Bool) {
        foreground=active
        if !active { cancel(reason:"非アクティブになったため文字転送を中止しました。再送はしません。") }
        refreshAvailability()
    }
    func sendDraft(enter: Bool) {
        guard !cancelling else { return }
        do { try begin(KeyboardPlan.text(draft,mode:mode,enter:enter)) }
        catch { status=error.localizedDescription }
    }
    func sendKey(_ stroke: KeyboardStroke) {
        guard !cancelling else { return }
        do { try begin(.key(stroke)) } catch { status=error.localizedDescription }
    }
    func sendCharacter(_ character: String) {
        guard !cancelling else { return }
        do { try begin(KeyboardPlan.text(character,mode:.ascii,enter:false)) } catch { status=error.localizedDescription }
    }
    private func begin(_ plan: KeyboardPlan) throws {
        guard !cancelling else { throw KeyboardError.busy }
        refreshAvailability()
        guard opened, available, foreground, let peer else { status="iPhoneとの接続と文字入力ウインドウを確認してください。入力は送信されていません。";return }
        try transaction.begin(plan,peer:peer,at:clock())
        transactionEpoch=sender.inputEpoch;operation &+= 1
        isSending=true;remaining=transaction.remaining
        status="キーを順番に転送中です。中止すると未送信のEnterも破棄します。"
        pump()
    }
    func cancel(reason: String = "文字転送を中止しました。自動再送はしません。") {
        // A transport callback can reenter public APIs while the release is being sent.
        // Do not permit a new transaction until this cancellation is fully committed.
        guard !cancelling else { return }
        cancelling=true; defer { cancelling=false }
        operation &+= 1
        let sameConnection = transactionEpoch == sender.inputEpoch
        if let peer=transaction.cancel() {
            // A stable UUID may now denote a NEW connection: never inject old release/Enter into it.
            if sameConnection {
                if sender.sendKeyboardBytes(KeyboardStroke.zero.data,to:peer) != .accepted { sender.hardDisconnect() }
            } else {
                // Topology changes may leave the original host connected with a held key.
                // Tear down rather than write a release into a possibly new connection.
                sender.hardDisconnect()
            }
            status=reason
        }
        transactionEpoch=nil;isSending=false;remaining=0
    }
    func pump() {
        guard !pumping else { return }
        pumping=true;defer { pumping=false }
        refreshAvailability()
        guard transaction.isActive else { return }
        guard opened,foreground,available,transaction.peer == peer,transactionEpoch == sender.inputEpoch else {
            cancel(reason:"接続状態が変わったため文字転送を中止しました。iPhoneの入力内容を確認してください。");return
        }
        let time=clock()
        guard !transaction.isStalled(at:time) else {
            cancel(reason:"Bluetoothの待機が長いため停止しました。一部だけ届いている可能性があります。自動再送しません。");return
        }
        guard let report=transaction.due(at:time),let target=transaction.peer else { return }
        let currentOperation=operation
        let result=sender.sendKeyboardBytes(report.data,to:target)
        guard currentOperation == operation else { return }
        // The write may synchronously change the connection or window state. Observe
        // that loss NOW, even if permission returns before the next timer tick.
        refreshAvailability()
        guard opened, foreground, available, transactionEpoch == sender.inputEpoch else {
            cancel(reason:"送信中に接続または操作ウインドウが変わったため停止しました。自動再送はしません。")
            return
        }
        switch result {
        case .accepted:
            transaction.accept(at:time);remaining=transaction.remaining
            if !transaction.isActive {
                transactionEpoch=nil;isSending=false
                status="Bluetoothへの送信受付が完了しました。iPhoneの表示・変換・送信結果は画面で確認してください。"
            }
        case .busy: break
        case .unavailable: cancel(reason:"受信先が見つからないため停止しました。未送信の文字とEnterは破棄しました。")
        }
    }
    /// Input state above is authoritative and changes synchronously. Only SwiftUI's
    /// invalidation is deferred; no report, permission, or state snapshot is queued.
    /// Keep draft/mode @Published so normal editing retains its standard bindings.
    private func schedulePresentationUpdate() {
        guard !presentationUpdateQueued else { return }
        presentationUpdateQueued=true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.presentationUpdateQueued=false
            self.objectWillChange.send()
        }
    }
    private func refreshAvailability() {
        let value=opened && inputSurfaceCheck() && KeyboardPolicy.canSend(peer:peer,receivers:sender.keyboardReceivers,foreground:foreground,mouseRelaying:false)
        if value != available { available=value }
    }
}
