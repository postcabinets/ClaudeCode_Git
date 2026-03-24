#!/usr/bin/env node
/**
 * .notion-hub.json に基づき、初期行を投入（既に Projects に行があればスキップ）。
 * 強制実行: NOTION_SEED_FORCE=1
 */
import { readFileSync, existsSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { loadDotEnv, projectRoot } from "./lib/env.mjs";
import { notionHeaders } from "./lib/notion.mjs";

const root = projectRoot();
loadDotEnv(root);

const hubPath = resolve(root, ".notion-hub.json");
if (!existsSync(hubPath)) {
  console.error("先に scripts/notion-hub-create.mjs を実行して .notion-hub.json を生成してください。");
  process.exit(1);
}

const token = process.env.NOTION_TOKEN;
if (!token) {
  console.error("NOTION_TOKEN が未設定です。");
  process.exit(1);
}

const hub = JSON.parse(readFileSync(hubPath, "utf8"));
const projectsId = hub.databases?.projects?.id;
const decisionsId = hub.databases?.decisions?.id;
const weeklyId = hub.databases?.weekly?.id;
const triggersId = hub.databases?.triggers?.id;

if (!projectsId || !decisionsId) {
  console.error(".notion-hub.json に projects / decisions ID がありません。");
  process.exit(1);
}

const headers = notionHeaders(token);

const rt = (s) => ({ rich_text: [{ type: "text", text: { content: s } }] });
const title = (s) => ({ title: [{ type: "text", text: { content: s } }] });
const today = new Date().toISOString().slice(0, 10);

async function hasAnyRow(databaseId) {
  const res = await fetch(`https://api.notion.com/v1/databases/${databaseId}/query`, {
    method: "POST",
    headers,
    body: JSON.stringify({ page_size: 1 }),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(JSON.stringify(data));
  return (data.results?.length ?? 0) > 0;
}

async function createPage(databaseId, properties) {
  const res = await fetch("https://api.notion.com/v1/pages", {
    method: "POST",
    headers,
    body: JSON.stringify({
      parent: { database_id: databaseId },
      properties,
    }),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(JSON.stringify(data));
  return data;
}

const force = process.env.NOTION_SEED_FORCE === "1";
if (!force && (await hasAnyRow(projectsId))) {
  console.log("Projects に既に行があります。上書きする場合は NOTION_SEED_FORCE=1 を付けて再実行。");
  process.exit(0);
}

console.log("シードを投入します…");

await createPage(projectsId, {
  Name: title("COPAIN MVP"),
  Status: { select: { name: "Active" } },
  Phase: { select: { name: "Discovery" } },
  Priority: { number: 1 },
  "Next action": rt("LINE 公式アカウント方針を Decisions に 1 件書く。notion-pulse で週次確認。"),
  "LINE/OpenClaw": { checkbox: true },
  Updated: { date: { start: today } },
});

await createPage(decisionsId, {
  Title: title("データハブは Notion、通知は Discord Webhook"),
  Date: { date: { start: today } },
  Status: { select: { name: "Accepted" } },
  Context: rt("CLAUDE.md と .notion-hub.json を正とする。リポジトリにシークレットを置かない。"),
});

await createPage(decisionsId, {
  Title: title("技術スパイク優先: LINE → バックエンド → モデル"),
  Date: { date: { start: today } },
  Status: { select: { name: "Proposed" } },
  Context: rt("OpenClaw 全導入は並行検証。課金・規約は人が決定。"),
});

if (weeklyId) {
  await createPage(weeklyId, {
    Week: title(`Week ${today}`),
    Focus: rt("COPAIN の MVP 範囲を 1 段落で固定する"),
    "Top 3": rt("1) Notion ハブ運用 2) LINE 接続スパイク 3) 課金仮説の Decisions 化"),
    Blockers: rt("未記入なら「なし」"),
  });
}

if (triggersId) {
  await createPage(triggersId, {
    Name: title("notion-pulse（Active プロジェクト要約 → Discord）"),
    Type: { select: { name: "cron" } },
    Cadence: rt("毎日 9:00 目安 — launchd の例は scripts/launchd/"),
    Notes: rt("npm run pulse:discord"),
  });
}

hub.seededAt = new Date().toISOString();
writeFileSync(hubPath, JSON.stringify(hub, null, 2), "utf8");
console.log("シード完了。.notion-hub.json を更新しました。");
