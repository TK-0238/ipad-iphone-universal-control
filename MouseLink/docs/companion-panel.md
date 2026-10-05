# MouseLink 0.4 — 別のアプリと並べる小窓パネル

全画面を占有する従来モードとは別に、見えている小窓のパッドだけでiPhoneを操作する方式を追加しました。Mac、PC、中継機器、物理キーボードは実行時に不要です。完全な背景制御ではありません。

## 使い方
1. iPadのSwift Playgroundで新しいMouseLink.swiftpmを実行します。
2. iPadOSのウインドウ機能で他のアプリと並べます。iPadOS 26では設定の「マルチタスクとジェスチャ」からウインドウ表示を選び、ウインドウの隅をドラッグして縮小。26.2以降はOSのSlide Overも利用可能です。iPadOS 17/18ではSplit View/Slide Over/対応モデルのステージマネージャを使います。
3. 幅700pt未満は自動でパネル表示になります。大きいまま試す場合は左上の「小窓パネル」を押します。複数のMouseLinkウインドウは作らず、MouseLink1枚＋他のアプリという構成です。
4. 接続待ちを開始し、iPhoneのAssistiveTouchからBluetoothペアリングを行います。受信先を選び、「パッドを有効にする」を押してください。
5. パッド内のマウス移動、左右クリック、ドラッグ、ホイールだけをiPhoneへ転送します。パッド外へ出ると移動を止めてドラッグを解除し、iPad側のポインターをそのまま操作できます。移動範囲を使い切ったときは一度外に出して置き直します。
6. 文字は下の「文字・Enter」から送信。別ウインドウへの操作、非表示、サイズ変更、接続変更ではパッドの許可を解除するため、再開には有効ボタンを押します。

## 従来との違い・限界
小窓ではポインターロックを要求しません。iPadOSの公開仕様ではSplit View/Slide Overで全画面用ポインターロックを前提にできないためです。MouseLinkの安全な全画面マウス転送を弱めるのではなく、ローカルUIKitイベントだけを受ける別の入力経路を使います。

他アプリ上の画面端や見えないパネルを監視しません。全画面のどこからでも自由にiPhoneへ行ける純正Universal Controlと同一ではありません。小窓のサイズ・配置・最前面化はOSとユーザーが管理し、アプリが勝手に他アプリを移動したり透明なオーバーレイを作ったりしません。

既存の英数/ローマ字/かなの読み、Enterの意味、日本語IMEの制約は引き継ぎます。漢字・絵文字の直接貼り付けは未対応です。実機のSwift Playground、Bluetooth通信、マウス入力・スクロールの向き、日本語変換は未検証で、自動テスト・シミュレーターの成功とは別です。

## 一次資料
- https://support.apple.com/125309 — ウインドウ表示・並べる操作・Slide Over
- https://developer.apple.com/documentation/bundleresources/information-property-list/uirequiresfullscreen — マルチタスクのオプトアウト
- https://developer.apple.com/documentation/technotes/tn3192-Migrating-your-app-from-the-deprecated-UIRequiresFullScreen-key — リサイズと全方向対応
- https://developer.apple.com/videos/play/wwdc2020/10094/ — iPadポインターロックの全画面条件、ローカルhover/scroll
