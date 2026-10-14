import { test, expect, type Page, type Locator } from '@playwright/test';
import { readFile } from 'node:fs/promises';
import type { PlannerData } from '../packages/planner-engine/src/types';

const STORAGE_KEY = 'sjtu-study-planner:items-v2';
const TODAY = '2026-10-14';
const TOMORROW = '2026-10-29';

async function readPlan(page: Page): Promise<PlannerData> {
  return page.evaluate(key => JSON.parse(localStorage.getItem(key) ?? 'null'), STORAGE_KEY);
}

async function expectSaved(page: Page, predicate: (data: PlannerData) => boolean) {
  await expect.poll(async () => predicate(await readPlan(page))).toBe(true);
}

async function createTask(page: Page, title: string, minutes = 120) {
  await page.goto('/tasks');
  await page.getByRole('button', { name: '新建事项', exact: true }).click();
  const dialog = page.getByRole('dialog', { name: '新建事项', exact: true });
  await dialog.getByLabel('事项名称', { exact: true }).fill(title);
  await dialog.getByLabel('预计总时长（分钟）', { exact: true }).fill(String(minutes));
  await dialog.getByLabel('截止日期', { exact: true }).fill('2027-12-01');
  await dialog.getByRole('button', { name: '保存事项', exact: true }).click();
  await expect(dialog).toBeHidden();
  const row = page.locator('[data-testid^="task-row-"]').filter({ has: page.getByText(title, { exact: true }) });
  await expect(row).toBeVisible();
  return row;
}

async function scheduleTask(page: Page, row: Locator, date = '2027-12-01', minutes?: number) {
  await row.getByRole('button', { name: /^安排 / }).click();
  const dialog = page.getByRole('dialog', { name: '安排时间块', exact: true });
  await dialog.getByLabel('安排日期', { exact: true }).fill(date);
  if (minutes !== undefined) await dialog.getByLabel('当天分配时长（分钟）', { exact: true }).fill(String(minutes));
  await dialog.getByRole('button', { name: '拆分并安排', exact: true }).click();
  await expect(dialog).toBeHidden();
}

async function groupDetails(page: Page, row: Locator) {
  const key = await row.getAttribute('data-category-day-id');
  const data = await readPlan(page);
  const blocks = data.blocks.filter(block => `${block.task_id}:${block.date}` === key);
  const ids = blocks.map(block => block.id);
  return { key: key!, ids, taskId: blocks[0].task_id, planned: blocks.reduce((sum, block) => sum + block.duration_minutes, 0) };
}

async function recordActual(page: Page, row: Locator, minutes: number, markCompleted = false) {
  const group = await groupDetails(page, row);
  await row.getByRole('button', { name: /^记录实际用时：/ }).click();
  const dialog = page.getByRole('dialog', { name: '记录实际用时', exact: true });
  await dialog.getByLabel('实际用时（分钟）', { exact: true }).fill(String(minutes));
  await dialog.getByRole('button', { name: '保存实际用时', exact: true }).click();
  await expect(dialog).toBeHidden();
  await expectSaved(page, data => data.logs.filter(log => group.ids.includes(log.block_id ?? '')).reduce((sum, log) => sum + log.minutes, 0) === minutes);
  if (markCompleted) for (const checkbox of await row.getByRole('checkbox').all()) await checkbox.check();
  return group;
}

async function firstEnglishRow(page: Page, date = TODAY) {
  const data = await readPlan(page);
  const english = data.tasks.find(task => ['vocabulary', 'grammar', 'reading'].includes(task.subject_id) && data.blocks.some(block => block.task_id === task.id && block.date === date))!;
  return page.locator(`[data-task-day-id="${english.id}:${date}"]`);
}

async function assertNoHorizontalOverflow(page: Page, route: string) {
  const bounds = await page.evaluate(() => ({ viewport: innerWidth, document: document.documentElement.scrollWidth, body: document.body.scrollWidth }));
  expect(bounds.document, `${route}: document should fit the viewport`).toBeLessThanOrEqual(bounds.viewport);
  expect(bounds.body, `${route}: body should fit the viewport`).toBeLessThanOrEqual(bounds.viewport);
}

