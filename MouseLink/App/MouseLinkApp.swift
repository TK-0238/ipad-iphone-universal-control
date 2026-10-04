// SPDX-License-Identifier: AGPL-3.0-only
import SwiftUI
import Combine
import UIKit

@main
struct MouseLinkApp: App {
    @StateObject private var session = MouseSession()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            MouseLinkHost(session: session)
                .onChange(of: phase) { newValue in session.setForeground(newValue == .active) }
        }
    }
}

struct MouseLinkHost: UIViewControllerRepresentable {
    @ObservedObject var session: MouseSession
    func makeUIViewController(context: Context) -> LockHostingController {
        LockHostingController(session: session)
    }
    func updateUIViewController(_ controller: LockHostingController, context: Context) {
        controller.locked = session.isRelaying
    }
}
final class LockHostingController: UIHostingController<MouseLinkView> {
    var locked = false {
        didSet { if oldValue != locked { setNeedsUpdateOfPrefersPointerLocked(); parent?.setNeedsUpdateOfPrefersPointerLocked() } }
    }
    private weak var session: MouseSession?
    private var lockObserver: NSObjectProtocol?
    init(session: MouseSession) {
        self.session = session
        super.init(rootView: MouseLinkView(session: session))
        session.pointerIsLocked = { [weak self] in
            self?.viewIfLoaded?.window?.windowScene?.pointerLockState?.isLocked == true
        }
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let lockObserver { NotificationCenter.default.removeObserver(lockObserver) }
        if let state = view.window?.windowScene?.pointerLockState {
            lockObserver = NotificationCenter.default.addObserver(forName: UIPointerLockState.didChangeNotification,
                object: state, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.session?.pointerLockChanged() }
            }
        }
        session?.pointerLockChanged()
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if let lockObserver { NotificationCenter.default.removeObserver(lockObserver) }
        lockObserver = nil
        if session?.isRelaying == true { session?.pause(reason: "操作画面が非表示になったため停止しました。") }
    }
    deinit { if let lockObserver { NotificationCenter.default.removeObserver(lockObserver) } }
    @objc required dynamic init?(coder aDecoder: NSCoder) { fatalError("Storyboard is not used") }
    override var prefersPointerLocked: Bool { locked }
}

