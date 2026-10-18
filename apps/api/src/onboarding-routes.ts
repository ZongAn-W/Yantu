import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type pg from "pg";
import { requireUser } from "./auth.js";
import { query, transaction } from "./db.js";
import { InterviewProfileSchema } from "./contracts.js";
import { ActionSchema, newSession, SessionSchema, type OnboardingSession } from "./onboarding-contracts.js";
import { advanceOnboarding } from "./onboarding.js";
import { sanitizeInterviewSession } from "./onboarding-evidence.js";
import { attachExamResearch, expireExamResearch } from "./exam-research.js";
import { PROFILE_COLUMNS, confirmDraft, itemToJson, replanDocument, saveProfile, snapshot } from "./planner.js";
import { commitPlannerState, PlannerRevisionConflict, readPlannerState } from "./sync.js";
import type { PlannerDocument } from "./sync-contracts.js";
import { buildPlanningDocument } from "./planning-service.js";

class SessionConflict extends Error {}

async function writeSession<T>(operation: (client: pg.PoolClient) => Promise<T>) {
  for (let attempt = 0; ; attempt++) {
    try {
      return await transaction(async client => {
        return operation(client);
      });
    } catch (error) {
      if (attempt < 2 && ["40001", "40P01"].includes((error as { code?: string }).code ?? "")) continue;
      throw error;
    }
  }
}

function planContext(document: PlannerDocument) {
  const fixed = new Set(document.blocks.filter(block => block.is_fixed).map(block => block.task_id));
  return { profile: document.profile, courses: document.subjects, items: document.tasks.map(task => ({ ...task, is_fixed: task.is_fixed || fixed.has(task.id) })),
    fixed_events: document.fixed_events, planning: document.planning,
    feedback_signals: document.tasks.flatMap(task => {
      const feedback = task.planning?.feedback;
      if (!feedback) return [];
      const samples = document.logs.filter(log => log.task_id === task.id && log.source === "timer" && log.minutes > 0
        && Date.parse(log.ended_at) > Date.parse(log.started_at) && log.ended_at <= feedback.sampled_at);
      const elapsed = samples.reduce((sum, log) => sum + log.minutes, 0);
      return [{ item_id: task.id, content_units: feedback.content_units, content_completed: feedback.content_completed,
        difficulty: feedback.difficulty, valid_samples: samples.length, actual_minutes: elapsed,
        observed_minutes_per_unit: samples.length >= 3 && feedback.content_units > 0 ? elapsed / feedback.content_units : null,
        estimated: samples.length < 3 }];
    }),
    recent_blocks: document.blocks.filter(block => block.actual_minutes > 0 || block.is_fixed).slice(-100) };
}

function seedDraft(session: OnboardingSession, document: PlannerDocument) {
  const fixed = new Set(document.blocks.filter(block => block.is_fixed).map(block => block.task_id));
  const tasks = document.tasks.filter(task => task.is_fixed || fixed.has(task.id) || task.status !== "archived" && task.status !== "completed").slice(0, 500);
  const subjectIds = new Set(tasks.map(task => task.subject_id));
  session.courses = document.subjects.filter(course => subjectIds.has(course.id)).slice(0, 100)
    .map(course => ({ id: course.id, name: course.name, description: "", priority: course.priority }));
  session.items = tasks.map(task => ({ id: task.id, course_id: task.subject_id, title: task.title,
    description: task.description ?? "", completion_criteria: "", estimated_minutes: task.estimated_minutes,
    earliest_date: task.earliest_date, deadline: task.deadline,
    deadline_kind: (task.deadline_kind ?? "deadline") as "deadline" | "plan_end", priority: task.priority, planning: task.planning }));
  session.planning = document.planning ?? null;
}

async function loadSession(client: pg.PoolClient, userId: string) {
  const plan = await readPlannerState(client, userId);
  const result = await client.query<{ payload: unknown }>("select payload from onboarding_sessions where user_id=$1", [userId]);
  const session = result.rows[0] ? SessionSchema.parse(result.rows[0].payload) : newSession();
  const hasPlan = Boolean(plan.data && (plan.data.subjects.length || plan.data.tasks.length));
  session.has_plan = hasPlan;
  if (hasPlan && plan.data && !result.rows[0]) {
    session.stage = "complete";
    const profile = await client.query(`select ${PROFILE_COLUMNS} from profiles where user_id=$1`, [userId]);
    session.profile = InterviewProfileSchema.parse(profile.rows[0]);
    session.start_date = session.profile.plan_start_date ?? "";
    session.end_date = session.profile.plan_end_date ?? "";
    seedDraft(session, plan.data);
  }
  if (hasPlan && plan.data && !session.replanning) {
    session.plan_revision = plan.revision;
    session.current_plan = planContext(plan.data);
  }
  return { session: sanitizeInterviewSession(session), plan };
}

