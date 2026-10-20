import { mkdir, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { z } from "zod";
import { config } from "./config.js";
import { requestStructuredAI } from "./ai-json.js";
import { generateItems } from "./onboarding-ai.js";
import { ItemsSchema, newSession, type OnboardingSession } from "./onboarding-contracts.js";
import { ProfileSchema } from "./contracts.js";
import { evaluatePlanning, newPlanning, PLANNING_PROMPT_VERSION, PLANNING_RULES_VERSION } from "./planning-service.js";
import { checkAndRepair } from "./planning-repair.js";

export const EVALUATION_CASES = [
  { id: "long-exam", type: "exam", goal: "长期备考，数学需要21套卷每套180分钟并逐套复盘，英语每周持续阅读", end: "2027-12-21", minutes: 300, course: "数学与英语" },
  { id: "short-exam", type: "exam", goal: "四周后语言测验，听力薄弱，每周需要稳定练习", minutes: 120, course: "语言学习" },
  { id: "university-course", type: "course", goal: "大学线性代数，完成矩阵章节与两份作业，特征值理解薄弱", minutes: 120, course: "线性代数" },
  { id: "project-skill", type: "skill", goal: "从零学习Python，产出可运行的CSV清理脚本，再用样例测试", minutes: 90, course: "Python" },
  { id: "self-study", type: "self_study", goal: "每周两次历史阅读，每次30分钟，没有目标日期，允许空闲", minutes: 60, course: "历史" },
  { id: "unknown-material", type: "skill", goal: "学习摄影，尚未选择材料和了解速度，先安排少量校准", minutes: 90, course: "摄影" },
  { id: "insufficient-time", type: "exam", goal: "两周内完成21套试卷及复盘，每套作答180分钟；每周只能学习两天，每天60分钟", minutes: 60, course: "试卷练习" },
  { id: "progress-deviation", type: "course", goal: "练习三次后发现原估计过快：实际每章120分钟，原估计60分钟；依然有两章未完成", minutes: 90, course: "课程练习" },
] as const;

export function evaluationSession(test: typeof EVALUATION_CASES[number]): OnboardingSession {
  const start = "2026-10-17", end = "end" in test ? test.end : test.id === "insufficient-time" ? "2026-10-30" : "2026-11-13";
  const week = Object.fromEntries([0, 1, 2, 3, 4, 5, 6].map(day => [String(day), test.id === "insufficient-time" && ![2, 6].includes(day) ? 0 : day === 0 ? 0 : test.minutes]));
  // The evaluation exercises the production default: one full-period plan, not a 14-day draft.
  const span = Math.round((Date.parse(`${end}T00:00:00Z`) - Date.parse(`${start}T00:00:00Z`)) / 86_400_000) + 1;
  return { ...newSession(), constraints_confirmed: true, start_date: start, end_date: end,
    planning: { ...newPlanning(), detail_days: Math.min(1095, span) },
    answers: [{ question: "学习目标", answer: test.goal }],
    profile: ProfileSchema.parse({ goal_type: test.type, goal_text: test.goal, target_date: null,
      plan_start_date: start, plan_end_date: end, weekly_minutes: week }),
    items: [{ id: `seed-${test.id}`, tag_names: [test.course], title: `${test.course}学习`, description: test.goal,
      completion_criteria: "完成一个可验证的小目标", estimated_minutes: test.minutes, deadline: end,
      deadline_kind: "plan_end", priority: 2 }] };
}

async function run() {
  const live = process.argv.includes("--live");
  const repair = process.argv.includes("--repair");
  const variantOption = process.argv.find(arg => arg.startsWith("--variant="))?.split("=")[1];
  const variants = variantOption === "baseline" ? ["baseline"] as const : variantOption === "upgrade" ? ["upgrade"] as const : ["baseline", "upgrade"] as const;
  const limit = Math.min(8, Math.max(1, Number(process.argv.find(arg => arg.startsWith("--limit="))?.split("=")[1] ?? 3)));
  const selected = process.argv.find(arg => arg.startsWith("--cases="))?.split("=")[1]?.split(",");
  const cases = EVALUATION_CASES.filter(test => !selected || selected.includes(test.id)).slice(0, limit);
  const output = resolve(process.argv.find(arg => arg.startsWith("--output="))?.slice(9) ?? "../../output/planning-evaluation.json");
  const report: Record<string, unknown> = { suite_version: "learning-planning-eval-1", prompt_version: PLANNING_PROMPT_VERSION,
    rules_version: PLANNING_RULES_VERSION, model: config.aiModel, reasoning_effort: config.aiReasoningEffort,
    mode: live ? "live" : "cases-only", generated_at: new Date().toISOString(),
    rubric: ["目标与薄弱项响应", "事实来源", "结构化工作量", "学习顺序与节奏", "容量与日期", "可执行性", "进度响应", "稳定性"],
    qualitative_review: "人工复核输入与输出；程序问题数不能替代学习策略质量评判", cases: [] };
  if (live && !config.aiApiKey) throw new Error("AI 未配置；未进行真实效果评测");
  const results: unknown[] = [];
  for (const test of cases) {
    const session = evaluationSession(test);
    if (!live) { results.push({ id: test.id, input: session, status: "not_run" }); continue; }
    const outcomes: unknown[] = [];
    for (const variant of variants) {
      const started = Date.now();
      try {
        const generated = variant === "baseline"
          ? await requestStructuredAI(z.object({ items: ItemsSchema, summary: z.string(), assumptions: z.array(z.string()), warnings: z.array(z.string()) }),
            '直接生成事项，不要求先创建课程。返回items,summary,assumptions,warnings。每项包含id、可选tag_names、title、description、completion_criteria、estimated_minutes、earliest_date、deadline、deadline_kind和priority。标签只返回名称，不返回数据库ID。', session, { timeoutMs: 65_000, label: "eval-items" })
          : await generateItems(session, "", 65_000);
        const candidate = { ...session, ...generated };
        const repaired = repair && variant === "upgrade" ? await checkAndRepair(candidate) : null;
        const checked = repaired?.preview ?? evaluatePlanning(candidate).preview;
        outcomes.push({ variant, status: "returned", elapsed_ms: Date.now() - started, output: generated,
          revised_output: repaired ? { items: repaired.items, planning: repaired.planning } : undefined,
          evaluation: { ...checked, token: undefined, fingerprint: undefined }, requests: 1 + Number(checked.repairs ?? 0) });
      } catch (error) {
        outcomes.push({ variant, status: "failed", elapsed_ms: Date.now() - started, requests: 1,
          error: error instanceof Error ? error.message : "request_failed" });
      }
    }
    results.push({ id: test.id, input: session, outcomes });
    console.log(`${test.id}: ${variants.join(" and ")} evaluated`);
  }
  report.cases = results;
  await mkdir(resolve(output, ".."), { recursive: true });
  await writeFile(output, JSON.stringify(report, null, 2), "utf8");
  console.log(`Report: ${output}`);
}

if (process.argv[1]?.replace(/\\/g, "/").endsWith("/planning-eval.ts")) await run();
