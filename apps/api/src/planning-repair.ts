import { config } from "./config.js";
import { generateItems } from "./onboarding-ai.js";
import type { OnboardingSession } from "./onboarding-contracts.js";
import type { PlannerDocument } from "./sync-contracts.js";
import { evaluatePlanning } from "./planning-service.js";

class ScopeChangeProposal extends Error {}

function assertFrozenScope(before: OnboardingSession["items"][number], after: OnboardingSession["items"][number]) {
  const proposal = (detail: string): never => {
    throw new ScopeChangeProposal(`「${before.title}」的范围取舍尚未应用：${detail}。原工作量已保留，请先编辑事项并确认该取舍`);
  };
  const original = before.planning?.workload?.components;
  const revised = after.planning?.workload?.components;
  if (original) {
    if (!revised || original.length !== revised.length) proposal("建议增减工作量组成项");
    for (const component of original) {
      const next = revised!.find(row => row.id === component.id);
      if (!next) proposal(`建议移除「${component.label}」`);
      if (next!.quantity !== component.quantity) proposal(`建议将「${component.label}」数量从${component.quantity}改为${next!.quantity}`);
      if (next!.minutes_per_unit !== component.minutes_per_unit)
        proposal(`建议将「${component.label}」每${component.unit}时长从${component.minutes_per_unit}分钟改为${next!.minutes_per_unit}分钟`);
      if (next!.unit !== component.unit || next!.label !== component.label
        || (next!.selected !== false) !== (component.selected !== false)
        || next!.range_min !== component.range_min || next!.range_max !== component.range_max)
        proposal(`建议更改「${component.label}」的范围或估算区间`);
    }
  } else if (after.estimated_minutes < before.estimated_minutes) proposal("建议降低尚无结构化依据的原时间预算");
  const activity = before.planning?.activity;
  if (activity) {
    const next = after.planning?.activity;
    if (!next || activity.kind !== next.kind || activity.sessions_per_week !== next.sessions_per_week
      || activity.session_minutes !== next.session_minutes || (activity.state ?? "active") !== (next.state ?? "active")
      || activity.starts_on !== next.starts_on || activity.ends_on !== next.ends_on)
      proposal("建议更改已确认的活动类型、频率、单次时长或有效窗口");
  }
}

/** Two repairs at most, sharing the deadline; failures retain the last valid candidate. */
export async function checkAndRepair(session: OnboardingSession, current?: PlannerDocument | null,
  revise = generateItems, now = Date.now) {
  let candidate = structuredClone(session);
  const deadline = now() + 135_000;
  let result = evaluatePlanning(candidate, current);
  for (let attempt = 1; config.aiApiKey && attempt <= 2; attempt++) {
    const actionable = result.preview.issues.filter(issue => issue.severity === "error" || ["RECURRENCE_SHORTFALL", "WORK_UNSCHEDULED"].includes(issue.code));
    const remaining = deadline - now();
    if (!actionable.length || remaining < 1000) break;
    try {
      const revised = await revise(candidate, JSON.stringify({ purpose: "定向修复规划质量问题", issues: actionable,
        frozen_constraints: candidate.profile, frozen_items: candidate.items.map(item => ({ id: item.id, deadline: item.deadline, deadline_kind: item.deadline_kind })),
        instruction: "保持全部已确认事项ID、真实截止日期、容量和固定记录。不能删除事项、缩短单价或虚构来源来通过检查；范围取舍必须明确显示。" }), Math.min(65_000, remaining));
      if (candidate.items.some(item => !revised.items.some(next => next.id === item.id))) throw new Error("修订遗漏已确认事项");
      if (candidate.items.some(item => item.deadline_kind === "deadline" && (revised.items.find(next => next.id === item.id)?.deadline !== item.deadline
        || revised.items.find(next => next.id === item.id)?.deadline_kind !== "deadline")))
        throw new Error("修订修改真实截止日期");
      for (const item of candidate.items) assertFrozenScope(item, revised.items.find(next => next.id === item.id)!);
      candidate = { ...candidate, ...revised, planning: { ...revised.planning,
        detail_days: candidate.planning?.detail_days ?? 14, rolling: candidate.planning?.rolling ?? true } };
      result = evaluatePlanning(candidate, current, attempt);
    } catch (error) {
      const message = error instanceof Error ? error.message : "修订失败";
      if (error instanceof ScopeChangeProposal) {
        candidate.planning = { ...(candidate.planning ?? result.planning),
          risks: [...new Set([...result.planning.risks, message])] };
        result = evaluatePlanning(candidate, current, attempt);
      }
      result.preview.issues.push({ code: error instanceof ScopeChangeProposal ? "SCOPE_CHANGE_PROPOSAL" : "REPAIR_FAILED", severity: "warning", message: `本次修订未完成：${message}`,
        evidence: "网络、结构或冻结约束校验失败", repair: "已有草稿已保留，可以重试或返回修改" });
      result.preview.repairs = attempt;
      if (result.planning.quality) result.planning.quality.repairs = attempt;
      break;
    }
  }
  return { ...candidate, planning: result.planning, preview: result.preview as unknown as Record<string, unknown> };
}

