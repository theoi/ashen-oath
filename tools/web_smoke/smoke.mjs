// Loads a web build in headless Chrome, waits for the game's ready marker in the console
// and saves a screenshot.
//
//   node smoke.mjs <url | build-dir> <screenshot.png> [--marker=ASHEN_OATH_READY] [--timeout=180000] [--settle=3000]
//
// A build directory is served locally without COOP/COEP headers, like GitHub Pages.
// Uses the system Chrome (CHROME env var, default /usr/bin/google-chrome) via playwright-core.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { chromium } from 'playwright-core';

const positional = process.argv.slice(2).filter((a) => !a.startsWith('--'));
const flags = Object.fromEntries(process.argv.slice(2).filter((a) => a.startsWith('--'))
  .map((a) => a.slice(2).split('=')));
const [target, shot] = positional;
if (!target || !shot) {
  console.error('usage: node smoke.mjs <url | build-dir> <screenshot.png> [--marker=..] [--timeout=ms] [--settle=ms]');
  process.exit(2);
}
const marker = flags.marker ?? 'ASHEN_OATH_READY';
const timeout = Number(flags.timeout ?? 180000);
const settle = Number(flags.settle ?? 3000);

let server;
let url = target;
if (!/^https?:\/\//.test(target)) {
  const types = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.png': 'image/png' };
  server = http.createServer((req, res) => {
    let p = path.join(target, decodeURIComponent(req.url.split('?')[0]));
    if (p.endsWith(path.sep) || p.endsWith('/')) p = path.join(p, 'index.html');
    fs.readFile(p, (err, data) => {
      if (err) { res.writeHead(404); res.end(); return; }
      res.writeHead(200, { 'Content-Type': types[path.extname(p)] ?? 'application/octet-stream' });
      res.end(data);
    });
  }).listen(0, '127.0.0.1');
  await new Promise((r) => server.on('listening', r));
  url = `http://127.0.0.1:${server.address().port}/`;
}

const browser = await chromium.launch({
  executablePath: process.env.CHROME ?? '/usr/bin/google-chrome',
  headless: true,
  args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'],
});
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
const logs = [];
let markerLine = null;
let resolveMarker;
const markerSeen = new Promise((r) => { resolveMarker = r; });
page.on('console', (m) => {
  const line = `[${m.type()}] ${m.text()}`;
  logs.push(line);
  if (m.text().includes(marker)) { markerLine = m.text(); resolveMarker(); }
});
page.on('pageerror', (e) => logs.push(`[pageerror] ${e.message}`));

const t0 = Date.now();
let ok = false;
try {
  await page.goto(url, { timeout });
  await Promise.race([markerSeen, page.waitForTimeout(timeout)]);
  ok = markerLine !== null;
  await page.waitForTimeout(settle);
} catch (e) {
  logs.push(`[smoke] ${e.message}`);
}
fs.mkdirSync(path.dirname(path.resolve(shot)), { recursive: true });
await page.screenshot({ path: shot });
const renderer = logs.find((l) => /Compatibility|WebGL/.test(l)) ?? null;
console.log(JSON.stringify({ url, ok, markerLine, renderer, elapsedMs: Date.now() - t0, screenshot: shot }, null, 1));
if (!ok) console.log(logs.slice(-40).join('\n'));
await browser.close();
server?.close();
process.exit(ok ? 0 : 1);
