import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { buildAdjustmentContext, generatePlanAdjustment, PlanAdjustmentSchema } from "./plan-adjust-ai.js";
import { PlannerDocumentSchema } from "./sync-contracts.js";

const aiConfig = vi.hoisted(() => ({
  aiApiKey: "test-key",
  aiBaseUrl: "https://ai.example.invalid",
  aiModel: "deepseek-flash",
  aiReasoningEffort: "max",
  aiSimpleReasoningEffort: "low",
  aiPlanningReasoningEffort: "high",
}));

vi.mock("./config.js", () => ({ config: aiConfig }));

const TODAY = "2026-10-18";
const OWNER = "1d4fba85-b73c-48c9-8039-fafdd77c607c";
const STAMP = "2026-10-16T12:40:00.528Z";

function fixture() {
  return PlannerDocumentSchema.parse({
    version: 1,
    profile: {
      user_id: OWNER,
      planning_mode: "daily",
      goal_text: "准备上海交通大学计算机专业考研",
      goal_type: "exam",
      goal_subtype: "考研",
      target_date: "2027-12-25",
      plan_start_date: "2026-10-01",
      plan_end_date: "2026-11-14",
      target_school: "上海交通大学",
      target_program: "计算机技术",
      foundation: "计算机专业大四，数学基础一般",
      constraints: "工作日最多 4 小时",
      daily_limit_minutes: 480,
      granularity_minutes: 30,
      buffer_minutes: 30,
      study_start_minute: 480,
      study_end_minute: 1320,
      weekly_minutes: { "0": 120, "1": 300, "2": 300, "3": 300, "4": 300, "5": 300, "6": 240 },
      capacity_basis: "net",
    },
    tags: [
      { id: "s-math", user_id: OWNER, name: "数学", color: "#4565c7" },
      { id: "s-en", user_id: OWNER, name: "英语", color: "#e8684a" },
    ],
    tasks: [
      {
        id: "t-math", user_id: OWNER, tag_ids: ["s-math"], title: "高数基础一轮",
        estimated_minutes: 12000, completed_minutes: 600, priority: 3,
        deadline: "2027-10-01", deadline_kind: "deadline", earliest_date: "2026-10-01",
        is_fixed: false, status: "in_progress", created_at: STAMP, updated_at: STAMP,
        planning: {
          workload: {
            components: [{ id: "ch", label: "章节", quantity: 100, unit: "章", minutes_per_unit: 120 }],
            source: "教材章节", confidence: "medium", calibration: "完成 3 章后校准",
          },
          activity: { kind: "finite", starts_on: "2026-10-01", ends_on: "2026-11-14" },
          content_progress: { completed_units: 2, confirmed: true },
          feedback: { content_units: 100, content_completed: false, difficulty: "manageable", sampled_at: STAMP },
        },
      },
      {
        id: "t-en", user_id: OWNER, tag_ids: ["s-en"], title: "英语真题",
        estimated_minutes: 3000, completed_minutes: 0, priority: 2,
        deadline: "2027-12-20", deadline_kind: "deadline",
        is_fixed: false, status: "not_started", created_at: STAMP, updated_at: STAMP,
      },
    ],
    blocks: [
      {
        id: "b-yesterday", user_id: OWNER, task_id: "t-math", date: "2026-10-17",
        start_minute: 0, duration_minutes: 120, actual_minutes: 90,
        is_fixed: false, status: "planned", created_at: STAMP, updated_at: STAMP,
      },
      {
        id: "b-today", user_id: OWNER, task_id: "t-en", date: "2026-10-18",
        start_minute: 0, duration_minutes: 60, actual_minutes: 0,
        is_fixed: false, status: "planned", created_at: STAMP, updated_at: STAMP,
      },
      {
        id: "b-future", user_id: OWNER, task_id: "t-en", date: "2026-10-20",
        start_minute: 0, duration_minutes: 60, actual_minutes: 0,
        is_fixed: false, status: "planned", created_at: STAMP, updated_at: STAMP,
      },
    ],
    logs: [
      {
        id: "log-1", user_id: OWNER, task_id: "t-math", block_id: "b-yesterday",
        date: "2026-10-17", minutes: 90, started_at: STAMP, ended_at: STAMP,
        source: "timer", relation: "scheduled",
      },
      {
        id: "log-2", user_id: OWNER, task_id: "t-en", block_id: null,
        date: "2026-10-16", minutes: 30, started_at: STAMP, ended_at: STAMP,
        source: "manual", relation: "extra",
      },
    ],
    fixed_events: [],
    replan_runs: [],
    phases: [],
    planning: {
      version: 1,
      prompt_version: "learning-route-2-full",
      rules_version: "workload-rhythm-2",
      mode: "full",
      detail_days: 45,
      rolling: false,
      route: [],
      milestones: [],
      assumptions: [],
      risks: [],
      uncovered: [],
      detailed_until: "2026-11-14",
      forecast: null,
    },
  });
}

