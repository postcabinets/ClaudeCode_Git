#!/usr/bin/env node
/**
 * Projects DB の Status=Active を取得し、Discord Webhook に要約投稿。
 * 要環境変数: NOTION_TOKEN, NOTION_HUB または .notion-hub.json, DISCORD_WEBHOOK_URL
 */
import { readFileSync, existsSync } from "node:fs";
import { resolve } from "node:path";
import { loadDotEnv, projectRoot } from "./lib/env.mjs";
import { notionHeaders } from "./lib/notion.mjs";

const root = projectRoot();
loadDotEnv(root);

const token = process.env.NOTION_TOKEN;
const webhook = process.env.DISCORD_WEBHOOK_URL;
const hubPath = resolve(root, ".notion-hub.json");

if (!token) {
  console.error("NOTION_TOKEN が未設定です。");
  process.exit(1);
}
if (!webhook) {
  console.error("DISCORD_WEBHOOK_URL が未設定です。Discord サーバーで Webhook を作成し .env に追加してください。");
  process.exit(1);
}
if (!existsSync(hubPath)) {
  console.error(".notion-hub.json がありません。notion-hub-create を先に実行してください。");
  process.exit(1);
}

const hub = JSON.parse(readFileSync(hubPath, "utf8"));
const projectsId = hub.databases?.projects?.id;
if (!projectsId) {
  console.error("projects データベース ID がありません。");
  process.exit(1);
}

const headers = notionHeaders(token);

const res = await fetch(`https://api.notion.com/v1/databases/${projectsId}/query`, {
  method: "POST",
  headers,
  body: JSON.stringify({
    filter: {
      property: "Status",
      select: { equals: "Active" },
    },
    page_size: 20,
  }),
});

const data = await res.json();
if (!res.ok) {
  console.error("Notion query 失敗:", res.status, data);
  process.exit(1);
}

const lines = ["**COPAIN — Active Projects**", ""];
for (const page of data.results ?? []) {
  const p = page.properties;
  const name = p?.Name?.title?.map((t) => t.plain_text).join("") ?? "(無題)";
  const next = p?.["Next action"]?.rich_text?.map((t) => t.plain_text).join("") ?? "";
  const url = p?.URL?.url ?? "";
  lines.push(`• **${name}**`);
  if (next) lines.push(`  Next: ${next}`);
  if (url) lines.push(`  ${url}`);
  lines.push("");
}

if (lines.length <= 2) {
  lines.push("_Active な行はありません。Notion の Projects を更新してください。_");
}

let content = lines.join("\n");
if (content.length > 1900) {
  content = content.slice(0, 1900) + "\n…(truncated)";
}

const wh = await fetch(webhook, {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ content }),
});

if (!wh.ok) {
  const t = await wh.text();
  console.error("Discord 投稿失敗:", wh.status, t);
  process.exit(1);
}

console.log("OK: Discord に Active Projects を投稿しました。");
