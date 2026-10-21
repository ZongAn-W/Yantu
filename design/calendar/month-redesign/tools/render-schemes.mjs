import { chromium } from 'playwright';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const screens = path.join(root, 'screens');
fs.mkdirSync(screens, { recursive: true });

const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({
  viewport: { width: 1200, height: 1000 },
  deviceScaleFactor: 2,
  locale: 'zh-CN',
  timezoneId: 'Asia/Shanghai',
  reducedMotion: 'no-preference',
});
const page = await context.newPage();
const pageErrors = [];
page.on('pageerror', (error) => pageErrors.push(String(error)));
page.on('console', (message) => {
  if (message.type() === 'error') pageErrors.push(message.text());
});

await page.goto(pathToFileURL(path.join(root, 'index.html')).href, { waitUntil: 'networkidle' });
await page.evaluate(() => document.fonts.ready);
await page.waitForTimeout(250);

const schemes = [
  ['scheme-a', 'scheme-a-information-layering.png'],
  ['scheme-b', 'scheme-b-plan-actual-bar.png'],
  ['scheme-c', 'scheme-c-selected-day-summary.png'],
  ['scheme-d', 'scheme-d-plan-only.png'],
  ['scheme-e', 'scheme-e-plan-capacity-meter.png'],
  ['scheme-f', 'scheme-f-dot-calendar-bottom-agenda.png'],
  ['scheme-g', 'scheme-g-dot-calendar-side-panel.png'],
  ['scheme-h', 'scheme-h-round-day-grid.png'],
  ['scheme-i', 'scheme-i-soft-tile-grid.png'],
  ['scheme-j', 'scheme-j-big-date-course-bar.png'],
  ['scheme-k', 'scheme-k-course-mosaic-capacity.png'],
  ['scheme-l', 'scheme-l-course-mosaic-fullbleed.png'],
];

for (const [id, name] of schemes) {
  const section = page.locator(`#${id}`);
  await section.screenshot({ path: path.join(screens, name) });
  const metrics = await section.evaluate((el) => {
    const cells = [...el.querySelectorAll('.cell')];
    const box = el.getBoundingClientRect();
    return {
      width: Math.round(box.width),
      height: Math.round(box.height),
      cells: cells.length,
      dayCells: cells.filter((cell) => cell.dataset.date).length,
      clippedCells: cells.filter((cell) => cell.scrollWidth > cell.clientWidth + 1).length,
      overflowingText: [...el.querySelectorAll('.fact-plan,.fact-cap,.fact-actual,.item,.panel-sum')]
        .filter((node) => node.scrollWidth > node.clientWidth + 1)
        .map((node) => node.textContent.trim())
        .slice(0, 12),
    };
  });
  console.log(name, JSON.stringify(metrics));
}

if (pageErrors.length) {
  console.error('page errors:', pageErrors);
  process.exitCode = 1;
} else {
  console.log('no page errors');
}

await browser.close();
