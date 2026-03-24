#!/usr/bin/env node
import { loadDotEnv, projectRoot } from "./lib/env.mjs";

loadDotEnv(projectRoot());

const url = process.env.DISCORD_WEBHOOK_URL;
const content = process.argv.slice(2).join(" ") || "テスト通知（COPAIN / Claude Code）";

if (!url) {
  console.error("DISCORD_WEBHOOK_URL が未設定です。サーバー設定で Webhook を作成し .env に追加してください。");
  process.exit(1);
}

const res = await fetch(url, {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ content }),
});

if (!res.ok) {
  const t = await res.text();
  console.error("失敗:", res.status, t);
  process.exit(1);
}

console.log("OK: Discord に投稿しました。");