test.beforeEach(async ({ page }) => {
  // Use a stable Shanghai calendar date for the complete seeded plan.
  await page.clock.install({ time: new Date(`${TODAY}T09:00:00+08:00`) });
  await page.goto('/');
  await expect(page.getByTestId('today-completed-minutes')).toBeVisible();
});

test('creates, edits and deletes a task, preserving the edit across refresh', async ({ page }) => {
  const title = '端到端测试 · 高数极限专项';
  const editedTitle = '端到端测试 · 高数极限与连续专项';
  const row = await createTask(page, title);
  await row.getByRole('button', { name: /^编辑(?:事项：| )/ }).click();
  const editor = page.getByRole('dialog', { name: '编辑事项', exact: true });
  await editor.getByLabel('事项名称', { exact: true }).fill(editedTitle);
  await editor.getByLabel('学习范围与完成标准', { exact: true }).fill('范围：极限与连续。完成标准：完成基础题并整理错题。');
  await editor.getByLabel('预计总时长（分钟）', { exact: true }).fill('180');
  await editor.getByRole('button', { name: '保存事项', exact: true }).click();
  await page.reload();
  const edited = page.locator('[data-testid^="task-row-"]').filter({ hasText: editedTitle });
  await expect(edited).toBeVisible();
  await expect(edited).toContainText('3小时');
  await edited.getByText('学习范围与完成标准', { exact: true }).click();
  await expect(edited).toContainText('完成标准：完成基础题并整理错题。');
  await edited.getByRole('button', { name: /^删除(?:事项：| )/ }).click();
  const deletion = page.getByRole('dialog', { name: '删除事项', exact: true });
  await deletion.getByRole('button', { name: '确认删除', exact: true }).click();
  await expect(edited).toHaveCount(0);
  await expectSaved(page, data => !data.tasks.some(task => task.title === editedTitle));
  await page.reload();
  await expect(page.locator('[data-testid^="task-row-"]').filter({ hasText: editedTitle })).toHaveCount(0);
});

test('shows compact course stages and hides future work by default', async ({ page }) => {
  const data = await readPlan(page);
  const base = data.tasks.find(item => item.subject_id === 'calculus' && item.title === '基础一轮')!;
  const advanced = data.tasks.find(item => item.subject_id === 'calculus' && item.title === '专题强化')!;
  await page.goto('/calendar');
  await expect(page.locator(`[data-task-day-id="${base.id}:${TODAY}"]`)).toContainText('高数');
  await page.goto('/tasks');
  await expect(page.getByTestId(`task-row-${base.id}`)).toBeVisible();
  await expect(page.getByTestId(`task-row-${advanced.id}`)).toHaveCount(0);
  await page.getByLabel(/显示后续事项/).check();
  await expect(page.getByTestId(`task-row-${advanced.id}`)).toBeVisible();
  await page.getByTestId(`task-row-${advanced.id}`).getByText('学习范围与完成标准', { exact: true }).click();
  await expect(page.getByTestId(`task-row-${advanced.id}`)).toContainText('完成标准：');
  await page.getByLabel(/显示后续事项/).uncheck();
  await page.reload();
  await expect(page.getByTestId(`task-row-${advanced.id}`)).toHaveCount(0);
});

test('splits a task into 30 minute learning units and supports subject and deadline filters', async ({ page }) => {
  const title = '端到端测试 · 英语长难句';
  const row = await createTask(page, title, 60);
  await row.getByRole('button', { name: /^编辑(?:事项：| )/ }).click();
  const editor = page.getByRole('dialog', { name: '编辑事项', exact: true });
  await editor.getByLabel('课程', { exact: true }).fill('词汇');
  await editor.getByRole('button', { name: '保存事项', exact: true }).click();
  await scheduleTask(page, row);
  await expectSaved(page, data => {
    const task = data.tasks.find(item => item.title === title);
    const blocks = data.blocks.filter(item => item.task_id === task?.id);
    return blocks.length === 2 && blocks.every(item => item.duration_minutes === 30 && item.date === '2027-12-01');
  });
  await page.getByLabel('课程', { exact: true }).selectOption('calculus');
  await expect(row).toHaveCount(0);
  await page.getByLabel('课程', { exact: true }).selectOption('vocabulary');
  await expect(row).toBeVisible();
  await page.getByLabel('截止日期之前', { exact: true }).fill('2026-12-31');
  await expect(row).toHaveCount(0);
});

