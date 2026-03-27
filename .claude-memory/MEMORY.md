# Memory Index — nobu's Life OS

## Owner
nobu（POST CABINETS代表 / 大阪府議会議員1期目・岸和田市選挙区 / アドネス大阪 / 父親）
詳細プロフィール・ミッション・Claudeへの期待 → [user_nobu.md](./user_nobu.md)

## Notion = Single Source of Truth
全てのタスク・目標・日記・振り返りはNotionで管理。Claude CodeはNotionを読み書きして運用を支援する。
詳細ルール → [notion-context.md](./notion-context.md)

## 5つの軸（人生の柱）
1. **POSTCABINETS** — Webマーケティング支援（年商2億/純利1億目標）
2. **アドネス大阪** — 年商6億目標、完全自律運営
3. **政治家** — SNS発信・実証プロジェクト・地域活動
4. **家族** — 旅行・対話・イベント参加
5. **成長** — 筋トレ・英語・読書・コンテンツ発信

## 主要Notion DB一覧 → [notion-context.md](./notion-context.md)

## ワークフロー
- 会話開始時: Notionの今週タスク・今月目標を確認
- 作業完了時: Notionのステータスを更新
- 週末: 振り返り → Strategic Diary記録 → 翌週タスク設計

## カスタムコマンド
- `/design` — プロレベルデザイン生成 (LP/名刺/SNS/スライド/ブランド) → [design-skill.md](./design-skill.md)

## COPAIN インフラ構成（設定済み）
Notion/Discord/launchd/hooksの設定内容 → [copain-infra.md](./copain-infra.md)

## AI組織 × Notionループ（中核インフラ）
Claude Code Agent Teamsによるタスク自動実行の仕組みと実装状況 → [project_ai_org.md](./project_ai_org.md)

## 業務自動化研修プログラム（Active）
社内実力養成 → 実案件 → 事例資産化 → 研修商品化の学習ループ → [project_automation_training.md](./project_automation_training.md)

## フィードバック
- [日数見積もり禁止](./feedback_no_day_estimates.md) — トークン消費量・セッション数で規模感を示す。日数/時間の見積もりは出さない

## プロジェクト: macOSスクリーンレコーダー
- [screen-recorder-project.md](./screen-recorder-project.md) — ScreenSage Pro級のmacOSネイティブ録画アプリ開発

## プロジェクト: VoiceTyping（Active）
- [project_voicetyping.md](./project_voicetyping.md) — 無料音声入力アプリ（iOS/Android/Mac）。Task 1から実装開始

## プロジェクト: リモートアクセス（構築済み・残タスクあり）
- [project_remote_access.md](./project_remote_access.md) — スマホからTailscale+ttyd+PWAでClaude Codeにアクセス。launchd常駐稼働中
