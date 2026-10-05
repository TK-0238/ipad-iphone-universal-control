// SPDX-License-Identifier: AGPL-3.0-only
import SwiftUI
import UIKit
import GameController

/// Native workspace inspired by the arrangement/edge-handoff interaction, not an OS impersonation.
struct MouseLinkView: View {
    @ObservedObject var session: MouseSession
    @StateObject private var edge: EdgeSwitchController
    @AppStorage("MouseLink.devicePlacement") private var placementRaw = DevicePlacement.right.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sheet: WorkspaceSheet?
    private var placement: DevicePlacement { DevicePlacement(rawValue:placementRaw) ?? .right }
    private var receiverConnected: Bool { session.selected.map { session.receivers.contains($0) } == true }

    init(session: MouseSession) {
        self.session = session
        _edge = StateObject(wrappedValue: EdgeSwitchController(session:session))
    }
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    Color(uiColor:.systemGroupedBackground).ignoresSafeArea()
                    ScrollView {
                        VStack(alignment:.leading,spacing:24) {
                            heading
                            arrangement
                            handoff
                            if !receiverConnected { connectionSteps }
                            Text(session.message).font(.subheadline).foregroundStyle(.secondary)
                                .fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("status")
                            HStack {
                                Button("接続ガイド") { present(.guide) }.accessibilityIdentifier("guide")
                                Spacer()
                                Button("ライセンス・ソース") { present(.license) }.accessibilityIdentifier("license")
                            }.font(.footnote)
                            Text("MouseLinkを開いている間だけ利用できます。端末の図は配置用で、画面共有ではありません。")
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                        }.padding(24).frame(maxWidth:800).frame(maxWidth:.infinity)
                    }
                    if edge.isArmed {
                        HStack {
                            if placement == .right { Spacer() }
                            Capsule().fill(Color.accentColor.opacity(edge.progress > 0 ? 0.85 : 0.25))
                                .frame(width:5,height:160 + 70*edge.progress).padding(.horizontal,5)
                            if placement == .left { Spacer() }
                        }.allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let p):
                        edge.hover(EdgePointer(x:p.x,y:p.y,width:geometry.size.width,height:geometry.size.height))
                    case .ended: edge.hover(nil)
                    }
                }
                .onChange(of:geometry.size) { _,_ in edge.disarm() }
            }
            .safeAreaInset(edge:.bottom,spacing:0) { actionBar }
            .navigationTitle("MouseLink").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.topBarLeading) {
                    Label("Bluetoothで直接接続",systemImage:"point.3.connected.trianglepath.dotted")
                        .font(.caption).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
                }
                ToolbarItem(placement:.topBarTrailing) {
                    Button { present(.settings) } label: { Image(systemName:"slider.horizontal.3") }
                        .accessibilityLabel("設定").accessibilityIdentifier("open-settings")
                }
            }
            .sheet(item:$sheet,onDismiss:{ session.typing.close(); edge.disarm() }) { destination in
                switch destination {
                case .settings: WorkspaceSettings(session:session)
                case .guide: GuideView()
                case .license: LicenseView()
                case .typing: TypingView(session:session.typing)
                }
            }
            .onAppear { edge.setPlacement(placement) }
            .onChange(of:placementRaw) { _,_ in edge.setPlacement(placement) }
            .onChange(of:session.isRelaying) { _,_ in edge.disarm() }
            .onReceive(NotificationCenter.default.publisher(for:UIApplication.willResignActiveNotification)) { _ in edge.disarm() }
            .onReceive(NotificationCenter.default.publisher(for:.GCMouseDidDisconnect).receive(on:DispatchQueue.main)) { _ in edge.disarm() }
            .onReceive(NotificationCenter.default.publisher(for:.GCMouseDidConnect).receive(on:DispatchQueue.main)) { _ in edge.disarm() }
            .onDisappear { edge.disarm() }
        }
    }
    private var heading: some View {
        VStack(alignment:.leading,spacing:8) {
            Text(session.isRelaying ? "iPhoneを操作中" : "デバイスをつなぐ")
                .font(.largeTitle.bold()).accessibilityIdentifier("headline")
            Text(session.isRelaying ? "視線はiPhoneへ。マウスはそのまま。" : "iPhoneを置いている側に合わせて配置します。")
                .font(.body).foregroundStyle(.secondary)
        }
    }
    private var arrangement: some View {
        VStack(spacing:20) {
            DeviceArrangementView(placement:placement, remoteActive:session.isRelaying,
                connected:receiverConnected, canStart:session.canStart && !session.isRelaying,
                switchToPhone:{ edge.disarm(); session.start() }, switchToPad:{ edge.disarm(); session.pause() },
                move:{ value in edge.disarm(); placementRaw = value.rawValue })
            HStack(spacing:12) {
                Text("iPhoneの位置").font(.subheadline).foregroundStyle(.secondary)
                ForEach(DevicePlacement.allCases,id:\.self) { side in
                    Button {
                        edge.disarm()
                        withAnimation(reduceMotion ? nil : .easeInOut(duration:0.2)) { placementRaw = side.rawValue }
                    } label: {
                        Label(side.title,systemImage:side == .left ? "arrow.left" : "arrow.right")
                            .font(.subheadline.weight(.medium)).frame(minWidth:58,minHeight:32)
                    }.buttonStyle(.bordered).tint(placement == side ? .accentColor : .secondary)
                        .accessibilityLabel("iPhoneを\(side.title)に配置")
                        .accessibilityValue(placement == side ? "選択中" : "未選択")
                        .accessibilityIdentifier("place-\(side.rawValue)")
                        .disabled(session.isRelaying)
                }
            }
            Divider()
            ViewThatFits(in:.horizontal) {
                HStack(spacing:24) { inputStatus; Spacer(); receiverStatus }
                VStack(alignment:.leading,spacing:12) { inputStatus; receiverStatus }
            }
        }.padding(20).background(Color(uiColor:.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:20))
    }
    private var inputStatus: some View {
        Label(session.mouseName ?? "マウス未接続",systemImage:"computermouse")
            .font(.subheadline).lineLimit(2).accessibilityIdentifier("mouse-status")
    }
    private var receiverStatus: some View {
        Menu {
            ForEach(session.receivers,id:\.self) { peer in
                Button {
                    edge.disarm(); session.select(peer)
                } label: { Label("受信先 \(peer.uuidString.prefix(8))",systemImage:peer == session.selected ? "checkmark" : "iphone") }
            }
            Button("接続設定…") { present(.settings) }
        } label: {
            Label(receiverConnected ? "受信先を接続済み" : "iPhone未接続",systemImage:receiverConnected ? "checkmark.circle.fill" : "iphone")
                .font(.subheadline).foregroundStyle(receiverConnected ? Color.accentColor : Color.secondary)
        }.disabled(session.isRelaying).accessibilityIdentifier("receiver-menu")
    }
    private var handoff: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack(alignment:.top) {
                VStack(alignment:.leading,spacing:4) {
                    Text("画面端で切り替え").font(.headline)
                    Text("この画面の\(placement.edgeDescription)で、ポインターを0.7秒止めます。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength:12)
                if edge.isArmed {
                    Button("待機を解除") { edge.disarm() }.buttonStyle(.bordered).accessibilityIdentifier("cancel-edge")
                } else {
                    Button("待機する") { edge.arm() }.buttonStyle(.bordered)
                        .disabled(!session.canArmEdgeHandoff).accessibilityIdentifier("arm-edge")
                }
            }
            if edge.isArmed {
                ProgressView(value:edge.progress).accessibilityLabel("端から切り替えの進行")
                Text("画面中央から\(placement.edgeDescription)へ。通り過ぎるだけ、またはドラッグ中では切り替わりません。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("接続後に待機を許可すると1回だけ有効。ほかのアプリ上では動作しません。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var connectionSteps: some View {
        VStack(alignment:.leading,spacing:14) {
            Text("はじめての接続").font(.headline)
            setupRow("1",title:"マウスをiPadにつなぐ",detail:"いつも使うマウスをBluetoothなどで接続。",done:session.mouseName != nil)
            setupRow("2",title:"iPhoneとペアリング",detail:"AssistiveTouch → デバイス → BluetoothデバイスでMouseLinkを選択。",done:false)
            HStack {
                Button("接続待ちを開始") { edge.disarm(); session.advertise() }
                    .buttonStyle(.borderedProminent).accessibilityIdentifier("advertise")
                Text(session.bluetoothStatus).font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth:.infinity,alignment:.leading).padding(18).background(Color(uiColor:.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:16))
    }
    private func setupRow(_ number:String,title:String,detail:String,done:Bool) -> some View {
        HStack(alignment:.top,spacing:12) {
            Group {
                if done { Image(systemName:"checkmark.circle.fill").foregroundStyle(Color.accentColor) }
                else { Text(number).font(.subheadline.weight(.semibold)) }
            }.frame(width:26,height:26).background(Color.secondary.opacity(0.09),in:Circle())
            VStack(alignment:.leading,spacing:3) { Text(title).font(.subheadline.weight(.medium)); Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
    }
    private var actionBar: some View {
        VStack(spacing:0) {
            Divider()
            ViewThatFits(in:.horizontal) {
                HStack(spacing:14) { actionState; Spacer(minLength:14); primaryActions }
                VStack(alignment:.leading,spacing:12) { actionState; primaryActions }
            }.padding(.horizontal,24).padding(.vertical,14).frame(maxWidth:850).frame(maxWidth:.infinity)
        }.background(.regularMaterial)
    }
    private var actionState: some View {
        VStack(alignment:.leading,spacing:2) {
            Label(session.isRelaying ? "iPhoneへ転送中" : "このiPadを操作中",systemImage:session.isRelaying ? "iphone" : "ipad.landscape")
                .font(.subheadline.weight(.semibold))
            Text(session.isRelaying ? "中央ボタンでiPadに戻る" : "接続後、iPhoneへ切り替え")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var primaryActions: some View {
        HStack(spacing:10) {
            Button { present(.typing) } label: { Label("文字入力",systemImage:"keyboard").padding(.vertical,6) }
                .buttonStyle(.bordered).accessibilityLabel("文字入力・Enter").accessibilityIdentifier("open-typing")
            if session.isRelaying {
                Button { edge.disarm(); session.pause() } label: { Label("iPadに戻る",systemImage:"arrow.uturn.backward").padding(.vertical,6) }
                    .buttonStyle(.borderedProminent).accessibilityIdentifier("pause").keyboardShortcut(.escape,modifiers:[])
            } else {
                Button { edge.disarm(); session.start() } label: { Label("iPhoneに切り替え",systemImage:"arrow.right").padding(.vertical,6) }
                    .buttonStyle(.borderedProminent).disabled(!session.canStart).accessibilityIdentifier("start")
            }
        }
    }
    private func present(_ destination:WorkspaceSheet) {
        edge.disarm()
        if destination == .typing { session.openTyping() }
        else { session.pause(reason:"設定・ヘルプを開いている間は転送を停止します。") }
        sheet = destination
    }
}
private enum WorkspaceSheet: String,Identifiable { case settings, guide, license, typing; var id:String { rawValue } }

struct WorkspaceSettings: View {
    @ObservedObject var session: MouseSession
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("マウス") {
                    HStack {
                        Text("感度"); Slider(value:$session.sensitivity,in:0.25...3,step:0.05).accessibilityLabel("マウス感度")
                        Text(session.sensitivity,format:.number.precision(.fractionLength(2))).monospacedDigit()
                    }
                    Toggle("スクロール方向を反転",isOn:$session.reverseScroll)
                }
                Section("Bluetoothの接続") {
                    Text(session.bluetoothStatus)
                    ForEach(session.receivers,id:\.self) { peer in
                        Button { session.select(peer) } label: {
                            HStack { Image(systemName:session.selected == peer ? "checkmark.circle.fill" : "circle")
                                Text("受信先 \(peer.uuidString.prefix(8))").monospaced() }
                        }
                    }
                    Button("接続待ちを開始") { session.advertise() }
                    Button("すべて切断",role:.destructive) { session.disconnect() }
                }
                Section("詳細") {
                    if let selected = session.selected { LabeledContent("受信先ID") { Text(selected.uuidString).font(.caption.monospaced()).textSelection(.enabled) } }
                    Text("表示名や図だけでは相手を識別できません。ペアリング時にiPhoneを確認し、選択した受信先にだけ転送します。")
                    Text("画面端の待機は保存されません。接続変更・非アクティブ化・画面の切り替えで解除されます。")
                }.font(.footnote)
            }.navigationTitle("設定").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("完了") { dismiss() }.accessibilityIdentifier("close-settings") }
        }
    }
}