test('keeps time independent for two items in one custom course', async ({ page }) => {
  await page.evaluate(key => { const data = JSON.parse(localStorage.getItem(key)!); data.blocks = data.blocks.filter((block: { date: string }) => block.date !== '2026-10-14'); localStorage.setItem(key, JSON.stringify(data)); }, STORAGE_KEY);
  await page.reload();
  const first = await createTask(page, '基础', 120);
  await first.getByRole('button', { name: /^编辑 / }).click();
  await page.getByRole('dialog').getByLabel('课程', { exact: true }).fill('自定义课程');
  await page.getByRole('button', { name: '保存事项', exact: true }).click();
  await scheduleTask(page, first, TODAY, 30);
  const second = await createTask(page, '强化', 120);
  await second.getByRole('button', { name: /^编辑 / }).click();
  await page.getByRole('dialog').getByLabel('课程', { exact: true }).fill('自定义课程');
  await page.getByRole('button', { name: '保存事项', exact: true }).click();
  await scheduleTask(page, second, TODAY, 30);
  const data = await readPlan(page);
  const base = data.tasks.find(task => task.title === '基础')!;
  const advanced = data.tasks.find(task => task.title === '强化')!;
  expect(data.blocks.filter(block => block.task_id === base.id).reduce((sum, block) => sum + block.duration_minutes, 0)).toBe(30);
  expect(base.estimated_minutes).toBe(120);
  await page.goto('/');
  const baseRow = page.locator(`[data-task-day-id="${base.id}:${TODAY}"]`);
  const advancedRow = page.locator(`[data-task-day-id="${advanced.id}:${TODAY}"]`);
  await expect(page.getByRole('region', { name: '自定义课程今日计划' })).toBeVisible();
  await recordActual(page, baseRow, 45);
  await recordActual(page, advancedRow, 30);
  await recordActual(page, baseRow, 20);
  const saved = await readPlan(page);
  expect(saved.logs.filter(log => log.task_id === base.id).reduce((sum, log) => sum + log.minutes, 0)).toBe(20);
  expect(saved.logs.filter(log => log.task_id === advanced.id).reduce((sum, log) => sum + log.minutes, 0)).toBe(30);
  await page.reload();
  await expect(baseRow).toBeVisible();
  await page.goto('/progress');
  await expect(page.getByRole('heading', { name: '课程与事项学习时长' })).toBeVisible();
});

test('records an existing unscheduled item without creating a plan', async ({ page }) => {
  await createTask(page, '自主强化', 120);
  const before = await readPlan(page);
  const item = before.tasks.find(task => task.title === '自主强化')!;
  await page.goto('/');
  await page.getByRole('button', { name: '记录事项用时', exact: true }).click();
  const editor = page.getByRole('dialog', { name: '记录实际用时' });
  await editor.getByLabel('课程', { exact: true }).selectOption(item.subject_id);
  await editor.getByLabel('事项', { exact: true }).selectOption(item.id);
  await editor.getByLabel('实际用时（分钟）', { exact: true }).fill('45');
  await editor.getByRole('button', { name: '保存实际用时', exact: true }).click();
  const after = await readPlan(page);
  expect(after.blocks).toEqual(before.blocks);
  expect(after.logs.filter(log => log.task_id === item.id).reduce((sum, log) => sum + log.minutes, 0)).toBe(45);
});