const validOutput = {
  assessment: "当前计划约 250 小时，明显低于交大计算机考研所需 1500–3000 小时，本次延长周期并增加训练量。",
  verdict: "too_light",
  required_minutes: { min: 90000, max: 180000 },
  cycle: { end_date: "2027-12-24", reason: "覆盖到目标日期前一天" },
  intensity: {
    weekly_minutes: { "0": 120, "1": 240, "2": 240, "3": 240, "4": 240, "5": 240, "6": 240 },
    reason: "近期每周实际约 2 小时，可逐步提高到 20 小时",
  },
  task_updates: [{ task_id: "t-math", estimated_minutes: 20000, reason: "数学需要更多一轮" }],
  new_tasks: [
    {
      key: "t408", tag_names: ["408"], title: "408 真题 15 套", description: "完成并复盘",
      estimated_minutes: 9000, deadline_kind: "plan_end", priority: 3, reason: "补齐 408 训练量",
    },
  ],
  warnings: ["英语真题仍需每周固定时间"],
};

function validResponse(result: unknown = validOutput) {
  return Response.json({ choices: [{ message: { content: JSON.stringify(result) } }] });
}

function rejectOnAbort<T>(signal: AbortSignal, error?: Error): Promise<T> {
  return new Promise((_, reject) => {
    signal.addEventListener("abort", () => reject(error ?? signal.reason), { once: true });
  });
}

const fetchMock = vi.fn<typeof fetch>();

beforeEach(() => {
  aiConfig.aiApiKey = "test-key";
  fetchMock.mockReset();
  vi.stubGlobal("fetch", fetchMock);
  vi.useFakeTimers();
  vi.setSystemTime(new Date("2026-10-18T04:00:00Z"));
  // AbortSignal.timeout uses Node 的内部计时器，需要桥接到 vitest 假时钟。
  vi.spyOn(AbortSignal, "timeout").mockImplementation((milliseconds) => {
    const controller = new AbortController();
    setTimeout(
      () => controller.abort(new DOMException("The operation was aborted due to timeout", "TimeoutError")),
      milliseconds,
    );
    return controller.signal;
  });
});

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
  vi.useRealTimers();
});

describe("buildAdjustmentContext", () => {
  it("summarizes goal, progress, capacity, recent execution and future load without raw blocks", () => {
    const context = buildAdjustmentContext(fixture(), TODAY);
    expect(context.today).toBe("2026-10-18");
    expect(context.goal).toMatchObject({
      type: "exam",
      target_school: "上海交通大学",
      target_program: "计算机技术",
      target_date: "2027-12-25",
      constraints: "工作日最多 4 小时",
    });
    expect(context.plan_cycle).toEqual({ start: "2026-10-01", end: "2026-11-14", remaining_days: 28 });
    expect(context.capacity).toMatchObject({
      basis: "net",
      weekly_minutes_template: { "0": 120, "1": 300, "6": 240 },
      weekly_baseline_minutes: null,
      weekly_range: null,
      adopted_weekly_minutes: 1860,
      date_override_count: 0,
      week_override_count: 0,
    });
    expect(context.totals).toMatchObject({
      planned_minutes: 15000,
      completed_minutes: 600,
      remaining_minutes: 14400,
    });
    expect(context.totals.tag_totals).toContainEqual({
      tag: "数学", task_count: 1, planned_minutes: 12000, completed_minutes: 600, remaining_minutes: 11400,
    });

    expect(context.tasks).toHaveLength(2);
    expect(context.tasks[0]).toMatchObject({
      task_id: "t-math",
      tags: ["数学"],
      estimated_minutes: 12000,
      completed_minutes: 600,
      remaining_minutes: 11400,
      deadline: "2027-10-01",
      deadline_kind: "deadline",
      is_fixed: false,
      content_progress: { completed_units: 2, confirmed: true },
    });
    expect(context.tasks[0].workload_components).toEqual([{ label: "章节", quantity: 100, minutes_per_unit: 120 }]);
    expect(context.tasks[0].feedback).toMatchObject({ content_units: 100, difficulty: "manageable" });

    expect(context.recent_execution.last7_actual_minutes).toBe(120);
    expect(context.recent_execution.last7_planned_minutes).toBe(180);
    expect(context.recent_execution.last14_actual_minutes).toBe(120);
    expect(context.recent_execution.last14_planned_minutes).toBe(180);
    expect(context.recent_execution.days).toHaveLength(7);
    expect(context.recent_execution.days.at(-1)).toEqual({
      date: "2026-10-18", planned_minutes: 60, actual_minutes: 0,
      scheduled_minutes: 0, extra_minutes: 0,
    });
    expect(context.recent_execution.days[5]).toMatchObject({
      date: "2026-10-17", planned_minutes: 120, actual_minutes: 90, scheduled_minutes: 90,
    });
    expect(context.recent_execution).not.toHaveProperty("per_subject_last14");

    expect(context.future_load.next14_days).toHaveLength(14);
    expect(context.future_load.next14_days[0].date).toBe("2026-10-18");
    expect(context.future_load.next14_days[2]).toEqual({ date: "2026-10-20", planned_minutes: 60 });
    expect(context.future_load.scheduled_remaining_minutes).toBe(14400);
    expect(context.rules.real_hours).toContain("required_minutes");
    // 全量 blocks 绝不进入提示词。
    expect(context).not.toHaveProperty("blocks");
    expect(JSON.stringify(context)).not.toContain("b-yesterday");
  });
});