export async function onboardingRoutes(app: FastifyInstance) {
  app.get("/api/onboarding/session", async (request, reply) => {
    const user = await requireUser(request, reply); if (!user) return;
    const { session } = await transaction(client => loadSession(client, user.id));
    return { session: await attachExamResearch(session) };
  });
  app.post("/api/ai/onboarding/advance", { config: { rateLimit: { max: 30, timeWindow: "1 minute" } } }, async (request, reply) => {
    const user = await requireUser(request, reply); if (!user) return;
    const parsed = z.object({ revision: z.number().int().nonnegative(), action: ActionSchema }).safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.issues[0]?.message ?? "请检查输入内容" });
    try {
      const { session: saved, plan } = await transaction(client => loadSession(client, user.id));
      const current = await attachExamResearch(saved);
      // A lost response to the final request may be retried without duplicating a plan.
      if (current.stage === "complete" && parsed.data.action.type === "finish") return { session: current };
      if (current.revision !== parsed.data.revision) throw new SessionConflict("引导已在其他页面更新，请刷新读取最新进度");
      if (parsed.data.action.type === "retry_research") await expireExamResearch(current);
      if (["resume_interview", "restart_interview", "refresh_plan"].includes(parsed.data.action.type) && plan.data) {
        current.plan_revision = plan.revision;
        current.current_plan = planContext(plan.data);
        if (parsed.data.action.type === "resume_interview" && current.stage === "complete") seedDraft(current, plan.data);
      }
      const candidate = SessionSchema.parse(await advanceOnboarding(current, parsed.data.action, plan.data));
      const next = await writeSession(async client => {
        const next = structuredClone(candidate);
        const latestPlan = await readPlannerState(client, user.id);
        await client.query("insert into onboarding_sessions(user_id,revision,payload) values($1,$2,$3) on conflict(user_id) do nothing", [user.id, current.revision, JSON.stringify(current)]);
        const locked = await client.query<{ revision: number }>("select revision from onboarding_sessions where user_id=$1 for update", [user.id]);
        if (locked.rows[0].revision !== current.revision) throw new SessionConflict("引导已更新，请刷新读取最新进度");
        if (next.stage === "complete") {
          const hasPlan = Boolean(latestPlan.data && (latestPlan.data.subjects.length || latestPlan.data.tasks.length));
          if (hasPlan && (!next.replanning || next.plan_revision !== latestPlan.revision))
            throw new PlannerRevisionConflict("当前计划已更新，请重新读取当前计划后再确认，访谈草案已保留");
          await saveProfile(user.id, next.profile, client);
          let document: PlannerDocument, unscheduled: number;
          if (next.planning) {
            const result = buildPlanningDocument(next, latestPlan.data, user.id);
            document = result.document;
            unscheduled = result.forecast.unscheduled_minutes;
            await client.query("insert into plan_versions(user_id,kind,payload) values($1,$2,$3)", [user.id, hasPlan ? "replan" : "confirmed",
              JSON.stringify({ summary: next.summary, start_date: next.start_date, previous_revision: latestPlan.revision,
                previous_document: latestPlan.data, previous_session: current, planning: document.planning })]);
          } else if (hasPlan && latestPlan.data) {
            const result = replanDocument(latestPlan.data, next);
            if (!result.generatedCount && result.unscheduledMinutes && result.unfinishedMinutes)
              throw new Error("所选日期内没有可安排的学习时间，请检查每周可用时间和事项日期");
            document = result.document;
            unscheduled = result.unscheduledMinutes;
            await client.query("insert into plan_versions(user_id,kind,payload) values($1,'replan',$2)", [user.id, JSON.stringify({ summary: next.summary,
              start_date: next.start_date, previous_revision: latestPlan.revision, previous_document: latestPlan.data, previous_session: current })]);
          } else {
            const result = await confirmDraft(user.id, { courses: next.courses, items: next.items,
              analysis_summary: next.summary, assumptions: next.assumptions, warnings: next.warnings }, { client, from: next.start_date, advice: false });
            if (!result.generated.count) throw new Error("所选日期内没有可安排的学习时间，请检查每周可用时间和事项日期");
            document = (await snapshot(user.id, client)) as PlannerDocument;
            unscheduled = result.generated.unscheduled_minutes;
          }
          // The locked revision also advances for our own profile/item writes via DB triggers.
          const ownRevision = (await client.query<{ revision: string }>("select revision from planner_sync_state where user_id=$1", [user.id])).rows[0];
          next.plan_revision = await commitPlannerState(client, user.id, document, Number(ownRevision.revision));
          next.has_plan = true;
          next.replanning = false;
          next.current_plan = planContext(document);
          if (unscheduled) next.warnings.push(`当前时间内尚有${unscheduled}分钟未排入计划，请在工作台调整学习预算`);
        }
        await client.query("update onboarding_sessions set revision=$2,payload=$3,updated_at=now() where user_id=$1", [user.id, next.revision, JSON.stringify(next)]);
        return next;
      });
      return { session: await attachExamResearch(next) };
    } catch (error) {
      // 用户只看到通用提示；把具体校验失败的字段写进服务端日志以便定位。
      if (error instanceof z.ZodError)
        console.error(JSON.stringify({ event: "onboarding_schema_invalid", userId: user.id,
          issues: error.issues.slice(0, 20).map(issue => ({ code: issue.code, path: issue.path, message: issue.message })) }));
      const message = error instanceof z.ZodError ? "AI 返回内容不完整或格式有误，请重试；已有进度已保留" : error instanceof Error ? error.message : "操作失败，请重试";
      return reply.code(error instanceof SessionConflict || error instanceof PlannerRevisionConflict
        || ["40001", "40P01"].includes((error as { code?: string }).code ?? "") ? 409 : 400).send({ error: message });
    }
  });
}

export async function onboardingProfileVisible(userId: string) {
  const courses = await query("select 1 from courses where user_id=$1 limit 1", [userId]);
  if (courses.rowCount) return true;
  const result = await query<{ payload: OnboardingSession }>("select payload from onboarding_sessions where user_id=$1", [userId]);
  return result.rows[0]?.payload.stage === "complete" || false;
}
