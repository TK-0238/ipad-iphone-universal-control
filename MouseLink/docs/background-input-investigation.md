# 他アプリ使用中の画面端切り替え — 調査と未解決事項

調査日: 2026-10-05。対象: MouseLink 0.3.1、Draft PR #2。

**主要求は未解決です。以下の停止処理の修正を、バックグラウンド入力対応と呼びません。**

## ユーザーが必要としていること

iPadでSafariなど別のアプリを使用したまま、1台のマウスを画面端へ動かしてiPhoneへ入力先を移す。MouseLinkを開きっぱなしにしない。Mac/PC/中継サーバー/追加HID機器を実行時に使用しない。

## 分けて確認した三つの条件

1. **実行を継続する**: 処理がバックグラウンドでスケジュールされること。
2. **ポインターを観測する**: 別のアプリ内で動かしているマウス位置とボタン状態を取得すること。
3. **入力先を切り替える**: iPhoneへ送る間はiPadで同じクリックが実行されず、明示操作で確実に戻れること。

1だけを実現しても2・3は成立しません。今回調べた公開APIと現行のSwift Playground配布形式では、2・3を満たす経路を確認できていません。これは全てのOSバージョン、将来のAPI、個別ハードウェアの可能性を否定する結論ではありません。

## 一次資料に基づく確認

| 候補 | 資料から確認した機能 | 今回の要求との差 |
|---|---|---|
| CoreBluetooth background modes | BLEの読み書き・購読などに応じてアプリが起動される仕組み | グローバルなマウスイベントや画面座標の取得権限とは別 |
| iOS 26のLive ActivityとCoreBluetooth | CBManagerを作成しLive Activityを開始した場合の背景BLE権限 | Bluetooth APIの権限であり、GCMouse/他アプリのポインター権限ではない |
| GCMouse / UIKit hover | 物理マウスの相対移動、アプリのビュー内のhover、シーンのpointer lock | GCMouseは現在のOSカーソル位置を取得するAPIを提供せず、ビューのhoverで別アプリの端を検出できない |
| GCController.shouldMonitorBackgroundEvents | Appleのプラットフォーム資料はmacOSのゲームコントローラーに対する背景監視を説明 | iPadのGCMouseにそのまま適用できる保証がない。GCControllerとGCMouseを混同しない |
| DriverKit | 対応する外付け機器向けのドライバー。ファミリーの対応はプラットフォームごとに異なる | 権限付きドライバーの署名・対象機器・配布が必要。通常アプリの全画面カーソルフックだと仮定しない |
| AssistiveTouch Hot Corners + Shortcuts | OS側で画面の四隅への滞在を検出し、ショートカットを実行できる | MouseLinkを開く迂回策は依然として前面転送。元のアプリを表示し続ける要求と同一視しない |
| 継続処理タスク / ReplayKit | 特定の仕事の継続や画面映像を扱う用途 | 入力先の排他切替権限やグローバルカーソルAPIが追加される根拠は得られなかった |

`setForeground(false)`・pointer lock確認を削除する、使わない音声を再生し続ける、BLE background設定だけ追加する、といった変更で「対応済み」に見せる修正は行いません。別アプリでの操作をiPhoneへ二重送信する可能性のある未検証経路も既定で有効化しません。

## 別途修正した項目

0.3の文字転送モデルはSwiftUIから渡された前面状態を保持しており、UIKitの非アクティブ通知をモデル自身では監視していませんでした。SwiftUIの状態反映がまだ届いていない順序をNativeテストで再現しました。UIKitのwillResignActive/didEnterBackground通知を文字転送モデル自身が同期的に購読し、通知が戻るまでに既存の停止処理を実行するよう修正しました。UIの前面制限やBluetoothのバックグラウンドモードを変更したものではありません。

このテストは通知の順序を注入するソフトウェア試験です。実際のiPhoneで誤送信を観測したものではありません。新しい停止経路でも、未送信の文字・Enterは破棄し、同じ接続にだけ全キー解除を試みます。解除を受け付けられなければ接続を破棄します。復帰による自動再送は行いません。

## 修正前の再現記録
テストのみのcommit `3b58de37a2bb7f5867a2bd19daf48ee4fe58d3bf`、GitHub Actions run `37257775616`（job `111598427312`）。追加した `TypingLifecycleTests` の4メソッド、10アサーションが実際に失敗しました。

- 非アクティブ化通知内での即時停止とキー解除。
- 背景移行通知後、SwiftUI更新前のEnter送信拒否。
- 復帰後に途中の文章・Enterを再送しないこと。
- キー解除が通信混雑で送れない場合の切断。

このテストのみのコミットのCIは意図したREDで、配布推奨版ではありません。修正後の全件再検証の実結果は、GitHub ActionsとDraft PR #2の最新検証記録を参照してください。Core/Native/UIテストの成功を、グローバルな画面端切替や実機Bluetoothの成功へ読み替えません。

## 完了と判断する前に必要な証拠

実機で別アプリを前面にした状態の入力取得、画面端の検出、iPadとiPhoneへの入力の排他性、切断時の解除、戻り操作を確認すること。その前に現在のCIが成功しても、この主要求の達成を意味しません。

## 出典

- CoreBluetooth (iOS 26 / Live Activityの説明): https://developer.apple.com/documentation/corebluetooth/
- Core Bluetooth Background Processing: https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html
- Bring keyboard and mouse gaming to iPad, WWDC20: https://developer.apple.com/videos/play/wwdc2020/10617/
- Handle trackpad and mouse input, WWDC20: https://developer.apple.com/videos/play/wwdc2020/10094/
- Apple Game Controller platform notes: https://github.com/apple/game-porting-toolkit/blob/main/game-porting-skills/skills/using-game-controller/reference/platform-notes.md
- DriverKit: https://developer.apple.com/documentation/DriverKit
- Creating drivers for iPadOS: https://developer.apple.com/documentation/driverkit/creating-drivers-for-ipados
- AssistiveTouch / Hot Corners: https://support.apple.com/en-asia/guide/ipad/ipad9a2466d3/ipados
- UIKit active/inactive transition: https://developer.apple.com/documentation/uikit/uiapplicationdelegate/applicationwillresignactive(_:)
- ScenePhase (App内での取得は複数シーンの集約): https://developer.apple.com/documentation/swiftui/scenephase

ユーザーのMac・共有GUI・認証・ペアリング・実アプリにはアクセスせず、Draft PRのみを更新します。バックグラウンド対応を根拠なく宣言する権限設定、merge、Release、App Store公開は行いません。
