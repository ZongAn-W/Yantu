import { chromium } from 'playwright';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const pageUrl = pathToFileURL(path.join(root, 'index.html')).href;

const failures = [];
function check(condition, label) {
  if (condition) console.log('  ok  ' + label);
  else { failures.push(label); console.log('  FAIL ' + label); }
}

const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({
  viewport: { width: 1440, height: 1220 },
  locale: 'zh-CN',
  timezoneId: 'Asia/Shanghai',
});
const page = await context.newPage();
await page.goto(pageUrl, { waitUntil: 'networkidle' });
await page.evaluate(() => document.fonts.ready);

console.log('\n[1] 初始结构与视觉约束');
check(await page.locator('.course').count() === 6, '6 门课程全部展示');
check(await page.locator('.item').count() === 20, '20 个事项全部展示');
check(await page.locator('.course-empty').count() === 1, '空课程仍然展示');
check(await page.locator('.course-empty-add').count() === 0, '空课程不再出现第二个重复添加入口');
check((await page.locator('.goal-meta').innerText()).includes('20 个事项'), '课程/事项数量与示例数据一致');
check((await page.locator('.new-desktop').innerText()).trim() === '新建课程', '顶部主操作为“新建课程”');
check((await page.locator('.course-name').first().boundingBox()).x === (await page.locator('.item-title').first().boundingBox()).x, '桌面事项文本与课程名对齐（文件夹层级）');
check((await page.locator('.course-head').first().evaluate((el) => getComputedStyle(el).backgroundColor)) === 'rgb(248, 250, 252)', '课程头部使用中性蓝灰底，颜色只留在图标/书脊');
const layout = await page.evaluate(() => {
  const columns = [...document.querySelectorAll('.board-col')];
  return {
    count: columns.length,
    courses: columns.map((col) => col.querySelectorAll(':scope > .course').length),
    display: columns.map((col) => getComputedStyle(col).display),
    gaps: columns.map((col) => {
      const cards = [...col.querySelectorAll(':scope > .course')];
      return cards.slice(1).map((card, index) => Math.round(card.getBoundingClientRect().top - cards[index].getBoundingClientRect().bottom));
    }),
  };
});
check(layout.count === 2, '1440px 桌面双列排列');
check(layout.courses.join(',') === '3,3', '左右两列各承载 3 门课程');
check(layout.display.every((value) => value === 'flex'), '两列是各自独立的列流');
check(layout.gaps.every((gaps) => gaps.every((gap) => gap === 18)), '列内课程间距固定 18px，不存在行间空洞');
check(await page.locator('.item-desc').count() === 0, '事项行仅展示名称，不展示说明');
const forbidden = await page.evaluate(() => {
  const visible = document.body.innerText;
  return ['当前事项', '后续事项', '已完成', '预计时长', '进度条', '截止日期', '起止日期', '优先级', '标记完成', '计时', '排程', '圆环'].filter((word) => visible.includes(word));
});
check(forbidden.length === 0, '未出现时长/进度/日期/优先级/状态/计时等字段');
check((await page.locator('.demo-chip').innerText()) === '示例数据', '顶部明确标注示例数据');
check((await page.locator('.demo-foot').innerText()).includes('示例数据'), '页脚再次标注示例数据');
check(await page.locator('.course-empty-hint').count() === 1, '空课程只保留头部一个添加入口 + 说明性空态');

console.log('\n[2] 搜索计数、空态与清除');
await page.locator('#searchInput').fill('定积分');
check(await page.locator('.item').count() === 1, '搜索“定积分”仅保留匹配事项');
check((await page.locator('.course-count').innerText()) === '1 / 5 个事项', '搜索后课程头显示“匹配 / 总数”');
check((await page.locator('#resultStatus').innerText()) === '找到 1 个事项', 'aria-live 区域播报搜索结果数');
await page.locator('#searchInput').fill('量子力学');
check(await page.locator('.board-empty').count() === 1, '无结果时出现空结果状态');
check((await page.locator('.board-empty-hint').innerText()).includes('全部课程'), '无筛选空态文案正确');
check(await page.locator('[data-clear-search]').count() === 1, '无结果时提供清除搜索入口');
await page.locator('[data-clear-search]').click();
check(await page.locator('.item').count() === 20, '清除搜索后恢复全部事项');
check((await page.locator('#searchInput').inputValue()) === '', '清除搜索后搜索框清空');

