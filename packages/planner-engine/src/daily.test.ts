import { describe, expect, it } from "vitest";
import {
  availableDailyMinutes,
  confirmReplan,
  fixedEventMinutesForDate,
  generateReplanPreview,
  undoLastReplan,
  validateBlockPlacement,
} from "./engine";
import type {
  FixedEvent,
  PlannerData,
  Profile,
  ReplanInput,
  ScheduleBlock,
  Task,
  TimeLog,
} from "./types";

const today = "2026-10-14";
const date = "2026-10-15";
const timestamp = "2026-10-14T08:00:00.000Z";
const profile: Profile = {
  user_id: "daily-user",
  planning_mode: "daily",
  target_school: "上海交通大学",
  target_program: "408",
  exam_date: "2027-12-25",
  exam_end_date: "2027-12-26",
  daily_limit_minutes: 480,
  buffer_minutes: 30,
  granularity_minutes: 30,
  study_start_minute: 480,
  study_end_minute: 1200,
  foundation: "3.4",
};
const task = (id = "math", overrides: Partial<Task> = {}): Task => ({
  id,
  user_id: profile.user_id,
  tag_ids: [],
  title: id,
  estimated_minutes: 600,
  completed_minutes: 0,
  priority: 3,
  deadline: "2026-10-28",
  is_fixed: false,
  status: "not_started",
  created_at: timestamp,
  updated_at: timestamp,
  ...overrides,
});
const block = (
  id: string,
  overrides: Partial<ScheduleBlock> = {},
): ScheduleBlock => ({
  id,
  user_id: profile.user_id,
  task_id: "math",
  date,
  start_minute: 0,
  duration_minutes: 30,
  actual_minutes: 0,
  is_fixed: false,
  status: "planned",
  created_at: timestamp,
  updated_at: timestamp,
  ...overrides,
});
const event = (
  id: string,
  overrides: Partial<FixedEvent> = {},
): FixedEvent => ({
  id,
  user_id: profile.user_id,
  title: id,
  date,
  start_minute: 480,
  duration_minutes: 60,
  kind: "course",
  repeat: "none",
  created_at: timestamp,
  updated_at: timestamp,
  ...overrides,
});
const input = (overrides: Partial<ReplanInput> = {}): ReplanInput => ({
  tasks: [task()],
  blocks: [],
  profile: { ...profile },
  logs: [],
  fixed_events: [],
  today,
  mode: "unfinished",
  ...overrides,
});
const data = (source: ReplanInput): PlannerData => ({
  version: 1,
  profile: source.profile,
  tasks: source.tasks,
  blocks: source.blocks,
  logs: source.logs,
  fixed_events: source.fixed_events,
  tags: [],
  phases: [],
  replan_runs: [],
});
const total = (blocks: ScheduleBlock[]) =>
  blocks.reduce((sum, item) => sum + item.duration_minutes, 0);

