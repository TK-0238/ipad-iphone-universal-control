# MouseLink 0.2 — Bluetoothマウス・文字入力・Enter

**iPadで開くソース配布版。実機のBluetooth・Swift Playground・iPhoneアプリ内の動作は未検証です。純正Universal Controlの完全再現ではありません。**

## 0.2で追加
「文字入力・Enter」から、iPadの画面キーボードやマウスで文章を準備し、選択中のiPhoneへ文字転送／文字＋Enter／Enter単独を送ります。Space、Backspace、Tab、矢印、Esc、Shift+Enter、Control+Spaceにも対応。英文・数字・U.S.配列の記号は直接のキー列、日本語はローマ字または「かなの読み」を送ってiPhone側で変換します。

**確定済みの漢字・絵文字をそのままコピーする機能ではありません。** 対応外の文章は送信前に全体を拒否します。Enterが確定・送信・改行などのどの動作になるかはiPhoneの入力先によります。

詳しい手順と制限: [文字入力とEnter](docs/keyboard-enter.md)。配布ZIPにも同じ説明を含みます。

## 実行構成
マウス → iPadのMouseLink → Bluetooth HID → iPhoneのAssistiveTouch／キーボード入力。
Mac・PC・中継サーバー・Wi-Fiルーター・物理キーボード・iPhoneの受信アプリを実行時に必要としない構成です。iPadのMouseLinkが前面の間だけ動作します。OS全体の自動画面端切り替え・ミラーリングは行いません。物理マウス転送は中央ボタンまたは画面の停止ボタンでiPad操作へ戻せます。文字入力中はiPadのマウスをロックしません。

## iPadだけで開く
ZIPを「ファイル」で展開し、`MouseLink.swiftpm` をSwift Playgroundで開いて「Appを実行」します。署名済みIPAではありません。ダウンロードにインターネットは必要ですが、入力転送はBluetoothだけです。初回はiPhoneでAssistiveTouchをオンにし、デバイス → BluetoothデバイスからMouseLinkをペアリングします。

## 検証・再現
```
swift test
swift test --package-path MouseLink
python3 MouseLink/tools/package_keyboard_app.py
```
GitHub Actionsは既存／追加コアテスト、iOSビルド、実際のTypingSessionを使うNativeテスト、iPad UIテストを実行し、ZIP・ログ・スクリーンショットを保存します。Nativeテストの送信先はテスト用に差し替えており、無線通信の実機検証ではありません。実際に完了した結果はPRの検証記録を参照してください。

旧packagerで上流4ファイルの固定Git blob SHAを検証した後、キーボード用の変更を適用します。完全な元／改変ソースとライセンスをオフラインZIPへ同梱します。

## ライセンス
HOGP実装: Jingqian Sun / jqssun, darwin-bt-remote
https://github.com/jqssun/darwin-bt-remote
commit `ad7a76ce6132254fbd6085af87cea8d10aa8a82d`。
全体およびMouseLinkの変更はAGPL-3.0-only。ライセンス全文、元のソース、改変ソースは配布ZIPに含まれます。閉鎖ソース化やApp Store配信を許可するものではありません。
