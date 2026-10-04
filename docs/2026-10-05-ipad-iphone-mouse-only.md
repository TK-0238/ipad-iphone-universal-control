# iPad・iPhone・マウスのみ：要件と実現性

更新日：2026-10-05
状態：**要件の確定と実現性調査まで。要求を満たすアプリの実装・実機検証は未完了。**

## 絶対条件

利用する機器はiPad、iPhone、マウス1台のみ。Mac、Windows PC、Raspberry Pi、外付けHIDブリッジ、常駐中継サーバーを必要とする方式は採用しない。物理キーボードも必須にしない。通信に外部ルーターやインターネットを必須にする設計は、端末だけで完結する要件を満たすものとして扱わない。

ユーザーの追加指示後はユーザーのMacで開発・検証操作を行わない。既存の作業用コピーの消去なども勝手に実行しない。

## 達成するべき目的

マウスをiPadに接続し、iPadでの操作からiPhoneへ操作対象を切り替え、iPhoneの実際の画面をマウスで操作する。画面端による滑らかな切り替えが理想。受信アプリ内のカーソル表示や文字送信だけを、OS全体を操作できるUniversal Controlの代替として完成扱いしない。

## 調査結果

| 項目 | 公開資料から確認できたこと | この依頼に対する扱い |
| --- | --- | --- |
| Apple純正Universal Control | Macを1台必要とし、対象はMacとiPad。[1] | 採用不可。iPhone対応を勝手に推測しない。 |
| 端末間通信 | Network.frameworkはBonjour/TLSを使った端末間通信を提供し、includePeerToPeerでP2Pリンクを有効にできる。[2][3] | Mac不要の通信基盤の候補。実機・ルーターなしの接続は未検証。 |
| マウス入力の取得 | GCMouseは接続した物理マウスの入力をアプリで受け取る。[4] | 自作アプリが前面にある間の入力取得の候補。全アプリの入力監視を意味しない。 |
| ポインターロック | UIViewControllerで特定のscene内のポインターロックを要求できる。[5] | アプリ内の動作。OS全体の画面端検出や別端末へのOSカーソル移動の権限ではない。 |
| 他アプリ・OSへの操作 | iOS/iPadOSのアプリはsandbox化され、他アプリやOSへアクセスするには明示的なシステムサービスが必要。[6] | 任意の他アプリへマウス・タッチを注入する公開APIは今回確認できていない。最大の未解決点。 |
| FaceTimeの遠隔操作 | Apple純正の1対1通話中に、許可されたiPhone/iPadの画面を操作する機能がある。[7] | 純正機能としての別方式。自作アプリに同じ権限がある証拠ではない。同一利用者の2端末・マウス操作・通話成立条件は未検証。 |
| Switch Control | 同一Apple Account・同一Wi-Fiで別端末へ操作対象を切り替えられる。[8] | 通常のマウスの自由移動や自動画面端切替と同一視しない。接続環境と入力装置の適合確認が必要。 |

### 現時点の判断

通信やポインターの描画だけを作っても、iPhoneのホーム画面や他アプリを操作できるようにはならない。Appleの公開資料で確認できた範囲では、通常の自作アプリだけで要求を満たす実装方法は確認できていない。

これは「iPhoneの遠隔操作がどんな方式でも不可能」という主張ではない。FaceTime等の純正機能は存在する。一方、それを自作アプリから任意のタイミングで制御できること、1つのマウスで両端のOS全体を連続操作できることは、別に立証する必要がある。

## 採用しない代替

- Mac常駐アプリやPC上の自動操作を隠れた依存にする。
- ハードウェアHID変換器を追加する。
- 文字入力専用キーボード拡張を今回のマウス共有の完成品とする。
- アプリ内カーソル、共有ノート、専用ブラウザーのデモを全アプリ操作の実現と表記する。
- 画面共有だけでクリック先のアプリを操作できると誤認させる。
- OSの私的API、脱獄や脆弱性を前提に、通常端末で動作すると表記する。

## 次の実装へ進むための検証ゲート

1. **受信側操作権限**：要求するiPhone/iPad OSで使用できる、許可されたシステム全体の入力経路を特定する。API名・権限・利用条件・Appleの一次資料を記録する。存在を仮定しない。
2. **追加機器なし**：Mac/PC/中継装置を停止した状態、外部ルーターに接続していない状態でも端末間接続を確認する。接続成立の実測を残す。
3. **実際の目的**：iPadに接続したマウスから、iPhoneのホーム・設定・任意の対応アプリへのクリック/スクロールを確認する。アプリ内の擬似操作を代用しない。
4. **送信側の範囲**：iPadで別アプリを利用している状態のマウス入力を取得できるか確認する。前面アプリ限定とOS全体対応を区別する。
5. **停止と同意**：受信側の明示許可、見える接続表示、即時停止、ロック/切断時の入力停止を確認する。

これらが成立する前に「完成」「全アプリ対応」「純正同等」と表示しない。専用アプリ内だけのモードは、ユーザーがその制限付きの範囲を選んだ場合に限り別機能として設計する。

## 現在のリポジトリとの関係

ベースコミット：26c5b2e472219a798a0827edfd5a5ff72ede1b0c。

既存READMEの「ユニバーサルコントロール相当」「Sidecar相当」等はプロトタイプの目標であり、要求達成や実機動作の証明ではない。追加指示前に実行した既存3件のシリアライズテストの成功も、今回の機器構成・入力共有・OS全体制御を検証するものではない。

この変更は文書のみ。既存アプリのソース、mainブランチ、ユーザーの端末設定を変更しない。新しいアプリのビルド、署名、iPad/iPhoneへの導入、実機通信テストは行っていない。

## 一次資料

[1] Apple, Universal Control: Use a single keyboard and mouse between Mac and iPad
https://support.apple.com/102459

[2] Apple Developer, Building a custom peer-to-peer protocol
https://developer.apple.com/documentation/network/building-a-custom-peer-to-peer-protocol

[3] Apple Developer, NWParameters.includePeerToPeer
https://developer.apple.com/documentation/network/nwparameters/includepeertopeer

[4] Apple Developer, GCMouse
https://developer.apple.com/documentation/gamecontroller/gcmouse

[5] Apple Developer, setNeedsUpdateOfPrefersPointerLocked
https://developer.apple.com/documentation/uikit/uiviewcontroller/setneedsupdateofpreferspointerlocked()

[6] Apple Platform Security, Security of runtime process in iOS, iPadOS and visionOS
https://support.apple.com/guide/security/sec15bfe098e/web

[7] Apple, Request or give remote control in a FaceTime call on iPad
https://support.apple.com/guide/ipad/ipada92df253/ipados

[8] Apple, Control several devices with one switch on iPad
https://support.apple.com/guide/ipad/ipad19840e9f/ipados