describe("每日任务与时长模式", () => {
  it("未设置 planning_mode 的旧数据默认使用每日计划，不受同一开始时间限制", () => {
    const source = data(
      input({
        profile: { ...profile, planning_mode: undefined },
        blocks: [block("a")],
      }),
    );
    expect(validateBlockPlacement(source, block("b"))).toBeNull();
  });

  it("不要求对齐开始分钟、不设开始结束时段、不验证学习块与事件的时间交叉", () => {
    const source = data(
      input({
        profile: { ...profile, study_start_minute: 600, study_end_minute: 600 },
        blocks: [block("a", { start_minute: 510 })],
        fixed_events: [event("course", { start_minute: 500 })],
      }),
    );
    expect(
      validateBlockPlacement(source, block("b", { start_minute: 511 })),
    ).toBeNull();
    expect(
      validateBlockPlacement(source, block("c", { start_minute: 1439 })),
    ).toBeNull();
    expect(
      validateBlockPlacement(source, block("d", { start_minute: -1 })),
    ).toBeNull();
  });

  it("遗留课程和休息事件不扣减当天容量，学习事项仍受每日上限限制", () => {
    const events = [
      event("course", { start_minute: 480, duration_minutes: 120 }),
      event("rest", { start_minute: 540, duration_minutes: 120, kind: "rest" }),
      event("duplicate", { start_minute: 480, duration_minutes: 120 }),
    ];
    expect(fixedEventMinutesForDate(events, date)).toBe(0);
    expect(availableDailyMinutes(profile, events, date)).toBe(450);
    const source = data(
      input({
        tasks: [task(), task("english")],
        blocks: [block("math", { duration_minutes: 240 })],
        fixed_events: events,
      }),
    );
    expect(
      validateBlockPlacement(
        source,
        block("fits", { task_id: "english", duration_minutes: 210 }),
      ),
    ).toBeNull();
    expect(
      validateBlockPlacement(
        source,
        block("too-much", { task_id: "english", duration_minutes: 240 }),
      ),
    ).toContain("每日上限");
  });

  it("遗留每日和每周重复事件在所有日期均不生效", () => {
    const events = [
      event("daily", {
        repeat: "daily",
        start_minute: 480,
        duration_minutes: 60,
      }),
      event("weekly", {
        repeat: "weekly",
        start_minute: 510,
        duration_minutes: 90,
      }),
    ];
    expect(fixedEventMinutesForDate(events, today)).toBe(0);
    expect(fixedEventMinutesForDate(events, date)).toBe(0);
    expect(fixedEventMinutesForDate(events, "2026-10-16")).toBe(0);
    expect(fixedEventMinutesForDate(events, "2026-10-22")).toBe(0);
  });

  it("遗留正式考试不阻止当天重排，兼容数据保持原状", () => {
    const events = [
      event("official", { duration_minutes: 480, kind: "official_exam" }),
    ];
    const source = input({
      blocks: [block("today", { date: today, duration_minutes: 60 })],
      fixed_events: events,
    });
    const preview = generateReplanPreview(source);
    expect(preview.after.map((item) => item.date)).toEqual([
      date,
      date,
    ]);
    expect(source.fixed_events).toEqual(events);
    expect(availableDailyMinutes(profile, events, date)).toBe(450);
  });

  it("找每日容量而不是时段空隙，即便遗留学习窗口为空也可重排", () => {
    const source = input({
      profile: { ...profile, study_start_minute: 1200, study_end_minute: 480 },
      blocks: [block("today", { date: today, duration_minutes: 90 })],
    });
    const preview = generateReplanPreview(source);
    expect(preview.conflicts).toHaveLength(0);
    expect(preview.after).toHaveLength(3);
    expect(total(preview.after)).toBe(90);
    expect(
      preview.after.every(
        (item) => item.date === date && item.start_minute === 0,
      ),
    ).toBe(true);
  });

  it("当天120分钟完成60分钟，整条记录受保护且确认撤销不改变记录", () => {
    const actual: TimeLog = {
      id: "log",
      user_id: profile.user_id,
      task_id: "math",
      block_id: "today",
      date: today,
      minutes: 60,
      source: "manual",
      started_at: timestamp,
      ended_at: timestamp,
    };
    const source = input({
      tasks: [task("math", { estimated_minutes: 120, completed_minutes: 60 })],
      blocks: [
        block("today", {
          date: today,
          duration_minutes: 120,
          actual_minutes: 60,
        }),
      ],
      logs: [actual],
    });
    const preview = generateReplanPreview(source);
    expect(preview.after).toEqual(source.blocks);
    expect(preview.changes).toEqual([]);
    expect(preview.postponed).toEqual([]);
    expect(undoLastReplan(confirmReplan(data(source), preview)).blocks).toEqual(
      source.blocks,
    );
  });

  it("所有事项共同受每日450分钟容量限制", () => {
    const preview = generateReplanPreview(
      input({
        tasks: [task(), task("english")],
        blocks: [
          block("math", { date: today, duration_minutes: 600 }),
          block("english", {
            task_id: "english",
            date: today,
            duration_minutes: 600,
          }),
        ],
      }),
    );
    expect(total(preview.after)).toBe(1200);
    for (const day of new Set(preview.after.map((item) => item.date))) {
      expect(
        total(preview.after.filter((item) => item.date === day)),
      ).toBeLessThanOrEqual(450);
    }
  });

  it("遗留固定事件不制造截止日期前的虚假容量冲突", () => {
    const preview = generateReplanPreview(
      input({
        tasks: [task("math", { estimated_minutes: 120, deadline: date })],
        blocks: [block("today", { date: today, duration_minutes: 120 })],
        fixed_events: [event("blocked", { duration_minutes: 390 })],
      }),
    );
    expect(total(preview.after)).toBe(120);
    expect(preview.conflicts).toEqual([]);
    expect(preview.after.every((item) => item.date === date)).toBe(true);
  });

  it("拖到另一天仍校验截止日期和日期容量，固定与已完成块仍不可换日期", () => {
    const fixed = block("fixed", { is_fixed: true });
    const completed = block("completed", {
      status: "completed",
      actual_minutes: 30,
    });
    const source = data(
      input({
        tasks: [task("math", { deadline: date })],
        blocks: [fixed, completed],
      }),
    );
    expect(
      validateBlockPlacement(
        source,
        { ...fixed, date: "2026-10-16" },
        fixed.id,
      ),
    ).toContain("不可移动");
    expect(
      validateBlockPlacement(
        source,
        { ...completed, date: "2026-10-16" },
        completed.id,
      ),
    ).toContain("不可移动");
    expect(
      validateBlockPlacement(source, block("late", { date: "2026-10-16" })),
    ).toContain("截止日期");
  });

  it("超额完成只从未来7天提前，遗留事件不扣减当天容量", () => {
    const future = block("near", { date: "2026-10-21", duration_minutes: 60 });
    const far = block("far", { date: "2026-10-22", duration_minutes: 60 });
    const preview = generateReplanPreview(
      input({
        mode: "overcompleted",
        excess_minutes: 60,
        blocks: [future, far],
        fixed_events: [
          event("today-event", { date: today, duration_minutes: 420 }),
        ],
      }),
    );
    expect(total(preview.after.filter((item) => item.date === today))).toBe(60);
    expect(total(preview.after)).toBe(120);
    expect(preview.after.find((item) => item.id === far.id)).toEqual(far);
  });

  it("跨日和相接的遗留事件均不占学习容量", () => {
    const events = [
      event("before", { start_minute: -30, duration_minutes: 60 }),
      event("adjacent", { start_minute: 30, duration_minutes: 60 }),
      event("late", { start_minute: 1410, duration_minutes: 60 }),
    ];
    expect(fixedEventMinutesForDate(events, date)).toBe(0);
  });
});
