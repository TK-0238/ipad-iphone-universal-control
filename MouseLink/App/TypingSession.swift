// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import Combine

// Kept injectable so native tests exercise the same UI-to-report path without a Bluetooth radio.
enum KeyboardSendResult { case accepted, busy, unavailable }
@MainActor
protocol KeyboardSending: AnyObject {
    var keyboardReceivers: Set<UUID> { get }
    func sendKeyboardBytes(_ bytes: Data, to peer: UUID) -> KeyboardSendResult
    func hardDisconnect()
}

@MainActor
final class TypingSession: ObservableObject {
    @Published var draft = ""
    @Published var mode: KeyboardTextMode = .ascii
    @Published private(set) var isSending = false
    @Published private(set) var available = false
    @Published private(set) var status = "iPhone側で入力欄を選び、文字転送またはEnterを押してください。"
    @Published private(set) var remaining = 0
    private(set) var peer: UUID?
    private let sender: KeyboardSending
    private let clock: () -> TimeInterval
    private var timer: AnyCancellable?
    private var transaction = KeyboardTransaction()
    private var foreground = true
    private var opened = false

    init(sender: KeyboardSending,
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         ticks: AnyPublisher<Date,Never> = Timer.publish(every:0.02,on:.main,in:.common).autoconnect().eraseToAnyPublisher()) {
        self.sender=sender;self.clock=clock
        timer=ticks.sink { [weak self] _ in self?.pump() }
    }
    var canSend: Bool { opened && available && !isSending && foreground }
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
        cancel()
        self.peer=peer;opened=true
        refreshAvailability()
        status=available ? "文字入力先はiPhone側で選んでください。転送はボタンを押したときだけ行います。" : "キーボード受信先が未接続です。文章の準備はできます。"
    }
    func close() { cancel();opened=false;available=false }
    func setForeground(_ active: Bool) {
        foreground=active
        if !active { cancel(reason:"非アクティブになったため文字転送を中止しました。再送はしません。") }
        refreshAvailability()
    }
    func sendDraft(enter: Bool) {
        do { try begin(KeyboardPlan.text(draft,mode:mode,enter:enter)) }
        catch { status=error.localizedDescription }
    }
    func sendKey(_ stroke: KeyboardStroke) {
        do { try begin(.key(stroke)) } catch { status=error.localizedDescription }
    }
    func sendCharacter(_ character: String) {
        do { try begin(KeyboardPlan.text(character,mode:.ascii,enter:false)) } catch { status=error.localizedDescription }
    }
    private func begin(_ plan: KeyboardPlan) throws {
        refreshAvailability()
        guard opened, available, foreground, let peer else { status="iPhoneのキーボード接続を確認してください。入力は送信されていません。";return }
        try transaction.begin(plan,peer:peer,at:clock())
        isSending=true;remaining=transaction.remaining
        status="キーを順番に転送中です。中止すると未送信のEnterも破棄します。"
        pump()
    }
    func cancel(reason: String = "文字転送を中止しました。自動再送はしません。") {
        if let peer=transaction.cancel() {
            // Release ONLY the original target. If the OS queue cannot take it, tear down the link.
            if sender.sendKeyboardBytes(KeyboardStroke.zero.data,to:peer) != .accepted { sender.hardDisconnect() }
            status=reason
        }
        isSending=false;remaining=0
    }
    func pump() {
        refreshAvailability()
        guard transaction.isActive else { return }
        guard opened,foreground,available,transaction.peer == peer else {
            cancel(reason:"接続状態が変わったため文字転送を中止しました。iPhoneの入力内容を確認してください。");return
        }
        let time=clock()
        guard !transaction.isStalled(at:time) else {
            cancel(reason:"Bluetoothの待機が長いため停止しました。一部だけ届いている可能性があります。自動再送しません。");return
        }
        guard let report=transaction.due(at:time),let target=transaction.peer else { return }
        switch sender.sendKeyboardBytes(report.data,to:target) {
        case .accepted:
            transaction.accept(at:time);remaining=transaction.remaining
            if !transaction.isActive {
                isSending=false
                status="Bluetoothへの送信受付が完了しました。iPhoneの表示・変換・送信結果は画面で確認してください。"
            }
        case .busy: break
        case .unavailable: cancel(reason:"受信先が見つからないため停止しました。未送信の文字とEnterは破棄しました。")
        }
    }
    private func refreshAvailability() {
        let value=opened && KeyboardPolicy.canSend(peer:peer,receivers:sender.keyboardReceivers,foreground:foreground,mouseRelaying:false)
        if value != available { available=value }
    }
}