test('manual completion records only supplied actual minutes and excludes finished tasks from scheduling', async ({ page }) => {
  const title = '端到端测试 · 手动完成只记录真实用时';
  const zeroTitle = '端到端测试 · 零分钟标记完成';
  const row = await createTask(page, title, 120);
  const before = await readPlan(page);
  const taskId = before.tasks.find(task => task.title === title)!.id;
  await row.getByRole('button', { name: /^标记完成 / }).click();
  let dialog = page.getByRole('dialog', { name: '标记事项完成', exact: true });
  await expect(dialog.getByLabel('本次实际学习时长（分钟）', { exact: true })).toHaveValue('0');
  await dialog.getByLabel('本次实际学习时长（分钟）', { exact: true }).fill('45');
  await dialog.getByRole('button', { name: '确认完成', exact: true }).click();
  await expect(dialog).toBeHidden();
  await expectSaved(page, data => data.tasks.find(task => task.id === taskId)?.status === 'completed');
  let data = await readPlan(page);
  expect(data.tasks.find(task => task.id === taskId)).toMatchObject({ estimated_minutes: 120, completed_minutes: 45, status: 'completed' });
  expect(data.logs.filter(log => log.task_id === taskId)).toHaveLength(1);
  expect(data.logs.filter(log => log.task_id === taskId).reduce((sum, log) => sum + log.minutes, 0)).toBe(45);
  expect(data.logs.reduce((sum, log) => sum + log.minutes, 0)).toBe(45);
  await expect(row.getByRole('button', { name: /^安排 / })).toBeDisabled();
  await page.reload();
  await expect(row.getByRole('button', { name: /^安排 / })).toBeDisabled();
  expect((await readPlan(page)).tasks.find(task => task.id === taskId)).toMatchObject({ completed_minutes: 45, status: 'completed' });

  const zeroRow = await createTask(page, zeroTitle, 120);
  const zeroTaskId = (await readPlan(page)).tasks.find(task => task.title === zeroTitle)!.id;
  await zeroRow.getByRole('button', { name: /^标记完成 / }).click();
  dialog = page.getByRole('dialog', { name: '标记事项完成', exact: true });
  await expect(dialog.getByLabel('本次实际学习时长（分钟）', { exact: true })).toHaveValue('0');
  await dialog.getByRole('button', { name: '确认完成', exact: true }).click();
  await expect(dialog).toBeHidden();
  await expectSaved(page, saved => saved.tasks.find(task => task.id === zeroTaskId)?.status === 'completed');
  data = await readPlan(page);
  expect(data.tasks.find(task => task.id === zeroTaskId)).toMatchObject({ completed_minutes: 0, status: 'completed' });
  expect(data.logs.filter(log => log.task_id === zeroTaskId)).toHaveLength(0);
  await expect(zeroRow.getByRole('button', { name: /^安排 / })).toBeDisabled();

  await page.goto('/');
  await expect(page.getByTestId('today-completed-minutes')).toHaveAttribute('data-minutes', '45');
  await page.getByRole('button', { name: /智能重排|重排计划/ }).click();
  const preview = page.getByRole('dialog', { name: '重排预览', exact: true });
  await preview.getByRole('button', { name: '确认调整', exact: true }).click();
  await expect(preview).toBeHidden();
  await expectSaved(page, saved => saved.replan_runs.length === 1);
  data = await readPlan(page);
  const completedIds = [taskId, zeroTaskId];
  expect(data.blocks.filter(block => completedIds.includes(block.task_id) && block.status === 'planned')).toHaveLength(0);
  expect(data.replan_runs[0].after.filter(block => completedIds.includes(block.task_id) && block.status === 'planned')).toHaveLength(0);
  expect(data.logs.reduce((sum, log) => sum + log.minutes, 0)).toBe(45);
  expect(data.tasks.find(task => task.id === taskId)).toMatchObject({ completed_minutes: 45, status: 'completed' });
  expect(data.tasks.find(task => task.id === zeroTaskId)).toMatchObject({ completed_minutes: 0, status: 'completed' });
});

