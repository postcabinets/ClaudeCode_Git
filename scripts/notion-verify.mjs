#!/usr/bin/env node
import { loadDotEnv, projectRoot } from "./lib/env.mjs";

const root = projectRoot();
loadDotEnv(root);

const token = process.env.NOTION_TOKEN;
if (!token) {
  console.error("NOTION_TOKEN が未設定です。.env に追加するか export してください。");
  process.exit(1);
}

const res = await fetch("https://api.notion.com/v1/search", {
  method: "POST",
  headers: {
    Authorization: `Bearer ${token}`,
    "Notion-Version": "2022-06-28",
    "Content-Type": "application/json",
  },
  body: JSON.stringify({ page_size: 5 }),
});

const body = await res.json();
if (!res.ok) {
  console.error("Notion API エラー:", res.status, body);
  process.exit(1);
}

console.log("OK: Notion インテグレーションは応答しています。");
console.log("直近のページ/DB 件数:", body.results?.length ?? 0);
if (body.results?.length) {
  for (const r of body.results) {
    const title =
      r.properties?.title?.title?.[0]?.plain_text ??
      r.properties?.Name?.title?.[0]?.plain_text ??
      "(無題)";
    console.log("-", r.object, r.id, title);
  }
}
