/**
 * Render the static Today-page comps through the already-running headless
 * Chromium (CDP on 127.0.0.1:9333) and save PNGs next to ../screens.
 *
 * This only screenshots design/ui-hierarchy/index.html; it never touches the
 * Flutter app.
 */
import { writeFile, mkdir } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const designDir = resolve(here, '..');
const htmlUrl = pathToFileURL(resolve(designDir, 'index.html')).href;
const outDir = resolve(designDir, 'screens');
const cdpBase = 'http://127.0.0.1:9333';

const version = await (await fetch(`${cdpBase}/json/version`)).json();
const ws = new WebSocket(version.webSocketDebuggerUrl);
await new Promise((resolve, reject) => {
  ws.onopen = resolve;
  ws.onerror = () => reject(new Error('CDP websocket failed to open'));
});

let nextId = 1;
const pending = new Map();
ws.addEventListener('message', (event) => {
  const message = JSON.parse(event.data);
  if (message.id && pending.has(message.id)) {
    const { resolve, reject } = pending.get(message.id);
    pending.delete(message.id);
    if (message.error) reject(new Error(`${message.error.message} (${message.error.code})`));
    else resolve(message.result);
  }
});

function send(method, params = {}, sessionId) {
  return new Promise((resolve, reject) => {
    const id = nextId++;
    pending.set(id, { resolve, reject });
    ws.send(JSON.stringify({ id, method, params, ...(sessionId ? { sessionId } : {}) }));
  });
}

const variants = [
  ['base', 'light', 'today-base-light.png'],
  ['a', 'light', 'today-a-depth-light.png'],
  ['b', 'light', 'today-b-balanced-light.png'],
  ['c', 'light', 'today-c-brand-light.png'],
  ['b', 'dark', 'today-b-balanced-dark.png'],
];

await mkdir(outDir, { recursive: true });

for (const [variant, theme, name] of variants) {
  const { targetId } = await send('Target.createTarget', { url: 'about:blank' });
  const { sessionId } = await send('Target.attachToTarget', { targetId, flatten: true });
  const session = (method, params) => send(method, params ?? {}, sessionId);

  await session('Page.enable');
  await session('Runtime.enable');
  await session('Emulation.setDeviceMetricsOverride', {
    width: 1366,
    height: 780,
    deviceScaleFactor: 1,
    mobile: false,
    screenWidth: 1366,
    screenHeight: 780,
  });
  await session('Page.navigate', { url: `${htmlUrl}?v=${variant}&theme=${theme}` });

  const deadline = Date.now() + 15_000;
  while (Date.now() < deadline) {
    const ready = await session('Runtime.evaluate', {
      expression: "document.readyState === 'complete' && !!document.body.dataset.variant",
      returnByValue: true,
    });
    if (ready.result?.value) break;
    await new Promise((resolve) => setTimeout(resolve, 120));
  }
  await new Promise((resolve) => setTimeout(resolve, 350));

  const shot = await session('Page.captureScreenshot', { format: 'png', fromSurface: true });
  await writeFile(resolve(outDir, name), Buffer.from(shot.data, 'base64'));
  console.log(`saved ${name}`);

  await send('Target.closeTarget', { targetId });
}

ws.close();
console.log('done');