test('records partial actual learning, edits down without duplicate hours, and keeps refresh progress', async ({ page }) => {
  await expect(page.getByTestId('today-completed-minutes')).toHaveAttribute('data-minutes', '0');
  const row = page.getByTestId('schedule-block').first();
  const group = await recordActual(page, row, 15);
  let data = await readPlan(page);
  expect(data.blocks.filter(block => group.ids.includes(block.id)).every(block => block.status === 'planned')).toBe(true);
  expect(data.tasks.find(task => task.id === group.taskId)?.completed_minutes).toBe(15);
  await recordActual(page, row, 20);
  await recordActual(page, row, 10);
  data = await readPlan(page);
  expect(data.logs.filter(log => group.ids.includes(log.block_id ?? '')).reduce((sum, log) => sum + log.minutes, 0)).toBe(10);
  expect(data.blocks.filter(block => group.ids.includes(block.id)).reduce((sum, block) => sum + block.actual_minutes, 0)).toBe(10);
  expect(data.tasks.find(task => task.id === group.taskId)?.completed_minutes).toBe(10);
  expect(data.logs.every(log => log.source === 'manual' && log.minutes > 0)).toBe(true);
  await page.reload();
  await expect(page.getByTestId('today-completed-minutes')).toHaveAttribute('data-minutes', '10');
  await row.getByRole('button', { name: /^调整日期：/ }).click();
  const dateEditor = page.getByRole('dialog', { name: '调整事项日期', exact: true });
  await expect(dateEditor.getByLabel('安排日期', { exact: true })).toBeDisabled();
  await dateEditor.getByRole('button', { name: '取消', exact: true }).click();
  expect((await readPlan(page)).logs.every(log => log.date === TODAY)).toBe(true);
  const rate = Math.round(10 / data.blocks.filter(block => block.date === TODAY).reduce((sum, block) => sum + block.duration_minutes, 0) * 100);
  await page.goto('/progress');
  await expect(page.getByRole('img', { name: '课程周计划与实际时长柱状图' })).toBeVisible();
  await expect(page.getByLabel(`${TODAY} 实际10分钟 完成率${rate}%`, { exact: true })).toBeVisible();
  await expect(page.getByRole('img', { name: '按实际完成记录计算的剩余事项量燃尽图' })).toBeVisible();
});

test('daily completion leaves the whole stage open and persists after time correction', async ({ page }) => {
  const row = page.getByTestId('schedule-block').first();
  const group = await groupDetails(page, row);
  await recordActual(page, row, group.planned);
  await expect(row).not.toHaveClass(/done/);
  for (const checkbox of await row.getByRole('checkbox').all()) await checkbox.check();
  await expect(row).toHaveClass(/done/);
  const checked = await readPlan(page);
  expect(checked.tasks.find(task => task.id === group.taskId)?.status).toBe('in_progress');
  expect(checked.blocks.filter(block => block.task_id === group.taskId && block.date > TODAY).some(block => block.status === 'planned')).toBe(true);
  await recordActual(page, row, 30);
  await expect(row).toHaveClass(/done/);
  expect((await readPlan(page)).logs.reduce((sum, log) => sum + log.minutes, 0)).toBe(30);
  await page.reload();
  await expect(row).toHaveClass(/done/);
  await row.getByRole('checkbox').first().uncheck();
  await expect(row).not.toHaveClass(/done/);
  expect((await readPlan(page)).tasks.find(task => task.id === group.taskId)?.status).not.toBe('completed');
  expect((await readPlan(page)).logs.reduce((sum, log) => sum + log.minutes, 0)).toBe(30);
});

test('daily study rows keep the target and actions together with details collapsed', async ({ page }) => {
  const row = page.getByTestId('schedule-block').first();
  const group = await groupDetails(page, row);
  await expect(row).toContainText('高数');
  await expect(row).toContainText('基础一轮');
  await expect(row).toContainText('今日目标');
  const bounds = await row.boundingBox();
  expect(bounds!.height).toBeLessThan(200);
  await expect(row.locator('.study-row-details')).not.toHaveAttribute('open');
  await row.getByText('学习内容', { exact: true }).click();
  await expect(row).toContainText('完成标准：');
  await expect(row).toContainText('事项截止');
  await row.getByText('学习内容', { exact: true }).click();
  await row.getByRole('button', { name: /^记录实际用时：/ }).click();
  const dialog = page.getByRole('dialog', { name: '记录实际用时' });
  await expect(dialog.locator('.record-item-heading')).toContainText('高数');
  await expect(dialog.getByRole('combobox')).toHaveCount(0);
  await dialog.getByLabel('实际用时（分钟）', { exact: true }).fill('20');
  await dialog.getByRole('button', { name: '保存实际用时' }).click();
  await expect(row.getByRole('button', { name: /^记录实际用时：/ })).toHaveText('修改用时');
  await expect(row).toContainText('20分钟');
  await row.getByRole('checkbox').check();
  await expect(row).toHaveClass(/done/);
  await expectSaved(page, data => data.tasks.find(task => task.id === group.taskId)?.status === 'in_progress');
});