console.log('\n[3] 课程筛选与筛选+搜索空态');
await page.locator('#filterBtn').click();
check(await page.locator('.course-option').count() === 7, '课程筛选含“全部课程”+ 6 门课程');
check((await page.locator('.course-option.is-selected').innerText()).includes('全部课程'), '筛选菜单有明确选中态');
await page.getByRole('menuitemradio', { name: /数据结构/ }).click();
check((await page.locator('#filterLabel').innerText()) === '数据结构', '筛选后按钮显示当前课程');
check(await page.locator('.course').count() === 1, '筛选后仅显示所选课程');
check(await page.locator('.board-columns').count() === 0, '筛选单卡时切换为完整单列，不留半列空白');
check((await page.locator('.course').boundingBox()).width > 1000, '筛选单卡使用完整内容宽度');
check(await page.locator('.item').count() === 4, '筛选后事项数量正确');
await page.locator('#searchInput').fill('量子力学');
check((await page.locator('.board-empty-hint').innerText()).includes('当前筛选「数据结构」'), '筛选+搜索空态文案区分了筛选条件');
await page.locator('[data-clear-filter]').click();
check((await page.locator('#filterLabel').innerText()) === '全部课程', '空态提供“切换全部课程”入口');
await page.locator('[data-clear-search]').click();
check(await page.locator('.item').count() === 20, '恢复全部课程与事项');

console.log('\n[4] 事项菜单与键盘');
check(await page.locator('.item-more').count() === 20, '每个事项右侧只有一个“⋯”操作按钮');
await page.locator('.item-more').first().click();
check(await page.locator('.menu-item').count() === 2, '菜单仅含两个操作');
check((await page.locator('.menu-item').allInnerTexts()).join('|') === '编辑事项|删除事项', '菜单内容为“编辑事项 / 删除事项”');
await page.keyboard.press('Tab');
check(await page.locator('.popover').count() === 0, 'Tab 离开菜单时浮层关闭');
await page.locator('.item-more').first().click();
await page.keyboard.press('Escape');
check(await page.locator('.popover').count() === 0, 'Esc 可关闭菜单');
check(await page.locator('.item-more').first().evaluate((el) => el === document.activeElement), '关闭菜单后焦点回到触发按钮');

console.log('\n[5] 编辑事项与焦点恢复');
await page.locator('.item-more').first().click();
await page.getByRole('menuitem', { name: '编辑事项' }).click();
check((await page.locator('#modalTitle').innerText()) === '编辑事项', '打开编辑弹窗');
check((await page.locator('#taskTitle').inputValue()).length > 0, '编辑弹窗带入名称');
check((await page.locator('#taskDesc').inputValue()).length > 0, '编辑弹窗带入说明');
check((await page.locator('#taskCourse').inputValue()) === 'calculus', '编辑弹窗带入所属课程');
await page.locator('#taskTitle').fill('极限与连续：错题重做');
await page.locator('#taskDesc').fill('重新整理错题，补做 10 道极限计算题。');
await page.locator('#taskCourse').selectOption('english');
await page.getByRole('button', { name: '保存' }).click();
await page.waitForTimeout(220);
check(await page.locator('.modal').isHidden(), '保存后弹窗关闭');
const englishItems = await page.locator('.course[data-course="english"]').locator('.item-title').allInnerTexts();
check(englishItems.includes('极限与连续：错题重做'), '事项已移动到新课程下');
const calculusItems = await page.locator('.course[data-course="calculus"]').locator('.item-title').allInnerTexts();
check(!calculusItems.includes('极限与连续：错题重做'), '原课程下不再显示该事项');
check(await page.locator('.item').count() === 20, '编辑后事项总数不变');
const editFocus = await page.evaluate(() => ({
  isMore: document.activeElement.classList.contains('item-more'),
  course: document.activeElement.getAttribute('data-course'),
}));
check(editFocus.isMore && editFocus.course === 'english', '保存后焦点落在目标行的“⋯”上');

