#!/usr/bin/env node
// remote-app/server.mjs — PWAランチャー配信サーバー
// Tailscale IP にのみバインド（セキュリティ）

import { createServer } from 'http';
import { readFile } from 'fs/promises';
import { join, extname } from 'path';
import { execFileSync } from 'child_process';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const PORT = 7680; // ttyd(7681)の隣

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.json': 'application/json',
  '.png':  'image/png',
  '.svg':  'image/svg+xml',
  '.js':   'application/javascript',
  '.css':  'text/css',
};

// Tailscale IP取得（execFileSyncでシェルインジェクション防止）
let host = '0.0.0.0';
try {
  host = execFileSync('tailscale', ['ip', '-4'], { encoding: 'utf8' }).trim();
} catch {
  console.warn('Tailscale not available, binding to 0.0.0.0');
}

const server = createServer(async (req, res) => {
  let filePath = req.url === '/' ? '/index.html' : req.url;
  // パストラバーサル防止
  filePath = filePath.split('?')[0].replace(/\.\./g, '');
  const fullPath = join(__dirname, filePath);
  const ext = extname(fullPath);

  try {
    const data = await readFile(fullPath);
    res.writeHead(200, {
      'Content-Type': MIME[ext] || 'application/octet-stream',
      'Cache-Control': ext === '.html' ? 'no-cache' : 'max-age=86400',
    });
    res.end(data);
  } catch {
    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('Not found');
  }
});

server.listen(PORT, host, () => {
  console.log(`Launcher running at http://${host}:${PORT}`);
  console.log('Open this URL on your phone (via Tailscale)');
});