test('caps completed task volume while retaining all overrun actual learning and daily excess', async ({ page }) => {
  const title = '端到端测试 · 已掌握专题';
  const taskRow = await createTask(page, title, 60);
  await taskRow.getByRole('button', { name: /^编辑 / }).click();
  const editor = page.getByRole('dialog', { name: '编辑事项', exact: true });
  await editor.getByLabel('课程', { exact: true }).fill('概率论');
  await editor.getByRole('button', { name: '保存事项', exact: true }).click();
  await scheduleTask(page, taskRow, TODAY);
  await page.goto('/');
  const row = page.getByTestId('schedule-block').filter({ has: page.getByText(title, { exact: true }) });
  await expect(row).toBeVisible();
  const data = await readPlan(page);
  const planned = data.blocks.filter(block => block.date === TODAY).reduce((sum, block) => sum + block.duration_minutes, 0);
  const actual = planned + 60;
  const group = await recordActual(page, row, actual);
  const updated = await readPlan(page);
  expect(updated.tasks.find(task => task.id === group.taskId)).toMatchObject({ completed_minutes: 60 });
  expect(updated.logs.filter(log => group.ids.includes(log.block_id ?? '')).reduce((sum, log) => sum + log.minutes, 0)).toBe(actual);
  await expect(page.getByTestId('today-completed-minutes')).toHaveAttribute('data-minutes', String(actual));
  await expect(page.locator('dl').filter({ hasText: '超额完成' })).toContainText('1小时');
  await page.getByRole('button', { name: /智能重排|重排计划/ }).click();
  const preview = page.getByRole('dialog', { name: '重排预览', exact: true });
  await preview.getByRole('button', { name: /超额提前/ }).click();
  await expect(preview).toContainText('1小时');
  await preview.getByRole('button', { name: '取消调整', exact: true }).click();
});

test('previews without writing, cancels, confirms with history, and undoes the latest replan', async ({ page }) => {
  await recordActual(page, page.getByTestId('schedule-block').first(), 60);
  const before = await readPlan(page);
  const replan = page.getByRole('button', { name: /智能重排|重排计划/ });
  await replan.click();
  let preview = page.getByRole('dialog', { name: '重排预览', exact: true });
  await expect(preview).toBeVisible();
  await expect(preview.getByRole('heading', { name: '每日学习时长', exact: true })).toBeVisible();
  expect((await readPlan(page)).blocks).toEqual(before.blocks);
  await preview.getByRole('button', { name: '取消调整', exact: true }).click();
  await expect(preview).toBeHidden();
  expect((await readPlan(page)).replan_runs).toHaveLength(0);
  expect((await readPlan(page)).blocks).toEqual(before.blocks);
  await replan.click();
  preview = page.getByRole('dialog', { name: '重排预览', exact: true });
  await preview.getByRole('button', { name: '确认调整', exact: true }).click();
  await expect(preview).toBeHidden();
  await expectSaved(page, data => data.replan_runs.length === 1 && data.replan_runs[0].status === 'confirmed');
  const confirmed = await readPlan(page);
  expect(confirmed.replan_runs[0].before).toEqual(before.blocks);
  expect(confirmed.replan_runs[0].changes.length).toBeGreaterThan(0);
  expect(confirmed.replan_runs[0].changes.every(change => change.run_id === confirmed.replan_runs[0].id)).toBe(true);
  await page.getByRole('button', { name: '撤销最近调整', exact: true }).click();
  await expectSaved(page, data => data.replan_runs[0]?.status === 'undone');
  expect((await readPlan(page)).blocks).toEqual(before.blocks);
  expect((await readPlan(page)).logs).toEqual(before.logs);
});

