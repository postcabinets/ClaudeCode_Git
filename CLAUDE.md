# COPAIN AI / プロジェクト運用（Claude Code 向け）

## 単一の真実（Single Source of Truth）

- **計画・決定・タスク・リスク・顧客メモの正本は Notion**（このリポジトリ内のメモは一時的な下書きにしない。更新は Notion を先に更新する）。
- 作業前に Notion の **Projects / Decisions / Weekly** を確認し、終わったら同じページまたは DB に結果を追記する。
- シークレット（Notion token、Discord Bot token、Webhook、API キー）は **`.env` にのみ**置き、**絶対にコミットしない**。

## セキュリティ（必須）

- **Discord Bot トークンは一度でも外部に出したら Developer Portal で再発行**する。過去にチャット等へ貼った場合は無効化済みとみなす。
- 公開キー（Public Key）もサービス側で使う秘密に近い情報として取り扱う。
- 本リポジトリにトークンを書かない。`.env.example` はプレースホルダのみ。

## 事業の北極星

1. **第 1 事業**: COPAIN AI（AI アシスタント）を「完成」に近づける。
2. **提供形態の仮説**: 公式 LINE に接続し、ユーザーが育てながら自動化が進む体験。課金はクレジット課金またはサブスク（決済・規約は別途確定）。
3. **技術スタックの仮説**: OpenClaw 相当の Gateway をそのまま使うか、簡易版にするかは未確定。**簡易版**に倒す場合は「LINE → あなたのバックエンド → モデル」で十分な範囲から切る。

## 意思決定の境界

- **あなた（人）がやること**: 価格、契約、公開コピー、個人情報の扱い、自動送信の可否、新規事業の Go/No-Go。
- **エージェント／自動化がやってよいこと**: 調査、下書き、リポジトリ内の実装、Notion 更新案の提示、Discord への進捗通知（Webhook 経由など）。

## Notion ハブの使い方

- 親ページの下に次の DB がある想定（`scripts/notion-hub-create.mjs` で作成可能）:
  - **Projects**: COPAIN / LINE / 課金 / OpenClaw 検証 などのイシュー単位。
  - **Decisions**: 決定事項と理由・日付。
  - **Weekly**: 週のフォーカスとトップ 3 の成果。
  - **Risks**: 法務・技術・運用リスク。
  - **Triggers**: 定期確認や「次にやること」のトリガー定義（Discord 通知と紐づけ可能）。

## Discord の役割

- **通知チャネル**: スクリプトまたは CI から **Webhook** で進捗・ブロッカーを投稿する（実装は `.env` の `DISCORD_WEBHOOK_URL`）。
- **対話が必要なら** Bot（トークンは `.env` のみ）。Slash コマンドや常時接続は後回しでよい。

## npm スクリプト（ルートで実行）

前提: Node 20+、`.env` に `NOTION_TOKEN` / `NOTION_PARENT_PAGE_ID`（および Discord 通知なら `DISCORD_WEBHOOK_URL`）。

| コマンド | 内容 |
|----------|------|
| `npm run notion:verify` | Notion インテグレーション疎通 |
| `npm run notion:hub` | 親ページ直下に 5 DB 作成 + `.notion-hub.json` に ID 保存 |
| `npm run notion:seed` | Projects / Decisions 等に初期行（既に行がある場合はスキップ。上書きは `NOTION_SEED_FORCE=1`） |
| `npm run pulse:discord` | Projects の **Active** を Discord Webhook に投稿 |
| `npm run discord:test` | Webhook テスト投稿 |
| `npm run bootstrap` | verify → hub → seed → discord:test を連続実行 |

定期トリガー: `scripts/launchd/com.copain.notion-pulse.plist.example` をコピーし、パスを自分の環境に合わせて `launchctl load` する。

## 次にやること（常にこの順で迷わない）

1. **Notion**: 親ページを 1 つ作り、インテグレーションに共有する。`.env` に `NOTION_TOKEN` と `NOTION_PARENT_PAGE_ID` を設定する。
2. **スクリプト**: `npm run notion:verify` → `npm run notion:hub` → `npm run notion:seed`。
3. **Discord**: Webhook URL を `.env` の `DISCORD_WEBHOOK_URL` に設定し、`npm run discord:test`。Bot トークンは対話 Bot を作る段階まで `.env` のみで管理（漏洩時は再発行）。
4. **運用**: 迷ったら `npm run pulse:discord` で Active プロジェクトを Discord に流す。
5. **技術スパイク**: 「LINE Messaging API + 最小バックエンド + モデル」の受信返信（OpenClaw 全導入は並行検証）。

## Claude Code に求める行動

- セッション開始時: Notion の Projects / Weekly を読む前提でユーザーに確認するか、ユーザーが貼った Notion リンクを優先する。
- セッション終了時: 変更があれば Notion 更新内容を箇条書きで提案する（ユーザーが貼りやすい形式）。
- 新しい「方針」はこの `CLAUDE.md` と Notion の Decisions の両方に矛盾がないようにする。
