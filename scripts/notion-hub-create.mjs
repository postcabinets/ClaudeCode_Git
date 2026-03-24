#!/usr/bin/env node
import { writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { loadDotEnv, projectRoot } from "./lib/env.mjs";
import { normalizeNotionId, notionHeaders } from "./lib/notion.mjs";

const root = projectRoot();
loadDotEnv(root);

const token = process.env.NOTION_TOKEN;
const parentId = normalizeNotionId(process.env.NOTION_PARENT_PAGE_ID ?? "");

if (!token || !parentId) {
  console.error("NOTION_TOKEN と NOTION_PARENT_PAGE_ID が必要です（.env 参照）。");
  process.exit(1);
}

const headers = notionHeaders(token);

const select = (options) => ({
  select: {
    options: options.map((name) => ({ name })),
  },
});

const schemas = [
  [
    "COPAIN — Projects",
    "projects",
    {
      Name: { title: {} },
      Status: select(["Idea", "Active", "Blocked", "Done"]),
      Phase: select(["Discovery", "MVP", "Beta", "GA"]),
      Priority: { number: { format: "number" } },
      "Next action": { rich_text: {} },
      "LINE/OpenClaw": { checkbox: {} },
      Updated: { date: {} },
      URL: { url: {} },
    },
  ],
  [
    "COPAIN — Decisions",
    "decisions",
    {
      Title: { title: {} },
      Date: { date: {} },
      Status: select(["Proposed", "Accepted", "Superseded"]),
      Context: { rich_text: {} },
    },
  ],
  [
    "COPAIN — Weekly",
    "weekly",
    {
      Week: { title: {} },
      Focus: { rich_text: {} },
      "Top 3": { rich_text: {} },
      Blockers: { rich_text: {} },
    },
  ],
  [
    "COPAIN — Risks",
    "risks",
    {
      Title: { title: {} },
      Severity: select(["Low", "Medium", "High"]),
      Area: select(["Legal", "Product", "Tech", "Ops", "Finance"]),
      Mitigation: { rich_text: {} },
    },
  ],
  [
    "COPAIN — Triggers",
    "triggers",
    {
      Name: { title: {} },
      Type: select(["cron", "webhook", "manual", "discord"]),
      Cadence: { rich_text: {} },
      "Last run": { date: {} },
      Notes: { rich_text: {} },
    },
  ],
];

async function createDatabase(title, properties) {
  const res = await fetch("https://api.notion.com/v1/databases", {
    method: "POST",
    headers,
    body: JSON.stringify({
      parent: { type: "page_id", page_id: parentId },
      title: [{ type: "text", text: { content: title } }],
      properties,
    }),
  });
  const data = await res.json();
  if (!res.ok) {
    throw new Error(`${title}: ${res.status} ${JSON.stringify(data)}`);
  }
  return data;
}

const hub = {
  version: 1,
  createdAt: new Date().toISOString(),
  parentPageId: parentId,
  databases: {},
};

console.log("親ページに DB を作成します…");
for (const [title, key, props] of schemas) {
  const db = await createDatabase(title, props);
  hub.databases[key] = {
    id: db.id,
    url: db.url ?? null,
    title,
  };
  console.log("作成:", title, "→", db.url ?? db.id);
}

const hubPath = resolve(root, ".notion-hub.json");
writeFileSync(hubPath, JSON.stringify(hub, null, 2), "utf8");
console.log("ハブ定義を保存:", hubPath);
console.log("完了。Notion で親ページを開いて確認してください。");
