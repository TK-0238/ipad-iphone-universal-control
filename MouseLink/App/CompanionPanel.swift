// SPDX-License-Identifier: AGPL-3.0-only
import SwiftUI
import GameController

/// A single resizable MouseLink window alongside other apps, not several competing HID sessions.
struct MouseLinkView: View {
    @ObservedObject var session:MouseSession
    @State private var preferPanel=false
    @StateObject private var panel:PanelSession
    @Environment(\.scenePhase) private var phase
    init(session:MouseSession) {
        self.session=session;_panel=StateObject(wrappedValue:PanelSession(sender:session.bluetooth))
    }
    var body:some View {
        GeometryReader { g in
            Group {
                if preferPanel || g.size.width < 700 {
                    CompanionPanel(session:session,panel:panel,canExpand:g.size.width >= 700,onExpand:{ panel.disable();preferPanel=false })
                } else {
                    FullWorkspaceView(session:session,openPanel:{ session.pause();panel.disable();preferPanel=true })
                }
            }.onChange(of:g.size) { _,_ in session.pause(reason:"ウインドウを変更したため操作を停止しました。");panel.geometryChanged() }
        }
        .onChange(of:phase) { _,value in panel.setForeground(value == .active) }
        .onChange(of:session.selected) { _,_ in panel.disable() }
        .onReceive(NotificationCenter.default.publisher(for:.GCMouseDidDisconnect).receive(on:DispatchQueue.main)) { _ in panel.disable() }
        .onDisappear { panel.disable() }
    }
}

struct CompanionPanel: View {
    @ObservedObject var session:MouseSession
    @ObservedObject var panel:PanelSession
    let canExpand:Bool
    let onExpand:()->Void
    @State private var sheet:WorkspaceSheet?
    init(session:MouseSession,panel:PanelSession,canExpand:Bool,onExpand:@escaping ()->Void) {
        self.session=session;self.panel=panel;self.canExpand=canExpand;self.onExpand=onExpand
    }
    private var connected:Bool { session.selected.map { session.bluetooth.mouseReceivers.contains($0) } == true }
    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    VStack(alignment:.leading,spacing:6) {
                        Label("ほかのアプリと並べて使う",systemImage:"rectangle.split.2x1")
                            .font(.headline).accessibilityIdentifier("panel-heading")
                        Text(connected ? "受信先 \(session.selected!.uuidString.prefix(8))" : "iPhone未接続")
                            .font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("panel-connection")
                    }
                    if !connected {
                        Button("接続待ちを開始") { session.advertise() }
                            .buttonStyle(.bordered).accessibilityIdentifier("panel-advertise")
                    }
                    Button {
                        if panel.isEnabled { panel.disable(reason:"パッドを停止しました。") }
                        else { session.pause();panel.sensitivity=session.sensitivity;panel.reverseScroll=session.reverseScroll;panel.enable(peer:session.selected) }
                    } label: {
                        Label(panel.isEnabled ? "パッドを停止" : "パッドを有効にする",systemImage:panel.isEnabled ? "pause.fill" : "cursorarrow")
                            .frame(maxWidth:.infinity,minHeight:36)
                    }.buttonStyle(.borderedProminent).disabled(!connected)
                        .accessibilityIdentifier("panel-enable")
                    PanelPadView(panel:panel).frame(height:200)
                    Text(panel.status).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("panel-status")
                    Divider()
                    Text("ウインドウを細くすると、このパネルに切り替わります。パッドの端では一度マウスを外へ出し、置き直せます。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("並べ方・操作ガイド") { present(.guide) }.font(.footnote).accessibilityIdentifier("panel-guide")
                    if canExpand { Button("端末配置の画面へ") { session.pause();onExpand() }.accessibilityIdentifier("panel-expand") }
                }.padding(16).frame(maxWidth:480).frame(maxWidth:.infinity)
            }.scrollDisabled(panel.isEnabled && panel.isInside)
                .background(Color(uiColor:.systemGroupedBackground))
                .safeAreaInset(edge:.bottom,spacing:0) {
                    HStack(spacing:12) {
                        Button { present(.typing) } label: { Label("文字・Enter",systemImage:"keyboard").frame(maxWidth:.infinity,minHeight:36) }
                            .buttonStyle(.bordered).accessibilityIdentifier("panel-typing")
                        Button("停止",role:.destructive) { panel.disable();session.pause() }.buttonStyle(.bordered)
                            .accessibilityIdentifier("panel-stop")
                    }.padding(12).background(.regularMaterial)
                }
                .navigationTitle("MouseLink パネル").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.topBarTrailing) {
                    Button { present(.settings) } label: { Image(systemName:"slider.horizontal.3") }
                        .accessibilityLabel("設定").accessibilityIdentifier("panel-settings")
                } }
                .sheet(item:$sheet,onDismiss:{ session.typing.close() }) { item in
                    switch item {
                    case .settings:WorkspaceSettings(session:session)
                    case .typing:TypingView(session:session.typing)
                    case .license:LicenseView()
                    case .guide:PanelGuideView()
                    }
                }
                .onDisappear { panel.disable() }
        }
    }
    private func present(_ value:WorkspaceSheet) {
        panel.disable();session.pause();if value == .typing { session.openTyping() };sheet=value
    }
}

struct PanelGuideView:View {
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        NavigationStack {
            List {
                Section("他のアプリを表示したまま使う") {
                    Text("iPadのウインドウ機能で、SafariなどとMouseLinkを並べてください。MouseLinkを細くすると操作パネルになります。全画面をMouseLinkで占有する必要はありません。")
                }
                Section("iPadOS 26以降") {
                    Text("設定 → マルチタスクとジェスチャ → ウインドウ表示アプリ。ウインドウの隅をドラッグして縮小し、ほかのアプリの隣へ置きます。26.2以降はOSのウインドウ操作からSlide Overも選べます。")
                }
                Section("iPadOS 17・18") {
                    Text("OSのマルチタスクメニューからSplit ViewまたはSlide Overを選びます。対応モデルではステージマネージャでも配置できます。")
                }
                Section("マウスと文字") {
                    Text("接続後にパッドを有効にします。パッド内のマウス移動・クリック・ホイールだけをiPhoneへ転送します。外へ出すと移動を止め、ドラッグを解除します。文字・Enterは下のボタンから開きます。")
                }
                Section("停止と再開") {
                    Text("別ウインドウへの操作、非表示、サイズ変更、接続変更で停止します。再開にはパッドを有効にしてください。他アプリ上の画面端は監視しません。ポインターを閉じ込めないため、移動範囲はパッドの内側です。")
                }
                Section("接続") {
                    Text("マウスをiPadへ接続し、接続待ちを開始します。iPhoneのAssistiveTouch → デバイス → BluetoothデバイスでMouseLinkを選択してください。実機のBluetooth動作は別途確認が必要です。")
                }
            }.navigationTitle("小窓の使い方").toolbar { Button("閉じる") { dismiss() } }
        }
    }
}
