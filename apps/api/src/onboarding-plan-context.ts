import type { OnboardingSession } from "./onboarding-contracts.js";

type Row = Record<string, unknown>;
export type PlanContextScope = "interview" | "items" | "recommendations";

const record = (value: unknown): Row | null => value && typeof value === "object" && !Array.isArray(value) ? value as Row : null;
const rows = (value: unknown): Row[] => Array.isArray(value) ? value.map(record).filter((row): row is Row => row !== null) : [];
const text = (value: unknown) => typeof value === "string" ? value : "";
const select = (row: Row, keys: readonly string[]) => Object.fromEntries(keys
  .filter(key => row[key] !== undefined).map(key => [key, structuredClone(row[key])]));
const dependencies = (item: Row) => rows(record(item.planning)?.dependencies).map(row => text(row.task_id)).filter(Boolean);

const itemFields = ["id", "title", "tag_ids", "estimated_minutes", "completed_minutes", "priority", "earliest_date", "deadline", "deadline_kind", "is_fixed", "status"];
const planningFields = ["workload", "activity", "dependencies", "content_progress", "feedback"];
const blockFields = ["id", "task_id", "date", "start_minute", "duration_minutes", "actual_minutes", "is_fixed", "status", "completion_status", "feedback", "activity_instance_id"];

function compactItem(item: Row, draft: OnboardingSession["items"][number] | undefined, isFixed: boolean, scope: PlanContextScope) {
  const result = { ...select(item, itemFields), ...(isFixed ? { is_fixed: true } : {}) };
  const description = text(item.description);
  const draftDescription = draft ? [draft.description, draft.completion_criteria ? `\u5b8c\u6210\u6807\u51c6\uff1a${draft.completion_criteria}` : ""].filter(Boolean).join("\n") : "";
  // Omit only exact duplicates already sent as the editable draft; unique scope and constraints stay intact.
  if (description && description !== draft?.description && description !== draftDescription) Object.assign(result, { description });
  if (item.completion_criteria && item.completion_criteria !== draft?.completion_criteria) {
    Object.assign(result, { completion_criteria: structuredClone(item.completion_criteria) });
  }
  const planning = record(item.planning);
  if (planning) Object.assign(result, { planning: select(planning,
    scope === "items" || isFixed ? planningFields : planningFields.filter(field => field !== "workload")) });
  return result;
}

/** Model-only projection. Stored plan data remains complete for frozen-input checks and commits. */
export function compactPlanContext(session: OnboardingSession, scope: PlanContextScope): Row | null {
  const plan = session.current_plan;
  if (!plan) return null;
  const legacyCourses = rows(plan.courses ?? plan.subjects);
  const tags = rows(plan.tags).length ? rows(plan.tags) : legacyCourses.map(course => ({ id: course.id, name: course.name }));
  const items = rows(plan.items).map(item => {
    if (Array.isArray(item.tag_ids)) return item;
    const legacyId = text(item.subject_id) || text(item.course_id);
    return { ...item, tag_ids: legacyId && tags.some(tag => text(tag.id) === legacyId) ? [legacyId] : [] };
  });
  const blocks = rows(plan.recent_blocks);
  const fixedIds = new Set(blocks.filter(block => block.is_fixed === true).map(block => text(block.task_id)));
  const draftItems = new Map(session.items.map(item => [item.id, item]));
  const included = new Set(items.filter(item => item.is_fixed === true || fixedIds.has(text(item.id)) || draftItems.has(text(item.id))
    || item.status !== "archived")
    .map(item => text(item.id)));
  const byId = new Map(items.map(item => [text(item.id), item]));

  // Follow both inherited and edited dependencies, including completed or archived predecessors.
  const pending = [...included, ...session.items.flatMap(dependencies)];
  for (let index = 0; index < pending.length; index++) {
    const id = pending[index], item = byId.get(id);
    if (!item) continue;
    included.add(id);
    for (const dependency of dependencies(item)) {
      if (included.has(dependency) || !byId.has(dependency)) continue;
      included.add(dependency);
      pending.push(dependency);
    }
  }
  const keptItems = items.filter(item => included.has(text(item.id)));
  const neededTags = new Set(keptItems.flatMap(item => Array.isArray(item.tag_ids)
    ? item.tag_ids.filter((value): value is string => typeof value === "string") : []));
  const result: Row = {
    tags: tags.filter(tag => neededTags.has(text(tag.id))).map(tag => select(tag, ["id", "name"])),
    items: keptItems.map(item => compactItem(item, scope === "items" ? draftItems.get(text(item.id)) : undefined,
      item.is_fixed === true || fixedIds.has(text(item.id)), scope)),
    feedback_signals: rows(plan.feedback_signals).filter(signal => included.has(text(signal.item_id)))
      .map(signal => select(signal, ["item_id", "content_units", "content_completed", "difficulty", "valid_samples", "actual_minutes", "observed_minutes_per_unit", "estimated"])),
  };
  const archivedItems = items.filter(item => item.status === "archived" && !included.has(text(item.id)))
    .map(item => ({ ...select(item, ["id", "title", "status"]), tag_ids: item.tag_ids }));
  if (archivedItems.length) result.archived_items = archivedItems;
  const fixedBlocks = blocks.filter(block => block.is_fixed === true);
  if (fixedBlocks.length) result.recent_blocks = fixedBlocks.map(block => select(block, blockFields));
  const recentExecution = new Map<string, { item_id: string; actual_minutes: number; blocks: number; latest_date: string; feedback: Row[] }>();
  for (const block of blocks) {
    const id = text(block.task_id);
    if (block.is_fixed === true || !included.has(id)) continue;
    const minutes = typeof block.actual_minutes === "number" ? block.actual_minutes : 0;
    if (minutes <= 0 && !block.feedback && block.completion_status !== "completed") continue;
    const entry = recentExecution.get(id) ?? { item_id: id, actual_minutes: 0, blocks: 0, latest_date: "", feedback: [] };
    entry.actual_minutes += minutes;
    entry.blocks++;
    if (text(block.date) > entry.latest_date) entry.latest_date = text(block.date);
    if (block.feedback || block.completion_status) entry.feedback.push(select(block, ["id", "date", "completion_status", "feedback"]));
    recentExecution.set(id, entry);
  }
  if (recentExecution.size) result.recent_execution = [...recentExecution.values()];

  const profile = record(plan.profile);
  if (profile) {
    const scheduling = select(profile, ["planning_mode", "weekly_minutes", "daily_limit_minutes", "buffer_minutes", "granularity_minutes", "study_start_minute", "study_end_minute", "constraints_text"]);
    if (Object.keys(scheduling).length) result.scheduling_constraints = scheduling;
    if (scope === "interview") {
      result.historical_profile = select(profile, ["goal_text", "goal_type", "goal_subtype", "target_school", "target_program", "target_date", "target_date_confirmed", "current_progress", "foundation"]);
    }
  }
  const milestones = rows(record(plan.planning)?.milestones).filter(milestone => ["user", "verified"].includes(text(milestone.source_kind)));
  if (milestones.length) result.milestones = structuredClone(milestones);
  return result;
}
