# MouseLink 0.4 — iPadの小窓からiPhoneへ

別のアプリを表示したまま、MouseLinkを小さなウインドウとして横に置いて使う実装です。実行時にMac/PC/中継サーバー/追加HID機器/物理キーボードは不要な構成を維持しています。**実機でのSwift Playground・Bluetooth入力は未検証です。**

## 使い始める
配布ZIPを展開し、iPadのSwift Playgroundで `MouseLink.swiftpm` を実行します。iPadOSのWindowed Apps・Split View・Slide Over・Stage Managerで他のアプリと並べてください。幅700pt未満では操作パネルへ自動切り替えし、大きい画面でも左上の「小窓パネル」で選択できます。

マウスをiPadへ接続し、MouseLinkの接続待ちを開始。iPhoneのAssistiveTouch → デバイス → Bluetoothデバイスでペアリングして受信先を選び、パッドを有効にします。パッド内の移動・左右クリック・ドラッグ・ホイールだけを転送し、パッドの外はiPadの通常操作です。指でなぞる移動とタップもあります。

文字・Enterは下部のボタンから。日本語はローマ字/かなの読みを送りiPhone側IMEで変換します。確定済みの漢字・絵文字の直接貼り付けではありません。

詳細: [小窓パネルの使い方](docs/companion-panel.md)、[文字・Enter](docs/keyboard-enter.md)。

## 制限
小窓は表示して操作対象にする必要があります。完全な背景監視、他アプリ上の画面端からの切り替え、見えない小窓からの転送ではありません。ウインドウ配置はOS/ユーザーが行います。MouseLink自身を複数同時に開くのではなく、MouseLink1枚＋他アプリで使います。

ポインターを閉じ込めない方式なので、移動範囲を使い切ったら一度パッドから外し、置き直します。非アクティブ化、非表示、リサイズ、接続変更で停止し、未送信の動き/文字/Enterを再生しません。Bluetoothの送信受付とiPhone上での動作成功は別です。

従来の全画面・端末配置モードも残しています。小窓用の入力経路はUIKitのローカルイベントのみで、全画面モードのポインターロックの安全条件を削除していません。

## 開発・検証
```
swift test --package-path MouseLink
python3 MouseLink/tools/package_panel_app.py
python3 MouseLink/tools/test_hardening.py -v
python3 MouseLink/tools/test_panel_package.py -v
```

CIはCore Debug/Release、Native/UI、端末向け/シミュレーター向けのビルドを検証します。送信先を置き換えたNativeテストは実Bluetoothテストではありません。署名済みIPAではなくソース形式で配布します。

## ライセンスと元ソース
Bluetooth HID部分はJingqian Sun / jqssun のdarwin-bt-remote、固定commit `ad7a76ce6132254fbd6085af87cea8d10aa8a82d`、AGPL-3.0-only。各Git blob SHAを検証し、原本・改変ソース・ライセンス全文を配布ZIPへ同梱しています。今回の変更もAGPL-3.0-onlyです。mainへのマージ、Release、App Store公開は行いません。
