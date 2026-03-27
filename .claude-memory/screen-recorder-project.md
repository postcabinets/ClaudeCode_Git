---
name: macOSスクリーンレコーダー開発プロジェクト
description: ScreenSage Pro級のmacOSネイティブスクリーンレコーダー。Swift/SwiftUI、6フェーズで段階的実装。
type: project
---

macOS専用のプロ向けスクリーンレコーダーを開発中。ScreenSage Proと同等機能を目指す。

**Why:** nobuが自分で使うツールとして開発。将来的にプロダクト化も視野。

**How to apply:** Phase 1（MVP）から順に実装。各セッションで前回の到達点を確認してから続きを実装する。

## 技術スタック
- Swift 5.9+ / SwiftUI / macOS 14+
- ScreenCaptureKit / AVFoundation / AVAudioEngine
- Vision / Speech framework / Core Animation / SceneKit

## フェーズ
1. MVP: 画面録画→MP4保存（ScreenCaptureKit + AVAssetWriter + 最小UI）
2. カメラ + PiP（AVCaptureSession + 合成）
3. スマートズーム + カーソルエフェクト + キーストローク（CGEvent tap）
4. AI機能（背景除去・字幕・プライバシーマスク）
5. 編集（タイムライン・カット・速度・BGM）
6. 3D + シネマ + DMGパッケージ

## 保存場所
`ScreenRecorder/` （このリポジトリ直下）

## 現在の進捗（2026-03-27）
- Phase 1 コード作成済み（App.swift, ContentView.swift, ScreenCaptureManager.swift, VideoWriter.swift, xcodeproj）
- Xcodeライセンス同意済み
- **次のステップ**: xcodebuildでビルドを通す → ビルドエラー修正 → 録画テスト → Phase 2へ