test('moves a whole daily task group between dates through the calendar date dialog', async ({ page }) => {
  await page.goto('/calendar');
  await page.getByRole('button', { name: '日视图', exact: true }).click();
  const row = await firstEnglishRow(page);
  const group = await groupDetails(page, row);
  await row.getByRole('button', { name: /^调整日期：/ }).click();
  const editor = page.getByRole('dialog', { name: '调整事项日期', exact: true });
  await editor.getByLabel('安排日期', { exact: true }).fill(TOMORROW);
  await expect(editor.locator('input[type="time"]')).toHaveCount(0);
  await editor.getByRole('button', { name: '保存日期', exact: true }).click();
  await expect(editor).toBeHidden();
  await expectSaved(page, data => data.blocks.filter(block => group.ids.includes(block.id)).every(block => block.date === TOMORROW));
  await expect(row).toHaveCount(0);
  await page.getByLabel('日历起始日期', { exact: true }).fill(TOMORROW);
  await page.getByRole('button', { name: '周视图', exact: true }).click();
  const target = page.locator(`[data-testid="calendar-day"][data-date="${TOMORROW}"]`);
  await expect(target.locator(`[data-task-day-id="${group.taskId}:${TOMORROW}"]`)).toBeVisible();
  await page.reload();
  expect((await readPlan(page)).blocks.filter(block => group.ids.includes(block.id)).every(block => block.date === TOMORROW)).toBe(true);
});

test('drags a daily task group into another day preserving all learning units', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name === 'mobile', 'Mobile manages dates through the separately tested edit dialog.');
  const title = '端到端测试 · 拖拽日期';
  const taskRow = await createTask(page, title, 60);
  await taskRow.getByRole('button', { name: /^编辑(?:事项：| )/ }).click();
  const editor = page.getByRole('dialog', { name: '编辑事项', exact: true });
  await editor.getByLabel('课程', { exact: true }).fill('词汇');
  await editor.getByRole('button', { name: '保存事项', exact: true }).click();
  await scheduleTask(page, taskRow, '2026-10-29');
  await page.goto('/calendar');
  await page.getByLabel('日历起始日期', { exact: true }).fill('2026-10-29');
  await page.getByRole('button', { name: '周视图', exact: true }).click();
  const source = page.locator('[data-task-day-id]').filter({ hasText: title }).first();
  const group = await groupDetails(page, source);
  const target = page.locator('[data-testid="calendar-day"]').filter({ has: page.getByText('11-03') }).first();
  await source.dragTo(target.locator('header'));
  await expectSaved(page, data => data.blocks.filter(block => group.ids.includes(block.id)).every(block => block.date === '2026-11-03'));
  await expect(target.locator(`[data-task-day-id="${group.taskId}:2026-11-03"]`)).toBeVisible();
  expect((await readPlan(page)).blocks.filter(block => group.ids.includes(block.id)).reduce((sum, block) => sum + block.duration_minutes, 0)).toBe(group.planned);
});

test('creates a fixed event and retains it after refresh', async ({ page }) => {
  await page.goto('/calendar');
  await page.getByRole('button', { name: '创建固定事件', exact: true }).click();
  const editor = page.getByRole('dialog', { name: '创建固定事件', exact: true });
  await editor.getByLabel('事件名称', { exact: true }).fill('端到端测试 · 不可移动模拟考试');
  await editor.getByLabel('开始时间', { exact: true }).fill('19:00');
  await editor.getByLabel('类型', { exact: true }).selectOption('exam');
  await editor.getByRole('button', { name: '保存固定事件', exact: true }).click();
  await expect(editor).toBeHidden();
  await expectSaved(page, data => data.fixed_events.some(event => event.title === '端到端测试 · 不可移动模拟考试' && event.kind === 'exam'));
  await page.reload();
  await expect(page.getByText(/端到端测试 · 不可移动模拟考试/).first()).toBeVisible();
});

