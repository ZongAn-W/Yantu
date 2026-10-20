#!/usr/bin/env node
/**
 * Generate a wholly fictional study plan for the 2026-10-19 calendar preview.
 * Usage: node tools/create-demo-plan.mjs --user-id <uuid> --output <new-file.json>
 * This script has no network access, creates no account, and never overwrites a file.
 */
import { randomUUID } from 'node:crypto';
import { writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const args = process.argv.slice(2);
const options = new Map();
for (let index = 0; index < args.length; index += 2) {
  if (args[index] === '--help') {
    console.log('Usage: node tools/create-demo-plan.mjs --user-id <uuid> --output <new-file.json>');
    process.exit(0);
  }
  const key = args[index];
  const value = args[index + 1];
  if (!['--user-id', '--output'].includes(key) || !value || options.has(key)) {
    throw new Error('Expected --user-id <uuid> and --output <new-file.json>.');
  }
  options.set(key, value);
}
const userId = options.get('--user-id');
if (!userId || !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(userId)) {
  throw new Error('--user-id must be a valid UUID.');
}
if (!options.get('--output')) throw new Error('--output is required.');
const output = resolve(options.get('--output'));
const today = '2026-10-19';
const cycleStart = '2026-10-12';
const cycleEnd = '2026-11-08';
const created = '2026-10-11T10:00:00+08:00';
const updated = '2026-10-19T10:30:00+08:00';
const weeklyMinutes = { 0: 180, 1: 210, 2: 180, 3: 240, 4: 150, 5: 180, 6: 300 };
const courseSpecs = [
  ['calculus', '高数', '#4565c7', 3],
  ['english', '英语', '#2c927c', 2],
  ['data', '数据结构', '#cf8641', 3],
  ['probability', '概率统计', '#9464b8', 2],
];
const subjects = courseSpecs.map(([key, name, color, priority]) => ({
  id: randomUUID(), user_id: userId, name, color, priority, key,
}));
const byCourse = new Map(subjects.map(subject => [subject.key, subject]));
const taskSpecs = [
  ['c_limit', 'calculus', '数列极限与两个重要极限：例题及基础训练', true],
  ['e_2018', 'english', '2018 年英语阅读 Text 1–2：精读与长难句', true],
  ['d_list', 'data', '线性表与链表：核心例题及手写实现', true],
  ['p_basic', 'probability', '概率公理与条件概率：基础题训练', true],
  ['c_deriv', 'calculus', '导数与微分：计算方法及错题复盘'],
  ['e_2019', 'english', '2019 年英语阅读 Text 1–4：限时与精读'],
  ['d_stack', 'data', '栈与队列：循环队列和括号匹配'],
  ['p_dist', 'probability', '随机变量与分布：典型题第一轮'],
  ['c_integral', 'calculus', '一元积分：换元、分部积分与应用'],
  ['e_2020', 'english', '2020 年英语阅读 Text 1–4：限时与复盘'],
  ['d_tree', 'data', '树与二叉树：遍历、线索树及应用'],
  ['p_expect', 'probability', '期望与方差：性质、计算及综合题'],
  ['c_series', 'calculus', '无穷级数：判别方法与幂级数'],
  ['e_write', 'english', '英语应用文：邀请信、建议信与修改'],
  ['d_graph', 'data', '图：遍历、最小生成树和最短路径'],
  ['p_estimate', 'probability', '参数估计：矩估计与最大似然'],
  ['c_review', 'calculus', '高数阶段检测：限时套题与错题归纳'],
  ['e_review', 'english', '英语阶段复盘：易错词义与长难句'],
  ['d_sort', 'data', '查找与排序：算法比较和代码复写'],
  ['p_review', 'probability', '概率统计阶段检测：综合题与复盘'],
  ['e_history', 'english', '核心词汇第一组：词义辨析与例句', true, true],
  ['d_history', 'data', '算法复杂度：时间与空间复杂度小测', true, true],
];
const tasksByKey = new Map(taskSpecs.map(([key, course, title, completed, historical]) => [key, {
  id: randomUUID(), user_id: userId, subject_id: byCourse.get(course).id,
  title, description: '虚构演示数据。完成标准：完成对应知识点、例题和练习，并整理易错点。',
  estimated_minutes: 0, completed_minutes: 0, priority: byCourse.get(course).priority,
  deadline: historical ? '2026-10-11' : cycleEnd,
  deadline_kind: 'deadline', earliest_date: historical ? '2026-10-01' : cycleStart,
  is_fixed: false, status: completed ? 'completed' : 'not_started',
  created_at: historical ? '2026-10-01T09:00:00+08:00' : created,
  updated_at: updated,
}]));

// Each row is [task key, planned minutes, scheduled minutes already studied].
// Omitted actual values are zero. Past, current, and future loads intentionally vary.
const schedule = {
  '2026-10-12': [['c_limit', 90, 90], ['e_2018', 45, 45], ['p_basic', 45, 45]],
  '2026-10-13': [['c_limit', 90, 90], ['d_list', 90, 90]],
  '2026-10-14': [['e_2018', 45, 45], ['p_basic', 75, 75], ['d_list', 60, 60]],
  '2026-10-15': [['c_deriv', 90, 75], ['d_list', 60, 60]],
  '2026-10-16': [['c_deriv', 90, 90], ['e_2019', 60, 45]],
  '2026-10-17': [['d_stack', 120, 100], ['p_dist', 90, 60], ['e_2019', 60, 60]],
  '2026-10-18': [['c_deriv', 60, 45], ['p_dist', 60, 45], ['e_2019', 45, 45]],
  '2026-10-19': [['c_deriv', 90, 35], ['e_2019', 45, 45], ['d_stack', 60]],
  '2026-10-20': [['c_deriv', 90], ['e_2019', 45], ['p_dist', 45]],
  '2026-10-21': [['d_stack', 90], ['p_dist', 60], ['e_2019', 45]],
  '2026-10-22': [['c_deriv', 60], ['d_stack', 60], ['p_dist', 30]],
  '2026-10-23': [['d_tree', 90], ['e_2020', 45], ['p_dist', 45]],
  '2026-10-24': [['c_integral', 120], ['d_tree', 90], ['e_2020', 45]],
  '2026-10-25': [['p_expect', 90], ['e_2020', 45], ['c_integral', 45]],
  '2026-10-26': [['c_integral', 90], ['d_tree', 60], ['e_2020', 45]],
  '2026-10-27': [['p_expect', 60], ['e_2020', 45], ['c_integral', 60]],
  '2026-10-28': [['d_tree', 90], ['c_integral', 90], ['e_2020', 45]],
  '2026-10-29': [['p_expect', 60], ['d_tree', 60], ['e_write', 30]],
  '2026-10-30': [['c_series', 90], ['p_expect', 45], ['e_write', 45]],
  '2026-10-31': [['d_graph', 120], ['c_series', 90], ['e_write', 45]],
  '2026-11-01': [['p_estimate', 90], ['d_graph', 60], ['e_write', 30]],
  '2026-11-02': [['c_series', 90], ['e_write', 45], ['d_graph', 60]],
  '2026-11-03': [['p_estimate', 60], ['c_series', 60], ['e_write', 45]],
  '2026-11-04': [['d_sort', 90], ['c_review', 90], ['e_review', 45]],
  '2026-11-05': [['p_review', 60], ['d_sort', 60], ['e_review', 30]],
  '2026-11-06': [['c_review', 90], ['p_review', 45], ['e_review', 45]],
  '2026-11-07': [['d_sort', 120], ['c_review', 90], ['e_review', 45]],
  '2026-11-08': [['p_review', 90], ['d_sort', 60], ['e_review', 30]],
};

function stamp(date, minute) {
  const hour = String(Math.floor(minute / 60)).padStart(2, '0');
  const min = String(minute % 60).padStart(2, '0');
  return `${date}T${hour}:${min}:00+08:00`;
}
const blocks = [];
const logs = [];
function addLog(task, date, minute, minutes, relation, blockId = null, quota = 0) {
  if (!minutes) return;
  logs.push({
    id: randomUUID(), user_id: userId, task_id: task.id, block_id: blockId, date, minutes,
    started_at: stamp(date, minute), ended_at: stamp(date, minute + minutes),
    source: 'timer', relation, session_id: randomUUID(), quota_minutes: quota,
  });
  task.completed_minutes += minutes;
}
for (const [date, rows] of Object.entries(schedule)) {
  let minute = 8 * 60;
  for (const [key, planned, actual = 0] of rows) {
    const task = tasksByKey.get(key);
    const block = {
      id: randomUUID(), user_id: userId, task_id: task.id, date, start_minute: minute,
      duration_minutes: planned, actual_minutes: actual, is_fixed: false,
      status: actual === planned ? 'completed' : 'planned',
      completion_status: actual === planned ? 'completed' : actual > 0 ? 'partial' : 'not_started',
      created_at: created, updated_at: actual > 0 ? stamp(date, minute + actual) : created,
    };
    blocks.push(block);
    task.estimated_minutes += planned;
    task.deadline = date;
    addLog(task, date, minute, actual, 'scheduled', block.id, planned);
    // Today's fictional sessions end at 08:35 and 10:30 Shanghai time.
    minute += planned + 15;
  }
}
addLog(tasksByKey.get('c_limit'), '2026-10-13', 19 * 60, 15, 'extra');
addLog(tasksByKey.get('d_list'), '2026-10-14', 19 * 60 + 30, 20, 'extra');
addLog(tasksByKey.get('p_dist'), '2026-10-18', 16 * 60, 15, 'extra');
for (const [key, minutes] of [['e_history', 90], ['d_history', 60]]) {
  const task = tasksByKey.get(key);
  task.estimated_minutes = minutes;
  addLog(task, '2026-10-10', key === 'e_history' ? 9 * 60 : 14 * 60, minutes, 'extra');
}
const tasks = [...tasksByKey.values()];
for (const task of tasks) {
  const scheduledDates = blocks.filter(block => block.task_id === task.id).map(block => block.date).sort();
  if (scheduledDates.length > 0) task.earliest_date = scheduledDates[0];
  if (task.status !== 'completed' && task.completed_minutes > 0) task.status = 'in_progress';
  task.planning = { activity: { kind: 'finite' } };
}
const phaseSpecs = [
  ['2026-10-12', '2026-10-18', '基础梳理', '巩固极限、链表与概率基础，完成首轮阅读精读。'],
  ['2026-10-19', '2026-10-25', '专题推进', '推进导数、栈队列、随机变量和阅读训练。'],
  ['2026-10-26', '2026-11-01', '综合强化', '衔接积分与级数，练习树、图及期望计算。'],
  ['2026-11-02', '2026-11-08', '阶段检测', '通过限时练习和错题复盘检查本轮掌握情况。'],
];
const phases = phaseSpecs.map(([start, end, title, description]) => ({
  id: randomUUID(), title, start, end, description,
}));
const plan = {
  version: 1,
  profile: {
    user_id: userId, planning_mode: 'daily',
    goal_text: '四周巩固高数、英语、数据结构与概率统计，完成阶段练习和错题复盘。',
    goal_type: 'self_study', goal_subtype: '四周基础巩固',
    target_date: cycleEnd, target_date_confirmed: true,
    plan_start_date: cycleStart, plan_end_date: cycleEnd,
    weekly_minutes: weeklyMinutes, capacity_basis: 'net',
    weekly_baseline_minutes: Object.values(weeklyMinutes).reduce((sum, value) => sum + value, 0),
    week_capacity_overrides: {}, date_capacity_overrides: {}, constraints: '',
    target_school: '', target_program: '', exam_date: '', exam_end_date: '',
    daily_limit_minutes: 240, granularity_minutes: 15, buffer_minutes: 0,
    subject_limit_minutes: 150, study_start_minute: 480, study_end_minute: 1260,
    foundation: '虚构演示：已学习各课程基础概念，通过专题练习查漏补缺；工作日以短时学习为主，周六可安排较长练习。',
  },
  subjects: subjects.map(({ key, ...subject }) => subject),
  tasks, blocks, logs, fixed_events: [], replan_runs: [], phases,
  planning: {
    version: 1, prompt_version: 'fictional-demo-v1', rules_version: 'fictional-demo-v1',
    mode: 'full', detail_days: 28, rolling: false, detailed_until: cycleEnd,
    route: phases.map(phase => ({
      id: phase.id, title: phase.title, start_date: phase.start, end_date: phase.end,
      item_ids: [...new Set(blocks.filter(block => block.date >= phase.start && block.date <= phase.end).map(block => block.task_id))],
      outcome: phase.description, check: '完成专题练习，记录错题原因并完成一次复做。',
    })),
    milestones: [], assumptions: ['全部内容均为演示而虚构，不代表真实用户的学习记录。'],
    risks: [], uncovered: [], needs_review: false,
  },
};

// Check the dataset's own invariants before the exclusive write.
for (const task of tasks) {
  const total = logs.filter(log => log.task_id === task.id).reduce((sum, log) => sum + log.minutes, 0);
  if (task.completed_minutes !== total || task.estimated_minutes <= 0) throw new Error('Invalid task aggregate.');
  if (task.status === 'completed' && total < task.estimated_minutes) throw new Error('Completed task has unfinished work.');
}
for (const [date, rows] of Object.entries(schedule)) {
  const planned = rows.reduce((sum, row) => sum + row[1], 0);
  const weekday = new Date(`${date}T00:00:00Z`).getUTCDay();
  if (planned > weeklyMinutes[weekday]) throw new Error(`Schedule exceeds capacity on ${date}.`);
}
if (logs.some(log => log.date > today)) throw new Error('Demo contains future learning logs.');
await writeFile(output, `${JSON.stringify(plan, null, 2)}\n`, { encoding: 'utf8', flag: 'wx' });
console.log(JSON.stringify({
  output, today, cycle_start: cycleStart, cycle_end: cycleEnd,
  subjects: plan.subjects.length, tasks: tasks.length, blocks: blocks.length, logs: logs.length,
  completed_tasks: tasks.filter(task => task.status === 'completed').length,
  planned_minutes: blocks.reduce((sum, block) => sum + block.duration_minutes, 0),
  learned_minutes: logs.reduce((sum, log) => sum + log.minutes, 0),
  today_planned_minutes: blocks.filter(block => block.date === today).reduce((sum, block) => sum + block.duration_minutes, 0),
  today_learned_minutes: logs.filter(log => log.date === today).reduce((sum, log) => sum + log.minutes, 0),
}));