console.log('\n[6] 删除确认与焦点恢复');
await page.reload({ waitUntil: 'networkidle' });
await page.evaluate(() => document.fonts.ready);
const target = page.locator('.item', { hasText: '排序算法对比与复杂度分析' });
await target.locator('.item-more').click();
await page.getByRole('menuitem', { name: '删除事项' }).click();
check((await page.locator('#modalTitle').innerText()) === '删除事项', '删除前弹出确认');
check((await page.locator('.confirm-text').innerText()).includes('排序算法对比与复杂度分析'), '确认文案包含事项名称');
check((await page.locator('.confirm-sub').innerText()) === '删除后无法恢复，请谨慎操作。', '删除副文案不重复');
check((await page.locator('#modalEl').getAttribute('aria-describedby')) === 'deleteWarning', '删除警告通过 aria-describedby 关联');
check((await page.locator('.modal-foot [data-modal-cancel]').evaluate((el) => el === document.activeElement)), '删除弹窗初始焦点在“取消”');
await page.getByRole('button', { name: '确认删除' }).click();
await page.waitForTimeout(220);
check(await page.locator('.item').count() === 19, '确认后事项被删除');
check((await page.locator('.course[data-course="data-structure"] .course-count').innerText()) === '3 个事项', '课程计数同步更新');
check(await page.evaluate(() => document.activeElement.classList.contains('item-more')), '删除后焦点落到相邻事项');

console.log('\n[7] 新建事项（从课程添加入口，自动带入课程）');
await page.locator('.course[data-course="computer-organization"] .course-add').click();
check((await page.locator('#modalTitle').innerText()) === '新建事项', '打开新建弹窗');
check((await page.locator('#taskCourse').inputValue()) === 'computer-organization', '自动带入所属课程');
check((await page.locator('.field-note').innerText()).includes('已自动带入'), '显示自动带入提示');
check(await page.getByRole('button', { name: '保存' }).isDisabled(), '名称为空时保存按钮禁用');
await page.locator('#taskTitle').fill('指令系统与寻址方式');
await page.getByRole('button', { name: '保存' }).click();
await page.waitForTimeout(220);
check(await page.locator('.course-empty').count() === 0, '空课程添加事项后空状态消失');
check((await page.locator('.course[data-course="computer-organization"] .course-count').innerText()) === '1 个事项', '课程计数更新');
check(await page.evaluate(() => document.activeElement.classList.contains('item-more')), '新建后焦点落在新事项的“⋯”上');

console.log('\n[8] 新建课程（页面顶部入口）');
await page.reload({ waitUntil: 'networkidle' });
await page.evaluate(() => document.fonts.ready);
await page.locator('.new-desktop').click();
check((await page.locator('#modalTitle').innerText()) === '新建课程', '打开新建课程弹窗');
check(await page.getByRole('button', { name: '创建课程' }).isDisabled(), '课程名称为空时创建按钮禁用');
await page.locator('#courseName').fill('概率论与数理统计');
check(await page.getByRole('button', { name: '创建课程' }).isEnabled(), '填写名称后可创建');
await page.locator('.swatch').nth(2).click();
check(await page.locator('.swatch[aria-checked="true"]').count() === 1, '课程颜色为单选');
await page.getByRole('button', { name: '创建课程' }).click();
await page.waitForTimeout(250);
check(await page.locator('.modal').isHidden(), '创建后弹窗关闭');
check(await page.locator('.course').count() === 7, '课程数量增加');
const newCourse = page.locator('.course', { hasText: '概率论与数理统计' });
check((await newCourse.locator('.course-count').innerText()) === '0 个事项', '新课程为空课程');
check((await newCourse.locator('.course-empty').count()) === 1, '新课程显示空态和添加入口');
check((await page.locator('#goalMeta').innerText()) === '7 门课程 · 20 个事项', '侧栏课程数量同步更新');
check((await newCourse.evaluate((el) => getComputedStyle(el).getPropertyValue('--course').trim())) === '#c2761f', '新建课程使用所选颜色');
check(await page.evaluate(() => document.activeElement.classList.contains('course-add')), '创建后焦点落到新课程的添加入口');

