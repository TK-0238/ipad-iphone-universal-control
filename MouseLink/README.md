# MouseLink 0.3.1 — アプリ切替時の文字転送停止を修正

**iPadで開くソース配布版。実機のBluetooth・Swift Playground・iPhoneでの動作は未検証です。Apple純正Universal Controlの完全再現ではありません。**

## 0.3.1の修正と未解決事項
**ほかのiPadアプリを使ったままの画面端切替は未対応のままです。この更新はバックグラウンド操作対応版ではありません。** Bluetoothのバックグラウンド実行だけでは、他アプリ上のポインター取得と入力先の排他切替を実現できる根拠になりません。[調査記録](docs/background-input-investigation.md)に検討経路と未解決点をまとめています。

別件として、UIKitの非アクティブ化通知がSwiftUIの状態更新より先に届く場合に、文字転送が残る順序依存を修正しました。文字転送モデルが通知を直接受け取り、通知処理内で未送信文字とEnterを破棄し、元の接続へキー解除を試みます。解除できなければ既存処理で接続を破棄します。復帰しても自動再送しません。実機で誤送信を観測したという意味ではなく、アプリモデルに通知順を再現した回帰テストです。

## 0.3の操作画面
普段の画面を「端末の配置図・操作先・下の操作バー」に整理しました。左右のボタンやiPhone図の下の↔のドラッグで、実際の置き方に合わせます。配置だけは次回も保持し、転送の許可は保存しません。

接続したiPhoneの図、または「iPhoneに切り替え」で転送します。「文字入力」は下のバーから1回で開き、感度・スクロール方向・接続先の詳細は右上の設定へ移しました。端末の図は配置用の模式図で、画面共有やiPhoneの実ポインター位置ではありません。

「画面端で切り替え」で待機を許可すると、この画面の中央から配置した側の端へポインターを移動し、0.7秒待つことで1回だけ切り替えられる実装です。端に最初から置いたまま、通り過ぎるだけ、ボタンを押してドラッグしている間は切り替えません。切断・設定表示・アプリ非アクティブ化などで待機を解除します。物理マウスでの実機挙動は未確認です。

**端からの切り替えはMouseLink内のみです。** ほかのiPadアプリの画面端や、iPhoneの端からの自動復帰には対応していません。iPadへはマウスの中央ボタンまたは画面の「iPadに戻る」で戻ります。

## 文字入力・Enter
下書きの文字転送／文字＋Enter／Enter単独、Space、Backspace、Tab、矢印、Esc、Shift+Enter、Control+Spaceを維持しています。英文・数字・U.S.配列の記号はキー列、日本語はローマ字または「かなの読み」を送ってiPhone側で変換します。

**確定済みの漢字・絵文字をそのままコピーする機能ではありません。** 対応外文字は送信前に文章全体を拒否します。Enterが変換確定・送信・改行などのどの動作になるかはiPhoneの入力先によります。文字入力画面ではiPadのマウスをロックしません。

手順: [文字入力とEnter](docs/keyboard-enter.md)、[配置と端の切り替え](docs/continuity-ux.md)。配布ZIPにはそれぞれ「文字入力とEnter.md」「操作画面と画面端切替.md」を含みます。

## iPadで開く
ZIPを「ファイル」で展開し、`MouseLink.swiftpm` をSwift Playgroundで開いてフルスクリーンで実行します。古い版のAppは先に停止します。**署名済みIPAではありません。** 初回ダウンロードにはインターネットが必要ですが、実行時の入力経路はBluetoothだけです。

iPadにマウスを接続し、MouseLinkで「接続待ちを開始」。iPhoneでAssistiveTouchをオンにし、「デバイス → Bluetoothデバイス」からMouseLinkをペアリングします。選択した受信先だけに送ります。iPad・iPhone・マウス以外の中継機器、物理キーボード、iPhone側受信アプリは不要な構成です。

## 検証・再現
```
swift test
swift test --package-path MouseLink
swift test --package-path MouseLink -c release
python3 MouseLink/tools/package_ux_app.py
python3 MouseLink/tools/test_hardening.py -v
```
GitHub Actionsは既存／追加コアテスト、Simulator Debug・device Releaseビルド、Nativeテスト、iPad UIテストを実行し、ZIP・ログ・画面画像を保存します。Nativeテストの転送先は差し替えており、無線通信の実機検証ではありません。実際に完了した結果はDraft PR #2の検証記録を参照してください。

0.2.1のHID安全対策・文字入力・停止処理は保持しています。ビルド成功は実機でのペアリング／導入成功と同じではありません。日本語IMEやアプリごとのEnter動作、長時間・電波混雑下の動作も未検証です。

## ライセンス
HOGP実装: Jingqian Sun / jqssun, darwin-bt-remote
https://github.com/jqssun/darwin-bt-remote
commit `ad7a76ce6132254fbd6085af87cea8d10aa8a82d`。
全体およびMouseLinkの変更はAGPL-3.0-only。固定Git blob SHAを検証した原本・改変ソース・ライセンス全文はZIPに同梱します。閉鎖ソース化やApp Store配信を許可するものではありません。ユーザーのMac・アカウントや実機を操作していません。
