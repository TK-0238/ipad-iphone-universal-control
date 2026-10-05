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
                .onChange(of: phase) { _, newValue in session.setForeground(newValue == .active) }
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
                    Text("iPadで受信先を選び、「iPhoneに切り替え」を押します。移動・左クリック・右クリック・ホイールをBluetoothで直接送ります。iPhone側にこのアプリをインストールする必要はありません。")
                }
                Section("4 · iPadに戻る") {
                    Text("マウスの中央ボタン、またはiPad画面の「iPadに戻る」で停止します。他のiPadアプリへ移ると転送は停止し、戻っても自動再開しません。")
                }
                Section("配置と画面端の切り替え") {
                    Text("左右のボタン、またはiPhone図の下の↔をドラッグして配置します。接続後に「待機する」を押し、画面中央から配置した側の端へポインターを移動して0.7秒止めると1回だけ切り替わります。MouseLink内だけの機能です。")
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
