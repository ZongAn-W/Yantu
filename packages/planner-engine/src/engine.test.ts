import { describe, expect, it } from "vitest";
import {
  addDays,
  confirmReplan,
  dateToday,
  eventOccursOn,
  generateReplanPreview,
  remainingTaskMinutes,
  taskCompletedMinutes,
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

const TODAY = "2026-10-13";
const timestamp = "2026-10-13T08:00:00.000Z";
const profile: Profile = {
  user_id: "user-1",
  planning_mode: "timed",
  target_school: "上海交通大学",
  target_program: "计算机 408",
  exam_date: "2027-12-25",
  exam_end_date: "2027-12-26",
  daily_limit_minutes: 480,
  granularity_minutes: 30,
  buffer_minutes: 30,
  subject_limit_minutes: 240,
  study_start_minute: 480,
  study_end_minute: 1200,
  foundation: "3.4",
};
const task = (id: string, overrides: Partial<Task> = {}): Task => ({
  id,
  user_id: profile.user_id,
  subject_id: "math",
  title: `任务 ${id}`,
  estimated_minutes: 120,
  completed_minutes: 0,
  priority: 3,
  deadline: "2026-10-27",
  is_fixed: false,
  status: "not_started",
  created_at: timestamp,
  updated_at: timestamp,
  ...overrides,
});
const block = (
  id: string,
  task_id = "math",
  overrides: Partial<ScheduleBlock> = {},
): ScheduleBlock => ({
  id,
  user_id: profile.user_id,
  task_id,
  date: TODAY,
  start_minute: 480,
  duration_minutes: 30,
  actual_minutes: 0,
  is_fixed: false,
  status: "planned",
  created_at: timestamp,
  updated_at: timestamp,
  ...overrides,
});
const log = (minutes: number, overrides: Partial<TimeLog> = {}): TimeLog => ({
  id: "log-1",
  user_id: profile.user_id,
  task_id: "math",
  block_id: "today",
  date: TODAY,
  minutes,
  started_at: timestamp,
  ended_at: timestamp,
  source: "manual",
  ...overrides,
});
const event = (overrides: Partial<FixedEvent> = {}): FixedEvent => ({
  id: "event-1",
  user_id: profile.user_id,
  title: "固定课程",
  date: "2026-10-14",
  start_minute: 480,
  duration_minutes: 120,
  kind: "course",
  repeat: "none",
  created_at: timestamp,
  updated_at: timestamp,
  ...overrides,
});
const input = (overrides: Partial<ReplanInput> = {}): ReplanInput => ({
  tasks: [task("math")],
  blocks: [block("today", "math", { duration_minutes: 120 })],
  logs: [],
  fixed_events: [],
  profile: { ...profile },
  today: TODAY,
  mode: "unfinished",
  ...overrides,
});
const data = (source: ReplanInput): PlannerData => ({
  version: 1,
  profile: source.profile,
  subjects: [],
  tasks: source.tasks,
  blocks: source.blocks,
  logs: source.logs,
  fixed_events: source.fixed_events,
  replan_runs: [],
  phases: [],
});
const planned = (blocks: ScheduleBlock[]) =>
  blocks.filter((item) => item.status === "planned");
const sum = (blocks: ScheduleBlock[]) =>
  blocks.reduce((total, item) => total + item.duration_minutes, 0);

describe("archived task history", () => {
  it.each(["unfinished", "overcompleted"] as const)(
    "%s skips archived work while preserving fixed, completed and actual-used history",
    (mode) => {
      const history = [
        block("past", "math", { date: addDays(TODAY, -1) }),
        block("actual", "math", { actual_minutes: 20 }),
        block("fixed", "math", { is_fixed: true, date: addDays(TODAY, 1) }),
        block("done", "math", { status: "completed", date: addDays(TODAY, 1) }),
      ];
      const source = input({
        mode,
        excess_minutes: 60,
        tasks: [task("math", { status: "archived", completed_minutes: 120 })],
        blocks: [...history, block("unstarted"), block("future", "math", { date: addDays(TODAY, 1) })],
        logs: [log(20, { block_id: "actual" })],
      });
      const original = data(source);
      expect(validateBlockPlacement(original, block("new"))).toBe("已归档事项不可安排");
      const preview = generateReplanPreview(source);
      expect(preview.after).toEqual(history);
      expect(preview.conflicts).toEqual([]);
      const confirmed = confirmReplan(original, preview);
      expect(confirmed.tasks[0].status).toBe("archived");
      expect(confirmed.logs).toEqual(original.logs);
      expect(undoLastReplan(confirmed).tasks[0].status).toBe("archived");
    },
  );
});

describe("保守重排", () => {
  it("120分钟完成60分钟后保护整条计时安排，不改写或重复预留剩余量", () => {
    const source = input({
      tasks: [task("math", { completed_minutes: 60, status: "in_progress" })],
      blocks: [
        block("today", "math", { duration_minutes: 120, actual_minutes: 60 }),
      ],
      logs: [log(60)],
    });
    const preview = generateReplanPreview(source);
    expect(preview.after).toEqual(source.blocks);
    expect(preview.changes).toEqual([]);
    expect(preview.postponed).toEqual([]);
  });

  it("只改变未来14天窗口中的量，不将长期任务全部塞入窗口", () => {
    const outside = block("far", "math", {
      date: "2026-11-01",
      duration_minutes: 120,
    });
    const preview = generateReplanPreview(
      input({
        tasks: [
          task("math", { estimated_minutes: 10_000, deadline: "2027-12-25" }),
        ],
        blocks: [block("today"), outside],
      }),
    );
    expect(preview.after.find((item) => item.id === "far")).toEqual(outside);
    expect(
      sum(
        preview.after.filter(
          (item) => item.date > TODAY && item.date <= addDays(TODAY, 14),
        ),
      ),
    ).toBe(30);
    expect(
      preview.changes.every(
        (change) => !change.before || change.before.id !== "far",
      ),
    ).toBe(true);
  });

  it("每天学习时长不超过8小时，并保留30分钟机动时间", () => {
    const tasks = [
      task("math", { estimated_minutes: 300 }),
      task("english", { estimated_minutes: 300, subject_id: "english" }),
    ];
    const preview = generateReplanPreview(
      input({
        tasks,
        blocks: [
          block("m", "math", { duration_minutes: 300 }),
          block("e", "english", { duration_minutes: 300, start_minute: 780 }),
        ],
      }),
    );
    for (const date of new Set(planned(preview.after).map((item) => item.date)))
      expect(
        sum(planned(preview.after).filter((item) => item.date === date)),
      ).toBeLessThanOrEqual(450);
    expect(sum(planned(preview.after))).toBe(600);
  });

  it("配置高于8小时或机动时间少于30分钟，也不能突破硬上限", () => {
    const source = input({
      profile: { ...profile, daily_limit_minutes: 1200, buffer_minutes: 0 },
      tasks: [
        task("math", { estimated_minutes: 500, subject_id: "math" }),
        task("cs", { estimated_minutes: 500, subject_id: "cs" }),
      ],
      blocks: [
        block("m", "math", { duration_minutes: 500 }),
        block("c", "cs", { duration_minutes: 500 }),
      ],
    });
    const preview = generateReplanPreview(source);
    for (const date of new Set(preview.after.map((item) => item.date)))
      expect(
        sum(preview.after.filter((item) => item.date === date)),
      ).toBeLessThanOrEqual(450);
  });

  it("同一科目每天最多4小时", () => {
    const preview = generateReplanPreview(
      input({
        tasks: [task("math", { estimated_minutes: 600 })],
        blocks: [block("m", "math", { duration_minutes: 600 })],
      }),
    );
    for (const date of new Set(preview.after.map((item) => item.date)))
      expect(
        sum(preview.after.filter((item) => item.date === date)),
      ).toBeLessThanOrEqual(240);
    expect(sum(preview.after)).toBe(600);
  });

  it("固定课程、休息、正式考试和固定时间块不被覆盖", () => {
    const fixed = block("fixed", "math", {
      date: "2026-10-14",
      start_minute: 660,
      duration_minutes: 30,
      is_fixed: true,
    });
    const events = [
      event(),
      event({
        id: "rest",
        start_minute: 600,
        duration_minutes: 60,
        kind: "rest",
      }),
      event({
        id: "official",
        date: "2026-10-15",
        start_minute: 480,
        duration_minutes: 720,
        kind: "official_exam",
      }),
    ];
    const preview = generateReplanPreview(
      input({
        tasks: [task("math", { estimated_minutes: 240 })],
        blocks: [block("today", "math", { duration_minutes: 210 }), fixed],
        fixed_events: events,
      }),
    );
    expect(preview.after.find((item) => item.id === "fixed")).toEqual(fixed);
    for (const item of planned(preview.after).filter(
      (item) => !item.is_fixed,
    )) {
      expect(
        events
          .filter((evt) => eventOccursOn(evt, item.date))
          .some(
            (evt) =>
              item.start_minute < evt.start_minute + evt.duration_minutes &&
              evt.start_minute < item.start_minute + item.duration_minutes,
          ),
      ).toBe(false);
    }
    expect(preview.after.some((item) => item.date === "2026-10-15")).toBe(
      false,
    );
  });

  it("固定任务和已完成块原封不动保留", () => {
    const fixedTask = task("fixed-task", { is_fixed: true });
    const completed = block("completed", "math", {
      date: "2026-10-14",
      status: "completed",
      actual_minutes: 30,
    });
    const fixed = block("fixed-block", "fixed-task", {
      date: "2026-10-14",
      start_minute: 540,
    });
    const preview = generateReplanPreview(
      input({
        tasks: [task("math", { completed_minutes: 30 }), fixedTask],
        blocks: [completed, fixed, block("today")],
      }),
    );
    expect(preview.after.find((item) => item.id === completed.id)).toEqual(
      completed,
    );
    expect(preview.after.find((item) => item.id === fixed.id)).toEqual(fixed);
  });

  it("截止日期前容量不足时明确生成冲突，不偷排到截止日期之后", () => {
    const preview = generateReplanPreview(
      input({
        tasks: [
          task("math", { estimated_minutes: 300, deadline: "2026-10-14" }),
        ],
        blocks: [block("today", "math", { duration_minutes: 300 })],
      }),
    );
    expect(sum(preview.after)).toBe(240);
    expect(preview.conflicts).toEqual([
      expect.objectContaining({ task_id: "math", minutes: 60 }),
    ]);
    expect(preview.after.every((item) => item.date <= "2026-10-14")).toBe(true);
  });

  it("较近截止日期优先，同一截止日期下优先级高的任务优先", () => {
    const source = input({
      profile: { ...profile, daily_limit_minutes: 60 },
      tasks: [
        task("later", {
          deadline: "2026-10-15",
          priority: 3,
          estimated_minutes: 30,
        }),
        task("low", {
          deadline: "2026-10-14",
          priority: 1,
          estimated_minutes: 30,
        }),
        task("high", {
          deadline: "2026-10-14",
          priority: 3,
          estimated_minutes: 30,
        }),
      ],
      blocks: [
        block("later", "later"),
        block("low", "low"),
        block("high", "high"),
      ],
    });
    const preview = generateReplanPreview(source);
    expect(
      preview.after.find((item) => item.date === "2026-10-14")?.task_id,
    ).toBe("high");
    expect(preview.conflicts.map((item) => item.task_id)).toContain("low");
  });

  it("不会提前到任务的可开始日期之前", () => {
    const preview = generateReplanPreview(
      input({ tasks: [task("math", { earliest_date: "2026-10-20" })] }),
    );
    expect(preview.after.every((item) => item.date >= "2026-10-20")).toBe(true);
  });

  it("不足30分钟且已有计时的剩余量保留在原安排，不新增重复预算", () => {
    const preview = generateReplanPreview(
      input({
        tasks: [task("math", { estimated_minutes: 75, completed_minutes: 60 })],
        blocks: [
          block("today", "math", { duration_minutes: 75, actual_minutes: 60 }),
        ],
        logs: [log(60)],
      }),
    );
    expect(planned(preview.after).map((item) => item.duration_minutes)).toEqual(
      [75],
    );
  });

  it("已完成任务或实际日志已完成的任务不再进入待排队列", () => {
    for (const completedTask of [
      task("math", { status: "completed" }),
      task("math", { completed_minutes: 120 }),
      task("math"),
    ]) {
      const preview = generateReplanPreview(
        input({
          tasks: [completedTask],
          logs:
            completedTask.status === "completed" ||
            completedTask.completed_minutes === 120
              ? []
              : [log(180)],
        }),
      );
      const protectedHistory = completedTask.status !== "completed" && completedTask.completed_minutes !== 120;
      expect(planned(preview.after)).toHaveLength(protectedHistory ? 1 : 0);
      if (protectedHistory) expect(preview.after[0].id).toBe("today");
      expect(preview.conflicts).toHaveLength(0);
    }
  });

  it("完成时长与日志不重复相加，任务完成量上限为预计总时长", () => {
    expect(
      taskCompletedMinutes(task("math", { completed_minutes: 60 }), [log(60)]),
    ).toBe(60);
    expect(
      taskCompletedMinutes(task("math", { completed_minutes: 180 }), [
        log(180),
      ]),
    ).toBe(120);
    expect(remainingTaskMinutes(task("math"), [log(180)])).toBe(0);
  });

  it("预览不修改原始输入；取消预览无需产生任何数据写入", () => {
    const source = input();
    const initial = structuredClone(source);
    generateReplanPreview(source);
    expect(source).toEqual(initial);
  });
});

describe("超额完成后的有限提前", () => {
  it("只提前未来7天内的高优先级任务，而且最多提前超额60分钟", () => {
    const source = input({
      mode: "overcompleted",
      excess_minutes: 60,
      tasks: [
        task("math", { completed_minutes: 180, status: "completed" }),
        task("low", { priority: 1, subject_id: "english" }),
        task("high", { priority: 3, subject_id: "cs" }),
        task("far", { priority: 3, subject_id: "politics" }),
      ],
      blocks: [
        block("today", "math", {
          duration_minutes: 120,
          actual_minutes: 180,
          status: "completed",
        }),
        block("low", "low", { date: "2026-10-14", start_minute: 900 }),
        block("high", "high", {
          date: "2026-10-20",
          start_minute: 900,
          duration_minutes: 60,
        }),
        block("far", "far", {
          date: "2026-10-21",
          start_minute: 900,
          duration_minutes: 60,
        }),
      ],
      logs: [log(180)],
    });
    const preview = generateReplanPreview(source);
    expect(
      sum(planned(preview.after).filter((item) => item.date === TODAY)),
    ).toBe(60);
    expect(
      planned(preview.after)
        .filter((item) => item.date === TODAY)
        .every((item) => item.task_id === "high"),
    ).toBe(true);
    expect(preview.after.find((item) => item.id === "far")).toEqual(
      source.blocks.find((item) => item.id === "far"),
    );
    expect(preview.advanced).toEqual(["high"]);
    expect(taskCompletedMinutes(source.tasks[0], source.logs)).toBe(120);
  });

  it("提前到今天也必须遵守实际用时、机动时间及科目上限", () => {
    const preview = generateReplanPreview(
      input({
        mode: "overcompleted",
        excess_minutes: 60,
        tasks: [
          task("math", { estimated_minutes: 600, completed_minutes: 420 }),
          task("future", { subject_id: "english" }),
        ],
        blocks: [
          block("today", "math", {
            duration_minutes: 420,
            actual_minutes: 420,
            status: "completed",
          }),
          block("future", "future", {
            date: "2026-10-14",
            duration_minutes: 60,
          }),
        ],
        logs: [log(420)],
      }),
    );
    expect(
      sum(planned(preview.after).filter((item) => item.date === TODAY)),
    ).toBe(30);
    expect(
      preview.after
        .filter((item) => item.task_id === "future")
        .reduce((total, item) => total + item.duration_minutes, 0),
    ).toBe(60);
  });

  it("多个来源的提前块保持唯一ID和正确总时长", () => {
    const preview = generateReplanPreview(
      input({
        mode: "overcompleted",
        excess_minutes: 120,
        tasks: [task("math", { estimated_minutes: 180 })],
        blocks: [
          block("f1", "math", { date: "2026-10-14", duration_minutes: 60 }),
          block("f2", "math", {
            date: "2026-10-15",
            duration_minutes: 60,
            start_minute: 540,
          }),
          block("f3", "math", {
            date: "2026-10-16",
            duration_minutes: 60,
            start_minute: 600,
          }),
        ],
      }),
    );
    expect(sum(preview.after)).toBe(180);
    expect(sum(preview.after.filter((item) => item.date === TODAY))).toBe(120);
    expect(new Set(preview.after.map((item) => item.id)).size).toBe(
      preview.after.length,
    );
  });

  it("固定、已完成、尚未到开始日期的未来任务不能被提前", () => {
    const sources = [
      block("fixed", "fixed", { date: "2026-10-14", is_fixed: true }),
      block("done", "done", {
        date: "2026-10-14",
        status: "completed",
        actual_minutes: 30,
      }),
      block("not-yet", "not-yet", { date: "2026-10-15" }),
    ];
    const preview = generateReplanPreview(
      input({
        mode: "overcompleted",
        excess_minutes: 120,
        tasks: [
          task("fixed"),
          task("done"),
          task("not-yet", { earliest_date: "2026-10-15" }),
        ],
        blocks: sources,
      }),
    );
    expect(preview.after).toEqual(sources);
  });

  it("没有超额容量时不提前任务，并清理已完成任务的未执行冗余块", () => {
    const preview = generateReplanPreview(
      input({
        mode: "overcompleted",
        excess_minutes: 0,
        tasks: [task("math", { completed_minutes: 120 }), task("other")],
        blocks: [
          block("obsolete", "math", { date: "2026-10-14" }),
          block("future", "other", { date: "2026-10-14", start_minute: 600 }),
        ],
      }),
    );
    expect(preview.after).toEqual([
      block("future", "other", { date: "2026-10-14", start_minute: 600 }),
    ]);
    expect(preview.changes).toEqual([
      expect.objectContaining({ type: "deleted", block_id: "obsolete" }),
    ]);
  });
});

describe("确认、变更记录与撤销", () => {
  it("确认重排产生完整变更记录、前后快照及延期状态", () => {
    const initial = data(input());
    const preview = generateReplanPreview(input());
    const confirmed = confirmReplan(initial, preview);
    expect(confirmed.blocks).toEqual(preview.after);
    expect(confirmed.replan_runs).toHaveLength(1);
    expect(confirmed.replan_runs[0]).toMatchObject({
      status: "confirmed",
      before: initial.blocks,
      after: preview.after,
    });
    expect(
      confirmed.replan_runs[0].changes.every(
        (change) =>
          change.run_id === preview.id && change.user_id === profile.user_id,
      ),
    ).toBe(true);
    expect(confirmed.tasks[0].status).toBe("delayed");
    expect(initial.blocks).toEqual(preview.before);
  });

  it("撤销恢复原计划和任务状态，并保留计时日志", () => {
    const source = input({
      logs: [log(30)],
      tasks: [task("math", { completed_minutes: 30, status: "in_progress" })],
      blocks: [
        block("today", "math", { duration_minutes: 120, actual_minutes: 30 }),
      ],
    });
    const initial = data(source);
    const confirmed = confirmReplan(initial, generateReplanPreview(source));
    const undone = undoLastReplan(confirmed);
    expect(undone.blocks).toEqual(initial.blocks);
    expect(undone.tasks[0].status).toBe(initial.tasks[0].status);
    expect(undone.logs).toEqual(initial.logs);
    expect(undone.replan_runs[0].status).toBe("undone");
    expect(confirmed.replan_runs[0].status).toBe("confirmed");
  });

  it("计划已变化或重复确认时拒绝写入，避免覆盖多设备更新", () => {
    const source = input();
    const initial = data(source);
    const preview = generateReplanPreview(source);
    const changed = {
      ...initial,
      blocks: [...initial.blocks, block("new", "math", { date: "2026-10-25" })],
    };
    expect(() => confirmReplan(changed, preview)).toThrow("计划已发生变化");
    const confirmed = confirmReplan(initial, preview);
    expect(() => confirmReplan(confirmed, preview)).toThrow("已经确认");
    expect(() => undoLastReplan(changed)).toThrow("没有可撤销");
    expect(() => undoLastReplan({ ...confirmed, blocks: [] })).toThrow(
      "计划已被修改",
    );
  });
});

describe("日期与手动调整约束", () => {
  it("跨月、跨年、闰年日期计算准确", () => {
    expect(addDays("2027-12-31", 1)).toBe("2028-01-01");
    expect(addDays("2028-02-28", 1)).toBe("2028-02-29");
    expect(addDays("2026-10-01", -1)).toBe("2026-09-30");
    expect(dateToday(new Date(2026, 9, 13, 23, 30))).toBe(TODAY);
  });

  it("重复事件只从起始日期生效，并正确识别每周与每日重复", () => {
    expect(eventOccursOn(event({ repeat: "daily" }), TODAY)).toBe(false);
    expect(eventOccursOn(event({ repeat: "daily" }), "2026-10-15")).toBe(true);
    expect(eventOccursOn(event({ repeat: "weekly" }), "2026-10-21")).toBe(true);
    expect(eventOccursOn(event({ repeat: "weekly" }), "2026-10-20")).toBe(
      false,
    );
  });

  it("拖拽拒绝时间重叠、固定事件及每日上限，允许首尾相接", () => {
    const initial = data(
      input({
        blocks: [
          block("existing", "math", { date: "2026-10-14", start_minute: 480 }),
        ],
        fixed_events: [
          event({ start_minute: 600, duration_minutes: 60, kind: "rest" }),
        ],
      }),
    );
    expect(
      validateBlockPlacement(
        initial,
        block("candidate", "math", { date: "2026-10-14", start_minute: 480 }),
      ),
    ).toContain("已有时间块");
    expect(
      validateBlockPlacement(
        initial,
        block("candidate", "math", { date: "2026-10-14", start_minute: 510 }),
      ),
    ).toBeNull();
    expect(
      validateBlockPlacement(
        initial,
        block("candidate", "math", { date: "2026-10-14", start_minute: 600 }),
      ),
    ).toContain("固定");
    const limited = {
      ...initial,
      profile: { ...profile, daily_limit_minutes: 60 },
    };
    expect(
      validateBlockPlacement(
        limited,
        block("candidate", "math", { date: "2026-10-14", start_minute: 510 }),
      ),
    ).toContain("每日上限");
  });

  it("已完成块和固定块不可拖拽；任意块不能越过截止日期", () => {
    const fixed = block("fixed", "math", {
      date: "2026-10-14",
      is_fixed: true,
    });
    const initial = data(input({ blocks: [fixed] }));
    expect(
      validateBlockPlacement(
        initial,
        { ...fixed, date: "2026-10-15" },
        fixed.id,
      ),
    ).toContain("不可移动");
    expect(
      validateBlockPlacement(
        initial,
        block("late", "math", { date: "2026-10-28" }),
      ),
    ).toContain("截止日期");
  });
});
