# MouseLink — iPadからiPhoneへ、マウスをBluetoothで直接転送

**実装済みソース。実機のBluetooth通信・マウス動作は未検証。純正Universal Controlの完全再現ではありません。**

## 何をするアプリか
マウスを接続したiPadをBluetooth HID入力機器として使い、iPhoneのAssistiveTouchへマウス移動・左クリック・右クリック・ホイールを直接送ります。Mac、PC、Wi-Fiルーター、中継サーバー、物理キーボード、iPhone側の受信アプリは実行時に使いません。iPadのMouseLinkが前面にある間だけ転送します。

iPadの別アプリ上から自動で画面端を越える機能、画面ミラーリング、OSへの任意タッチ注入はありません。中央ボタンまたは停止ボタンでiPad操作に戻ります。中央ボタンのないマウスでは停止ボタンのタップが必要です。接続許可や初期設定は端末のタッチ操作も使います。

## iPadだけで開く
1. 配布の `MouseLink-iPad.zip` を「ファイル」で展開します。
2. `MouseLink.swiftpm` をiPadのSwift Playgroundで開き、「Appを実行」を押します。プレビューではなくフルスクリーンを使います。
3. Bluetoothの使用を許可し、「接続待ちを開始」を押します。
4. iPhoneで「設定 → アクセシビリティ → タッチ → AssistiveTouch」をオン。「デバイス → Bluetoothデバイス」からMouseLinkをペアリングします。
5. iPadで受信先を選び、「iPhoneの操作を開始」を押します。

このZIPは署名済みIPAではありません。Swift Playground上でビルドして実行するソース一式です。初回ダウンロード/Swift Playgroundの入手にはインターネットが必要ですが、転送時の通信経路はBluetoothだけです。端末へのインストール・ペアリングはユーザー所有の実機で未確認です。

## 保護動作
初回に選んだ単一受信先へだけ送信。自動転送/自動再開なし。マウス切断・受信先喪失・アプリ非アクティブ化・送信キュー上限・500ms超の待機で停止し、全ボタン解除を試みます。解除通知を送れない状態が続くとBluetoothセッションを破棄します。既にOSが受理した無線パケットの到達時間や相手端末の応答は保証できません。

移動は小数を蓄積して分割し、クリックの押下/解放を順番通り保持します。停止したセッションの入力を再生しません。入力ログ、外部サーバー、解析SDKはありません。

## 検証
`swift test --package-path MouseLink` はBluetooth部分とは独立した**実際にアプリで使用する**キュー/移動処理をテストします。原型プロジェクトの3件のテストと新しいテストは別です。GitHub Actionsはソース整合性、iOSビルド、iPadシミュレータUIを検証し、ログと画面画像を保存します。シミュレータ成功は実機Bluetoothの成功を意味しません。ユーザーのMacにはアクセスしません。

## 再現可能なパッケージ作成
```
python3 MouseLink/tools/package_app.py
```
固定コミットの上流ファイルのGit blob SHAを検証して取り込み、完全なソースを含む `MouseLink/out/MouseLink-iPad.zip` を生成します。パッケージ作成時のみ上流を取得し、配布ZIPは外部Swiftパッケージ取得を必要としません。

## 出典とライセンス
Bluetooth HIDスタック: Jingqian Sun / jqssun, darwin-bt-remote
https://github.com/jqssun/darwin-bt-remote
commit `ad7a76ce6132254fbd6085af87cea8d10aa8a82d`, AGPL-3.0-only。
MouseLinkの変更部分もAGPL-3.0-onlyで提供。完全なライセンス、改変元、改変ソースを配布ZIPへ同梱。閉鎖ソース化やApp Store配信をこの作業で許可するものではありません。

Apple: AssistiveTouchでポインティングデバイスを使う
https://support.apple.com/111775
Apple: iPadのSwift PlaygroundでAppを実行する
https://support.apple.com/ja-jp/guide/playgrounds-ipad/itc650868b1f/ipados

前回の「使える経路がない」という説明はBluetooth HID方式を除外していたため不十分でした。ただし、この公開実装の存在と、ユーザーの具体的な実機構成の動作確認は別です。
