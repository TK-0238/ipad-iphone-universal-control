# iPadとiPhone連携操作アプリ

このリポジトリは、iPadとiPhoneの両方に同じアプリをインストールして使用することで、
1台のキーボード／ポインタ入力共有（ユニバーサルコントロール相当）と片方を外部ディスプレイとして扱う体験（Sidecar相当）を再現するためのプロトタイプです。

## 目的
- iPad・iPhone間で低遅延な双方向接続を確立する。
- ハードウェアキーボード／ポインタ入力を片方のデバイスからもう片方へ中継する。
- 片方の画面をもう片方にストリーミングし、外部ディスプレイ風に扱う。
- App Store Review Guidelineの範囲に収まる（脱獄・私的API禁止）。

## 全体アーキテクチャ
```
┌───────────┐   Wi‑Fi Direct / BLE / 本地LAN   ┌───────────┐
│ Controller端末 │◀──────── MultipeerConnectivity ──────▶│ Display端末 │
│ (iPad/iPhone)  │        + optional WebRTC DataChannel       │ (iPad/iPhone) │
└───────────┘                                             └───────────┘
        ▲ キーボード／ポインタ Capture                            │ ReplayKit Screen Capture
        │ InputBridgeService                                      │ DisplayBridgeService
        └────────────── SharedControlKit (共通ロジック) ────────────┘
```

- **SharedControlKit**: 端末役割に関わらず使う共有モジュール。暗号化済みセッション管理、入力イベントモデル、映像フレーム圧縮、QoS制御を提供。
- **Controllerフロー**: `InputCaptureView` が `UIKeyCommand` と `UIHoverGestureRecognizer` / `PointerInteraction` のイベントを検出し、`InputBridgeService` が差分送信。
- **Displayフロー**: `ReplayKit`（`RPScreenRecorder`）または `MetalCaptureView` で得たフレームを `VideoEncoder` 経由で `H.264/HEVC` に圧縮し、`DisplayBridgeService` が送出。受信側は `Metal` レンダラで描画し、`PointerProjectionLayer` でリモートカーソルを合成。

## 評価指標
1. 往復遅延 ≤ 80ms を目標としたキーボード入力到達時間
2. 60Hz ポインタ同期（カーソル位置差 ≤ 2px）
3. ReplayKit ストリーミング 15fps 以上／遅延 ≤ 200ms
4. 1時間連続利用で切断ゼロ
5. ガイドライン準拠（マルチデバイス制御・画面共有をアプリ内で完結）

## 実装予定モジュール
- `SharedControlKit`
  - `SessionCoordinator`: MultipeerConnectivity + NWConnection による暗号化チャンネル
  - `InputEvent`, `PointerEvent`, `DisplayFrame` モデル（CBORエンコード）
  - `FrameCompressor`: `VideoToolbox` での低遅延エンコード
  - `LatencyEstimator`: 双方向の生存確認とRTT計測
- `UniversalPadApp`（iOS/iPadOSアプリ）
  - 役割切替 UI（Controller / Display / Mirror）
  - `InputCaptureView`, `RemoteDisplayView`
  - `ReplayKitScreenSource`
  - 設定画面（エンコードビットレート、ポインタ感度など）

## 今後の流れ
1. プロジェクトの SwiftPM / Xcode ひな型を作成
2. SharedControlKit 基本実装とユニットテスト
3. iOS/iPadOS アプリの UI + サービス結線
4. 実機テストと計測ログ出力