test('shows task durations without clock times and local Demo status; every route fits the viewport', async ({ page }, testInfo) => {
  const failures: string[] = [];
  page.on('pageerror', error => failures.push(error.message));
  for (const route of ['/', '/calendar', '/tasks', '/progress', '/settings']) {
    await page.goto(route);
    await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
    await assertNoHorizontalOverflow(page, route);
    if (route === '/' || route === '/calendar') {
      const rows = page.getByTestId('schedule-block');
      expect(await rows.count()).toBeGreaterThan(0);
      for (const text of await rows.allTextContents()) expect(text).not.toMatch(/\b\d{2}:\d{2}\b/);
      await expect(page.getByRole('button', { name: /开始计时|暂停计时|完成计时/ })).toHaveCount(0);
    }
    await page.screenshot({ path: testInfo.outputPath(`${route === '/' ? 'today' : route.slice(1)}.png`), fullPage: true });
  }
  await expect(page.getByText(/本地 Demo/).first()).toBeVisible();
  await expect(page.getByText(/VITE_SUPABASE_URL/).first()).toBeVisible();
  expect(failures).toEqual([]);
});

test('exports real learning records and restores the complete backup after changes', async ({ page }, testInfo) => {
  await recordActual(page, page.getByTestId('schedule-block').first(), 45);
  const before = await readPlan(page);
  await page.goto('/settings');
  const downloadPromise = page.waitForEvent('download');
  await page.getByRole('button', { name: '导出本地数据', exact: true }).click();
  const download = await downloadPromise;
  const backupPath = testInfo.outputPath('study-plan-backup.json');
  await download.saveAs(backupPath);
  const exported = JSON.parse(await readFile(backupPath, 'utf8')) as PlannerData;
  expect(exported).toEqual(before);
  await page.getByLabel('目标方向', { exact: true }).fill('端到端测试 · 临时方向');
  await expectSaved(page, data => data.profile.target_program === '端到端测试 · 临时方向');
  await page.getByLabel('恢复数据', { exact: true }).setInputFiles(backupPath);
  await expectSaved(page, data => data.profile.target_program === before.profile.target_program);
  expect(await readPlan(page)).toEqual(before);
  await page.goto('/');
  await expect(page.getByTestId('today-completed-minutes')).toHaveAttribute('data-minutes', '45');
});

test('mobile manages the complete day with manual actual records, date changes and keyboard controls', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'mobile', 'Dedicated mobile workflow; desktop operations have their own tests.');
  const row = page.getByTestId('schedule-block').last();
  await row.scrollIntoViewIfNeeded();
  await expect(row).toBeVisible();
  const group = await groupDetails(page, row);
  await recordActual(page, row, 30);
  await expect(page.getByTestId('today-completed-minutes')).toHaveAttribute('data-minutes', '30');
  await expect(page.getByText('剩余时长', { exact: true })).toBeVisible();
  await recordActual(page, row, group.planned, true);
  await expect(row).toHaveClass(/done/);
  await row.getByRole('button', { name: /^记录实际用时：/ }).click();
  await page.keyboard.press('Escape');
  await expect(page.getByRole('dialog')).toHaveCount(0);
  await expect(row.getByRole('button', { name: /^记录实际用时：/ })).toBeVisible();
  const english = await firstEnglishRow(page);
  await english.getByRole('button', { name: /^调整日期：/ }).click();
  const editor = page.getByRole('dialog', { name: '调整事项日期', exact: true });
  await editor.getByLabel('安排日期', { exact: true }).fill(TOMORROW);
  await editor.getByRole('button', { name: '保存日期', exact: true }).click();
  await expect(editor).toBeHidden();
  await expect(english).toHaveCount(0);
  await assertNoHorizontalOverflow(page, 'mobile today');
  await page.reload();
  await expect(page.getByTestId('today-completed-minutes')).toHaveAttribute('data-minutes', String(group.planned));
});