describe("generatePlanAdjustment", () => {
  it("sends the compact context with planning reasoning and parses the schema output", async () => {
    fetchMock.mockResolvedValue(validResponse());
    const context = buildAdjustmentContext(fixture(), TODAY);

    const result = await generatePlanAdjustment(context);

    expect(result).toEqual(PlanAdjustmentSchema.parse(validOutput));
    expect(AbortSignal.timeout).toHaveBeenCalledWith(210_000);
    const [url, options] = fetchMock.mock.calls[0];
    expect(url).toBe("https://ai.example.invalid/chat/completions");
    const body = JSON.parse(String(options?.body));
    expect(body).toMatchObject({
      model: "deepseek-flash",
      reasoning_effort: "high",
      response_format: { type: "json_object" },
    });
    const user = JSON.parse(body.messages.at(-1)!.content);
    expect(user).toEqual(JSON.parse(JSON.stringify(context)));
    expect(user.goal.target_school).toBe("上海交通大学");
    expect(user.totals.planned_minutes).toBe(15000);
    expect(user.recent_execution.last7_actual_minutes).toBe(120);
    expect(user.tasks[0].workload_components).toHaveLength(1);
    expect(user).not.toHaveProperty("blocks");
    const system = body.messages[0] as { role: string; content: string };
    expect(system.role).toBe("system");
    expect(system.content).toContain("只返回一个 JSON 对象");
    expect(system.content).toContain("1500–3000 小时");
    expect(system.content).toContain("不得修改真实截止日期");
  });

  it("fills the schema defaults for omitted collections", async () => {
    fetchMock.mockResolvedValue(
      validResponse({
        assessment: "计划合理",
        verdict: "reasonable",
        required_minutes: { min: 60000, max: 90000 },
        cycle: { end_date: "2027-09-30", reason: "保持" },
      }),
    );
    const result = await generatePlanAdjustment(buildAdjustmentContext(fixture(), TODAY));
    expect(result.task_updates).toEqual([]);
    expect(result.new_tasks).toEqual([]);
    expect(result.warnings).toEqual([]);
    expect(result.intensity).toBeUndefined();
  });

  it("reports upstream HTTP failures", async () => {
    fetchMock.mockResolvedValue(new Response(null, { status: 503 }));
    await expect(generatePlanAdjustment(buildAdjustmentContext(fixture(), TODAY)))
      .rejects.toThrow("AI 请求失败（503）");
  });

  it("rejects non-JSON and schema-invalid content, logging the issues server-side", async () => {
    const error = vi.spyOn(console, "error").mockImplementation(() => {});
    fetchMock.mockResolvedValueOnce(Response.json({ choices: [{ message: { content: "not JSON" } }] }));
    await expect(generatePlanAdjustment(buildAdjustmentContext(fixture(), TODAY))).rejects.toThrow();

    fetchMock.mockResolvedValueOnce(validResponse({ ...validOutput, verdict: "impossible" }));
    await expect(generatePlanAdjustment(buildAdjustmentContext(fixture(), TODAY))).rejects.toThrow();

    const schemaLog = error.mock.calls
      .map((call) => String(call[0]))
      .find((line) => line.includes('"ai_schema_invalid"'));
    expect(schemaLog).toContain('"label":"plan-adjust"');
    expect(schemaLog).toContain("verdict");
  });

  it("reports a timeout after 210 seconds instead of returning a local fallback", async () => {
    fetchMock.mockImplementation(async (_url, options) => rejectOnAbort<Response>(options!.signal!));
    const request = generatePlanAdjustment(buildAdjustmentContext(fixture(), TODAY));
    const result = expect(request).rejects.toThrow(/超时/);
    await vi.advanceTimersByTimeAsync(210_000);
    await result;
  });

  it("fails clearly when AI is not configured", async () => {
    aiConfig.aiApiKey = "";
    await expect(generatePlanAdjustment(buildAdjustmentContext(fixture(), TODAY)))
      .rejects.toThrow("服务器尚未配置 AI");
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
