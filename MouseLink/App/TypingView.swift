// SPDX-License-Identifier: AGPL-3.0-only
import SwiftUI

struct TypingView: View {
    @ObservedObject var session: TypingSession
    @Environment(\.dismiss) private var dismiss
    @FocusState private var draftFocused: Bool
    @State private var uppercase=false
    @State private var showKeys=false
    private var validDraft: Bool { !session.draft.isEmpty && session.validation == nil }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    Label(session.available ? "iPhoneの入力欄へ転送" : "キーボード受信先が未接続",systemImage:session.available ? "keyboard.badge.ellipsis" : "keyboard")
                        .font(.headline).accessibilityIdentifier("typing-connection")
                    Text("iPhoneで入力欄をクリック → マウス中央ボタンでiPadに戻る → この画面で入力します。ここではマウスをiPadの画面操作に使えます。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Picker("入力する文字",selection:$session.mode) {
                        ForEach(KeyboardTextMode.allCases,id:\.self) { mode in Text(mode.title).tag(mode) }
                    }.pickerStyle(.segmented).disabled(session.isSending).accessibilityIdentifier("text-mode")
                    VStack(alignment:.leading,spacing:8) {
                        TextField(session.mode == .ascii ? "例: hello / nihongo" : "例: にほんご",text:$session.draft,axis:.vertical)
                            .lineLimit(2...4).textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                            .keyboardType(session.mode == .ascii ? .asciiCapable : .default)
                            .focused($draftFocused).submitLabel(.done)
                            .onSubmit { draftFocused=false }
                            .disabled(session.isSending).accessibilityIdentifier("typing-draft")
                        HStack {
                            Text("\(session.draft.count) / 256文字").monospacedDigit()
                            Spacer()
                            Button("下書きを消去") { session.draft="" }.disabled(session.isSending)
                        }.font(.caption)
                        if let error=session.validation { Text(error).font(.caption).foregroundStyle(.red).accessibilityIdentifier("draft-error") }
                        if let preview=session.wirePreview, !preview.isEmpty {
                            Text("送るキー列: \(preview)").font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(3)
                        }
                    }
                    HStack {
                        Button("文字を転送") { draftFocused=false;DispatchQueue.main.async { session.sendDraft(enter:false) } }
                            .buttonStyle(.bordered).accessibilityIdentifier("send-text")
                        Button("文字を転送 ＋ Enter") { draftFocused=false;DispatchQueue.main.async { session.sendDraft(enter:true) } }
                            .buttonStyle(.borderedProminent).accessibilityIdentifier("send-text-enter")
                    }.disabled(!session.canSend || !validDraft)
                    Text(session.status).font(.subheadline).fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("typing-status")
                    if session.isSending {
                        HStack {
                            ProgressView()
                            Text("残り \(session.remaining) レポート").font(.caption)
                            Spacer()
                            Button("転送を中止",role:.destructive) { session.cancel() }.accessibilityIdentifier("cancel-typing")
                        }
                    }
                    Divider()
                    VStack(alignment:.leading,spacing:10) {
                        Text("iPhoneへキーを送る").font(.headline)
                        Text("下のボタンは下書きを送らず、そのキーだけを送ります。Enterの働きは入力先によって異なります（確定・送信・検索・改行など）。")
                            .font(.caption).foregroundStyle(.secondary)
                        LazyVGrid(columns:[GridItem(.adaptive(minimum:110),spacing:8)],spacing:8) {
                            key("Enter",.enter,"remote-enter")
                            key("Shift + Enter",.shiftEnter,"remote-shift-enter")
                            key("⌫ 削除",.backspace,"remote-backspace")
                            key("Space / 変換",.space,"remote-space")
                            key("Tab",.tab,"remote-tab")
                            key("Esc",.escape,"remote-escape")
                            key("←",.left,"remote-left")
                            key("→",.right,"remote-right")
                            key("↑",.up,"remote-up")
                            key("↓",.down,"remote-down")
                        }
                        key("入力言語切替（Control + Space）",.inputSource,"remote-language")
                    }
                    DisclosureGroup("画面キーで1文字ずつ送る",isExpanded:$showKeys) {
                        VStack(alignment:.leading,spacing:12) {
                            Text("iPadのソフトウェアキーボードを使わず、マウスで各キーをクリックすることもできます。")
                                .font(.caption).foregroundStyle(.secondary)
                            Toggle("大文字を送る",isOn:$uppercase).disabled(session.isSending)
                            LazyVGrid(columns:[GridItem(.adaptive(minimum:44),spacing:6)],spacing:6) {
                                ForEach(Array("1234567890qwertyuiopasdfghjklzxcvbnm-.,'"),id:\.self) { char in
                                    let value=uppercase ? String(char).uppercased() : String(char)
                                    Button(value) { draftFocused=false;session.sendCharacter(value) }
                                        .font(.body.monospaced()).frame(maxWidth:.infinity,minHeight:40)
                                        .buttonStyle(.bordered).disabled(!session.canSend)
                                        .accessibilityIdentifier("remote-char-\(char)")
                                }
                            }
                        }.padding(.top,12)
                    }.accessibilityIdentifier("direct-keys")
                    Divider()
                    VStack(alignment:.leading,spacing:10) {
                        Text("日本語の使い方").font(.headline)
                        Text("iPhoneのキーボードに「日本語 - ローマ字」を追加・選択します。「かなの読み」で、ひらがな／カタカナを読みとして転送するか、「英数・ローマ字」で nihongo のように入力してください。候補を見ながらSpaceで変換し、Enterで確定します。送信にさらにEnterが必要かはiPhoneの画面で判断してください。")
                        Text("確定済みの漢字・絵文字をそのまま貼り付ける機能ではありません。カタカナも読みとして送ります。英数・記号はiPhone側をU.S.配列・Caps Lockオフにしてください。自動修正や入力言語によって表示が変わることがあります。")
                    }.font(.caption).foregroundStyle(.secondary)
                }.padding(22).frame(maxWidth:720).frame(maxWidth:.infinity)
            }.scrollDismissesKeyboard(.interactively)
            .navigationTitle("文字入力・Enter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.confirmationAction) { Button("閉じる") { session.close();dismiss() }.accessibilityIdentifier("close-typing") }
                ToolbarItemGroup(placement:.keyboard) { Spacer();Button("キーボードを閉じる") { draftFocused=false } }
            }
        }
    }
    private func key(_ title:String,_ stroke:KeyboardStroke,_ identifier:String) -> some View {
        Button { draftFocused=false;session.sendKey(stroke) } label: { Text(title).frame(maxWidth:.infinity,minHeight:36) }
            .buttonStyle(.bordered).disabled(!session.canSend).accessibilityIdentifier(identifier)
    }
}
