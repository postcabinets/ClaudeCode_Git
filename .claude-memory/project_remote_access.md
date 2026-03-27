---
name: リモートアクセス環境（Claude Code Mobile）
description: スマホからTailscale+ttyd+PWAでClaude Codeにアクセスする環境。構築済み・launchd常駐。
type: project
---

## 目的
外出先のスマホから自宅Mac上のClaude Codeにアクセスし、セッション継続・新規起動ができるようにする。

## 構成（2026-03-27構築済み）

```
スマホ (Samsung Galaxy / Tailscale VPN)
  ↓ 暗号化P2P
自宅 Mac (100.90.64.60)
  ├── :7680 PWAランチャー (Node.js, launchd常駐)
  └── :7681 ttyd → tmux → Claude Code (launchd常駐)
```

## 稼働サービス
| サービス | ポート | launchd Label |
|---------|-------|---------------|
| PWAランチャー | 7680 | com.postcabinets.claude-launcher |
| ttyd (Webターミナル) | 7681 | com.postcabinets.ttyd-claude |

## ファイル構成
- `remote-app/index.html` — PWAランチャーUI
- `remote-app/manifest.json` — PWAマニフェスト
- `remote-app/server.mjs` — ランチャー配信サーバー
- `scripts/start-ttyd.sh` — ttyd起動（.envから認証情報読み込み）
- `scripts/ttyd-claude.sh` — tmuxセッション自動作成・接続
- `scripts/launchd/com.postcabinets.ttyd-claude.plist`
- `scripts/launchd/com.postcabinets.claude-launcher.plist`

## 認証
- `.env` の `TTYD_USER` / `TTYD_PASS` で管理
- Tailscale VPN経由のみアクセス可能

## npmコマンド
- `npm run ttyd:start` / `ttyd:stop` / `ttyd:status`
- `npm run remote:start` / `remote:status`

## 残タスク
1. `npm run remote:setup` 一発セットアップスクリプト（別Mac用）
2. PWA iframe内の自動コマンド実行改善
3. `.tmux.conf` のリポジトリ管理判断
4. パスワード変更ドキュメント

## Why
SSHだとセッションが消える、tmux/screenは面倒。スマホブラウザからワンタップでClaude Codeに繋がる体験が必要だった。

## How to apply
リモートアクセス関連の変更・拡張時にこのファイルを参照。残タスクから着手する。
