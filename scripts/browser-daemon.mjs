#!/usr/bin/env node
/**
 * Playwright（Chromium）をヘッドレスで起動し、バックグラウンドで常駐する。
 * 設定: browser/browser-runner.config.json
 *
 *   npm run browser:daemon
 *
 * 終了: Ctrl+C または SIGTERM
 */
import { chromium } from "playwright";
import { readFileSync, existsSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = resolve(__dirname, "..");
const configPath = resolve(root, "browser/browser-runner.config.json");

if (!existsSync(configPath)) {
  console.error("設定が見つかりません:", configPath);
  process.exit(1);
}

const config = JSON.parse(readFileSync(configPath, "utf8"));
const headless = config.headless !== false;
const startUrl = config.startUrl || "about:blank";
const viewport = config.viewport || { width: 1280, height: 720 };

console.log("[browser-daemon] 起動中… headless=", headless, "url=", startUrl);

const launchOpts = {
  headless,
  args: ["--disable-blink-features=AutomationControlled"],
};

if (config.slowMoMs > 0) {
  launchOpts.slowMo = config.slowMoMs;
}

/** launch より前に登録しないと、起動中の SIGTERM で子プロセスが不整合になる */
let browser;

async function shutdown() {
  console.log("[browser-daemon] 終了処理…");
  try {
    if (browser) await browser.close();
  } catch (_) {}
  process.exit(0);
}

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);

browser = await chromium.launch(launchOpts);

const contextOpts = { viewport };
if (config.userAgent) {
  contextOpts.userAgent = config.userAgent;
}

const context = await browser.newContext(contextOpts);
const page = await context.newPage();

try {
  await page.goto(startUrl, { waitUntil: "domcontentloaded", timeout: 120000 });
  console.log("[browser-daemon] 初期ページを読み込みました。");
} catch (e) {
  console.error("[browser-daemon] 初回ナビゲーション失敗（オフライン等）:", e.message);
}

if (config.keepAlive && config.pingIntervalMs > 0 && config.pingUrl) {
  setInterval(async () => {
    try {
      await page.goto(config.pingUrl, { waitUntil: "domcontentloaded", timeout: 60000 });
      console.log("[browser-daemon] ping OK", new Date().toISOString());
    } catch (e) {
      console.error("[browser-daemon] ping 失敗:", e.message);
    }
  }, config.pingIntervalMs);
}

if (config.keepAlive) {
  console.log("[browser-daemon] 常駐中（終了は Ctrl+C）。PID=", process.pid);
  await new Promise(() => {});
} else {
  await browser.close();
  console.log("[browser-daemon] keepAlive=false のため終了しました。");
}
