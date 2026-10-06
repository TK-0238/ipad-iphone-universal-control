# MouseLink 0.2 — 文字入力とEnter

旧版0.1はマウス転送のみでした。0.2はBluetooth HIDキーボードのキーを、iPadの画面から選択中のiPhoneへ直接送る機能を追加しています。実行時のMac・PC・外部サーバー・Wi-Fiルーター・物理キーボード・iPhone側アプリは不要な構成です。手元の実機でのペアリング／入力動作は未確認です。

## 使い方
1. iPadのSwift Playgroundで0.2の `MouseLink.swiftpm` を開き実行します。既に0.1を開いている場合は古いAppを止めて新しいものを開いてください。Bluetoothの古いペアリングが残る場合は登録解除してペアリングし直します。
2. iPhoneの入力したいアプリを開き、入力欄をマウスでクリックします。マウス中央ボタン（なければiPad画面の停止ボタン）でiPad操作に戻り、MouseLinkの「文字入力・Enter」を開きます。文字入力画面でマウスをロックしません。
3. iPadで文章を入力し「文字を転送」または「文字を転送 ＋ Enter」を押します。ソフトウェアキーボードのReturnはローカル編集の終了だけで、iPhoneへ自動送信しません。物理キーボードなしで「画面キーで1文字ずつ送る」からマウスでも入力できます。
4. 「Enter」は下書きを送らずEnterだけを1回送ります。「Shift + Enter」「Space / 変換」「⌫ 削除」「Tab」「Esc」「矢印」「入力言語切替（Control + Space）」もあります。

## 日本語
- iPhoneで「設定 → 一般 → キーボード → キーボード」から「日本語 - ローマ字」を追加し、入力中の言語として選んでください。Control+Spaceボタンでも追加済みの言語を順に切り替えます。現在の言語はBluetooth経由で自動判定しません。
- 「英数・ローマ字」では `nihongo` のようなキー列を送ります。
- 「かなの読み」では `にほんご` を `nihon'go` のようなローマ字キー列へ変換して送ります。カタカナも読みとして送るため、元の表記をそのまま再現する保証はありません。送信前に実際のキー列を表示します。
- iPhone画面を見て「Space / 変換」で候補を選び、Enterで確定します。送信に追加のEnterが必要かは入力先によります。アプリは自動でEnterを2回送りません。
- **iPadで確定した漢字や絵文字を、そのままiPhoneへ貼り付ける機能ではありません。** 対応外の文字を含む文章は全体を送信前に拒否し、読みに勝手に推測変換したり文字を消したりしません。必要な漢字はiPhoneの変換で選びます。

## 英数・記号／Enterの注意
英数・記号はU.S.配列のHIDマッピングを使用します。iPhone側のハードウェアキーボードをU.S.配列、Caps Lockオフにしてください。別配列・自動修正・入力言語により結果が変わります。EnterはHID usage 0x28の押下と解放を送信します。送信、検索、改行、変換確定のどれになるかはiPhoneのアプリ／入力欄が決めます。

一度に256文字まで。改行、タブ、制御文字を貼り付けた文章は、意図しない送信やフォーカス移動を防ぐため拒否します。専用ボタンを使ってください。

## 安全動作
キーごとに押下／解放を順番に送り、同じ文字の連続も取りこぼさない構成です。転送先は選択中の1台だけで、BootとReportの両方へ重複送信しません。500ms以上送信受付が進まない場合や、切断・非アクティブ化・中止・入力画面を閉じた場合は残りを破棄し、キー解放を試みます。解放を送れない場合は接続を破棄します。未送信のEnterを再接続後に再生しません。

Bluetoothが受け付けたこととiPhoneアプリが文字を入力したことは別です。表示は「Bluetoothへの送信受付が完了」とし、相手アプリの成功を推測表示しません。途中停止では一部だけ届いている場合があるため、iPhoneを見て確認してください。下書きはアプリのメモリだけに保持し、入力内容をログ・ファイル・外部サーバーへ保存しません。

## 検証の区別
- Core tests: 文字→キー列、Enter、修飾キー、キー解放、Unicode拒否、順序、送信間隔、切断の制御。
- Native tests: 実際のTypingSessionから注入可能な送信先へ流し、iPadの文字送信操作→HIDバイト列までを検証。これはBluetooth実機テストではありません。
- UI tests: iPadシミュレータで文字入力画面・未接続時の送信禁止・画面キーを確認。
- 実機のSwift Playground、Bluetoothペアリング、日本語IMEの変換候補、他アプリでのEnter動作は未検証。

パッケージ生成: `python3 MouseLink/tools/package_keyboard_app.py`。旧packagerを実行し、固定SHA検証したHIDソースにキーボード転送を追加して再梱包します。完全な改変ソースとAGPL-3.0-onlyライセンスを同梱します。

## 一次資料
Apple: UIKeyboardHIDUsage.keyboardReturnOrEnter
https://developer.apple.com/documentation/uikit/uikeyboardhidusage/keyboardreturnorenter
Apple: Magic KeyboardおよびiPhoneを使用してキーボードを切り替える
https://support.apple.com/ja-jp/guide/iphone/iph5948b3f2e/26/ios/26
Apple: iPhoneのキーボードを追加する/変更する
https://support.apple.com/ja-jp/guide/iphone/iph73b71eb/ios
Apple: iPhoneでユーザ辞書に単語を登録する（日本語ローマ字・かな）
https://support.apple.com/ja-jp/guide/iphone/iph6d01d862/ios
