/** Notion API 共通 */

export const NOTION_VERSION = "2022-06-28";

export function notionHeaders(token) {
  return {
    Authorization: `Bearer ${token}`,
    "Notion-Version": NOTION_VERSION,
    "Content-Type": "application/json",
  };
}

export function normalizeNotionId(raw) {
  const s = raw?.trim();
  if (!s) return null;
  if (s.includes("-")) return s;
  if (/^[a-f0-9]{32}$/i.test(s)) {
    return `${s.slice(0, 8)}-${s.slice(8, 12)}-${s.slice(12, 16)}-${s.slice(16, 20)}-${s.slice(20)}`;
  }
  return s;
}

export async function notionFetch(path, token, init = {}) {
  const url = path.startsWith("http") ? path : `https://api.notion.com${path}`;
  const res = await fetch(url, {
    ...init,
    headers: { ...notionHeaders(token), ...init.headers },
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    const err = new Error(`Notion API ${res.status}: ${JSON.stringify(data)}`);
    err.status = res.status;
    err.body = data;
    throw err;
  }
  return data;
}