struct MouseLinkView: View {
    @ObservedObject var session: MouseSession
    @State private var guide = false
    @State private var license = false
    @State private var typing = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    connection
                    controls
                    Button { session.openTyping(); typing = true } label: {
                        Label("文字入力・Enter", systemImage: "keyboard").frame(maxWidth: .infinity).padding(.vertical, 8)
                    }.buttonStyle(.bordered).accessibilityIdentifier("open-typing")
                    VStack(alignment: .leading, spacing: 12) {
                        Label("操作の感度", systemImage: "slider.horizontal.3").font(.headline)
                        HStack {
                            Slider(value: $session.sensitivity, in: 0.25...3, step: 0.05)
                                .accessibilityLabel("マウス感度")
                            Text(session.sensitivity, format: .number.precision(.fractionLength(2))).monospacedDigit().frame(width: 56)
                        }
                        Toggle("スクロール方向を反転", isOn: $session.reverseScroll)
                    }.disabled(session.isRelaying)
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("このアプリを開いている間に転送します。")
                            .font(.headline)
                        Text("iPhoneの画面にはAssistiveTouchのポインターが表示されます。iPadの他アプリ上での自動画面端切り替えや、iPhoneの画面ミラーリングは行いません。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("接続ガイド") { guide = true }.accessibilityIdentifier("guide")
                        Spacer()
                        Button("ライセンス・ソース") { license = true }.accessibilityIdentifier("license")
                    }.font(.subheadline)
                }
                .padding(24).frame(maxWidth: 700).frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("MouseLink")
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                if session.isRelaying { Button("停止", role: .destructive) { session.pause() }.accessibilityIdentifier("stop") }
            } }
            .sheet(isPresented: $guide) { GuideView() }
            .sheet(isPresented: $license) { LicenseView() }
            .sheet(isPresented: $typing, onDismiss: { session.typing.close() }) { TypingView(session: session.typing) }
        }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(session.isRelaying ? "iPhoneを操作中" : "1つのマウスで、2つの画面へ。",
                  systemImage: session.isRelaying ? "cursorarrow.rays" : "computermouse")
                .font(.title2.bold()).accessibilityIdentifier("headline")
            Text("iPad  →  Bluetooth  →  iPhone")
                .font(.subheadline.monospaced()).foregroundStyle(.secondary)
            Text(session.message).font(.body).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("status")
        }
    }
    private var connection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(session.mouseName ?? "マウス未接続", systemImage: session.mouseName == nil ? "computermouse" : "checkmark.circle")
                .accessibilityIdentifier("mouse-status")
            Divider()
            Label(session.bluetoothStatus, systemImage: "antenna.radiowaves.left.and.right")
            if !session.receivers.isEmpty {
                Text("転送する受信先").font(.caption).foregroundStyle(.secondary)
                ForEach(session.receivers, id: \.self) { peer in
                    Button { session.select(peer) } label: {
                        HStack {
                            Image(systemName: session.selected == peer ? "checkmark.circle.fill" : "circle")
                            VStack(alignment: .leading) {
                                Text("Bluetooth受信先")
                                Text(peer.uuidString).font(.caption.monospaced()).lineLimit(1).minimumScaleFactor(0.7)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.disabled(session.isRelaying)
                }
                Text("接続名だけで相手を判別しません。初回はiPhoneだけをペアリングし、開始ボタンで転送を許可してください。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(20).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }
    private var controls: some View {
        VStack(spacing: 12) {
            if session.isRelaying {
                Button { session.pause() } label: {
                    Label("iPad操作に戻る", systemImage: "pause.fill").frame(maxWidth: .infinity).padding(.vertical, 9)
                }.buttonStyle(.borderedProminent).tint(.orange).accessibilityIdentifier("pause")
                Text("マウスの中央ボタンでも停止できます。中央ボタンのないマウスでは、このボタンをタップしてください。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Button { session.start() } label: {
                    Label("iPhoneの操作を開始", systemImage: "play.fill").frame(maxWidth: .infinity).padding(.vertical, 9)
                }.buttonStyle(.borderedProminent).disabled(!session.canStart).accessibilityIdentifier("start")
                HStack {
                    Button("接続待ちを開始") { session.advertise() }.buttonStyle(.bordered).accessibilityIdentifier("advertise")
                    Spacer()
                    Button("すべて切断", role: .destructive) { session.disconnect() }.buttonStyle(.bordered)
                }
            }
        }
    }
}

struct GuideView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("1 · iPadにマウスを接続") {
                    Text("いつも使うマウスをiPadへ接続します。物理キーボードは不要です。MouseLinkをフルスクリーンで開き、「接続待ちを開始」を押します。")
                }
                Section("2 · iPhoneでAssistiveTouchをオン") {
                    Text("設定 → アクセシビリティ → タッチ → AssistiveTouchをオンにします。その画面の「デバイス」→「Bluetoothデバイス」でMouseLinkを選び、システムのペアリング要求を確認します。")
                }
                Section("3 · 転送を許可") {
                    Text("iPadで受信先を選び、「iPhoneの操作を開始」を押します。移動・左クリック・右クリック・ホイールをBluetoothで直接送ります。iPhone側にこのアプリをインストールする必要はありません。")
                }
                Section("4 · iPadに戻る") {
                    Text("マウスの中央ボタン、またはiPad画面の「iPad操作に戻る」で停止します。他のiPadアプリへ移ると転送は停止し、戻っても自動再開しません。")
                }
                Section("接続できないとき") {
                    Text("Bluetoothの許可、iPhoneのAssistiveTouch、両端末の距離を確認します。古いペアリングが残っている場合は、iPhone側でMouseLinkを登録解除してからペアリングし直してください。接続名や公開実装の対応表だけでは、手元の組み合わせの動作保証にはなりません。")
                }
                Section("対応範囲") {
                    Text("これは前面アプリからの直接マウス転送です。OS全体の自動画面端切り替えは未対応です。Bluetooth通信と物理マウスの動作は実機での確認が必要です。")
                }
            }.navigationTitle("接続ガイド").toolbar { Button("閉じる") { dismiss() } }
        }
    }
}
struct LicenseView: View {
    @Environment(\.dismiss) private var dismiss
    private var text: String {
        #if SWIFT_PACKAGE
        let resources = Bundle.module
        #else
        let resources = Bundle.main
        #endif
        guard let url = resources.url(forResource: "LICENSE", withExtension: "txt"), let result = try? String(contentsOf: url, encoding: .utf8) else {
            return "AGPL-3.0-only。配布パッケージ内のLICENSE.txtを参照してください。"
        }
        return result
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Bluetooth HID部分はJingqian Sunのdarwin-bt-remoteを使用しています。MouseLinkの変更部分を含めAGPL-3.0-onlyでソースを同梱しています。")
                    Link("MouseLinkの完全なソース", destination: URL(string: "https://github.com/TK-0238/ipad-iphone-universal-control/tree/feature/mouselink-bluetooth-direct/MouseLink")!)
                    Link("上流プロジェクト", destination: URL(string: "https://github.com/jqssun/darwin-bt-remote")!)
                    Text(text).font(.caption.monospaced()).textSelection(.enabled)
                }.padding()
            }.navigationTitle("ライセンス").toolbar { Button("閉じる") { dismiss() } }
        }
    }
}