console.log('\n[9] 响应式边界');
await page.setViewportSize({ width: 1024, height: 900 });
await page.waitForTimeout(150);
const tablet = await page.evaluate(() => ({
  columns: document.querySelectorAll('.board-col').length,
  display: getComputedStyle(document.querySelector('#board')).display,
  direction: getComputedStyle(document.querySelector('#board')).flexDirection,
  overflow: document.documentElement.scrollWidth > window.innerWidth,
  sidebar: getComputedStyle(document.querySelector('.sidebar')).display,
  bottomNav: getComputedStyle(document.querySelector('.bottom-nav')).display,
  nameTruncated: [...document.querySelectorAll('.course-name')].some((n) => n.scrollWidth > n.clientWidth + 1),
}));
check(tablet.columns === 0 && tablet.display === 'flex' && tablet.direction === 'column', '1024px 平板宽度单列展示（避免课程名截断）');
check(!tablet.overflow && !tablet.nameTruncated, '1024px 无横向溢出、课程名完整');
check(tablet.sidebar !== 'none', '1024px 显示侧边栏');
check(tablet.bottomNav === 'none', '平板宽度隐藏底部导航');

await page.setViewportSize({ width: 900, height: 900 });
await page.waitForTimeout(120);
const narrowDesktop = await page.evaluate(() => ({
  columns: document.querySelectorAll('.board-col').length,
  display: getComputedStyle(document.querySelector('#board')).display,
  overflow: document.documentElement.scrollWidth > window.innerWidth,
  nameTruncated: [...document.querySelectorAll('.course-name')].some((n) => n.scrollWidth > n.clientWidth + 1),
}));
check(narrowDesktop.columns === 0 && narrowDesktop.display === 'flex' && !narrowDesktop.overflow && !narrowDesktop.nameTruncated, '900px 断点无课程名截断/溢出');

await page.setViewportSize({ width: 390, height: 844 });
await page.waitForTimeout(150);
const mobile = await page.evaluate(() => ({
  columns: document.querySelectorAll('.board-col').length,
  display: getComputedStyle(document.querySelector('#board')).display,
  overflow: document.documentElement.scrollWidth > window.innerWidth,
  sidebar: getComputedStyle(document.querySelector('.sidebar')).display,
  bottomNav: getComputedStyle(document.querySelector('.bottom-nav')).display,
  topbar: getComputedStyle(document.querySelector('.mobile-topbar')).display,
  itemMore: Math.round(document.querySelector('.item-more').getBoundingClientRect().width),
  navFont: parseFloat(getComputedStyle(document.querySelector('.bottom-nav button')).fontSize),
}));
check(mobile.columns === 0 && mobile.display === 'flex', '390px 课程单列展示');
check(!mobile.overflow, '390px 无横向溢出');
check(mobile.sidebar === 'none' && mobile.bottomNav === 'flex' && mobile.topbar === 'flex', '手机端使用品牌栏 + 底部导航');
check(mobile.itemMore >= 38, '手机端“⋯”触控区至少 38px（含伪元素命中区 44px）');
check(mobile.navFont >= 10.5, '底部导航标签不小于 10.5px');

await page.setViewportSize({ width: 320, height: 800 });
await page.waitForTimeout(150);
const small = await page.evaluate(() => ({
  columns: document.querySelectorAll('.board-col').length,
  overflow: document.documentElement.scrollWidth > window.innerWidth,
  searchWidth: Math.round(document.querySelector('.search').getBoundingClientRect().width),
  filterRight: Math.round(document.querySelector('.filter-btn').getBoundingClientRect().right),
}));
check(small.columns === 0 && !small.overflow, '320px 单列且无横向溢出');
check(small.filterRight <= 304, '320px 搜索/筛选完整可用');

console.log('\n[10] 手机端菜单与弹窗');
await page.setViewportSize({ width: 390, height: 844 });
await page.waitForTimeout(120);
await page.locator('.item-more').first().click();
check(await page.locator('.popover').count() === 1, '手机端可打开事项菜单');
check((await page.locator('.menu-item').first().evaluate((el) => el.getBoundingClientRect().height)) >= 44, '手机端菜单行高 ≥ 44px');
await page.keyboard.press('Escape');
await page.locator('.course-add').first().click();
await page.waitForTimeout(220);
check((await page.locator('#taskCourse').inputValue()) === 'calculus', '手机端课程添加入口同样带入课程');
check((await page.locator('.modal-foot .btn').first().evaluate((el) => el.getBoundingClientRect().height)) >= 44, '手机端弹窗按钮高 ≥ 44px');
await page.keyboard.press('Escape');
check(await page.locator('.modal').isHidden(), '手机端弹窗可关闭');

await context.close();
await browser.close();

console.log('\n' + (failures.length === 0 ? '全部通过 ✓' : '存在失败：\n- ' + failures.join('\n- ')));
process.exitCode = failures.length ? 1 : 0;
