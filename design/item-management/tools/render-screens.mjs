import { chromium } from 'playwright';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const screens = path.join(root, 'screens');
fs.mkdirSync(screens, { recursive: true });
const pageUrl = pathToFileURL(path.join(root, 'index.html')).href;

const only = process.argv[2] || 'all';

const browser = await chromium.launch({ headless: true });

async function openPage(viewport) {
  const context = await browser.newContext({
    viewport,
    deviceScaleFactor: 2,
    locale: 'zh-CN',
    timezoneId: 'Asia/Shanghai',
    reducedMotion: 'no-preference',
  });
  const page = await context.newPage();
  await page.goto(pageUrl, { waitUntil: 'networkidle' });
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(250);
  return { context, page };
}

async function shot(page, name, options = {}) {
  await page.waitForTimeout(160);
  await page.screenshot({ path: path.join(screens, name), ...options });
  console.log('saved', name);
}

async function desktopStates() {
  const { context, page } = await openPage({ width: 1440, height: 1000 });

  await shot(page, '01-desktop-overview.png', { fullPage: true });

  // item action menu
  await page.locator('.item-more').first().click();
  await shot(page, '02-desktop-item-menu.png');
  await page.keyboard.press('Escape');

  // edit dialog
  await page.locator('.item-more').first().click();
  await page.getByRole('menuitem', { name: '编辑事项' }).click();
  await shot(page, '03-desktop-edit-dialog.png');
  await page.keyboard.press('Escape');

  // delete confirm
  await page.locator('.item-more').first().click();
  await page.getByRole('menuitem', { name: '删除事项' }).click();
  await shot(page, '04-desktop-delete-confirm.png');
  await page.keyboard.press('Escape');

  // new task, auto-filled course
  await page.locator('.course-add').nth(2).click();
  await shot(page, '05-desktop-new-prefilled.png');
  await page.keyboard.press('Escape');

  // new course from the page-level action
  await page.locator('.new-desktop').click();
  await shot(page, '05b-desktop-new-course.png');
  await page.keyboard.press('Escape');

  // course filter menu
  await page.locator('#filterBtn').click();
  await shot(page, '06-desktop-filter-menu.png');
  await page.keyboard.press('Escape');

  // search no result
  await page.locator('#searchInput').fill('量子力学');
  await shot(page, '07-desktop-search-empty.png', { fullPage: true });

  // search result with “匹配 / 总数”计数
  await page.locator('[data-clear-search]').click();
  await page.locator('#searchInput').fill('定积分');
  await shot(page, '07b-desktop-search-count.png', { fullPage: true });

  // filtered course
  await page.locator('#searchInput').fill('');
  await page.locator('#filterBtn').click();
  await page.getByRole('menuitemradio', { name: /数据结构/ }).click();
  await shot(page, '08-desktop-filtered-course.png', { fullPage: true });

  const metrics = await page.evaluate(() => ({
    scrollHeight: document.documentElement.scrollHeight,
    boardWidth: document.querySelector('#board').getBoundingClientRect().width,
    courseCount: document.querySelectorAll('.course').length,
    filterLabel: document.querySelector('#filterLabel').textContent,
  }));
  console.log('desktop metrics', metrics);
  await context.close();
}

async function mobileStates() {
  const { context, page } = await openPage({ width: 390, height: 844 });

  await shot(page, '12-mobile-first-screen.png');
  await page.evaluate(() => document.body.classList.add('capture-nav'));
  await shot(page, '09-mobile-overview.png', { fullPage: true });
  await page.evaluate(() => document.body.classList.remove('capture-nav'));

  await page.locator('.item-more').first().click();
  await shot(page, '10-mobile-item-menu.png');
  await page.keyboard.press('Escape');

  await page.locator('.course-add').nth(2).click();
  await shot(page, '11-mobile-new-prefilled.png');
  await page.keyboard.press('Escape');

  const metrics = await page.evaluate(() => ({
    scrollHeight: document.documentElement.scrollHeight,
    scrollWidth: document.documentElement.scrollWidth,
    innerWidth: window.innerWidth,
    bottomNav: document.querySelector('.bottom-nav').getBoundingClientRect().toJSON(),
    topbar: document.querySelector('.mobile-topbar').getBoundingClientRect().toJSON(),
  }));
  console.log('mobile metrics', metrics);
  await context.close();
}

if (only === 'all' || only === 'desktop') await desktopStates();
if (only === 'all' || only === 'mobile') await mobileStates();

async function tabletStates() {
  const { context, page } = await openPage({ width: 1024, height: 1000 });
  await shot(page, '13-tablet-1024.png', { fullPage: true });
  await context.close();
}

async function narrowStates() {
  const { context, page } = await openPage({ width: 320, height: 800 });
  await page.evaluate(() => document.body.classList.add('capture-nav'));
  await shot(page, '14-mobile-320.png', { fullPage: true });
  await context.close();
}

if (only === 'all' || only === 'tablet') await tabletStates();
if (only === 'all' || only === 'narrow') await narrowStates();

await browser.close();
