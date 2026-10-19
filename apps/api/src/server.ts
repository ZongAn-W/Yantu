import Fastify from "fastify";
import cors from "@fastify/cors";
import cookie from "@fastify/cookie";
import rateLimit from "@fastify/rate-limit";
import { config } from "./config.js";
import { query, transaction } from "./db.js";
import { AccountDeletedError, clearSession, requireUser } from "./auth.js";
import { authRoutes } from "./auth-routes.js";
import { syncRoutes } from "./sync.js";
import { commitPlannerState, PlannerRevisionConflict, readPlannerState } from "./sync.js";
import { PlannerDocumentSchema } from "./sync-contracts.js";
import { onboardingRoutes, onboardingProfileVisible } from "./onboarding-routes.js";
import { migrateDatabase } from "./migrate.js";
import { PlanDraftSchema, ProfileSchema, ProfileUpdateSchema, SettleSchema } from "./contracts.js";
import { createPlanDraft } from "./ai.js";
import { applyPlanAdjustment, PlanAdjustmentError, type PlanAdjustmentJobPreview, type PlanAdjustmentPreview } from "./plan-adjust.js";
import { buildAdjustmentContext, generatePlanAdjustment, type PlanAdjustment } from "./plan-adjust-ai.js";
import { confirmDraft, dateAdd, dateToday, generatePlan, getProfile, itemToJson, listCourses, listDailyPlans, listItems, saveProfile, settleDay, snapshot, undoRun, type ItemRow } from "./planner.js";
import { z } from "zod";
import { fileURLToPath } from "node:url";
import { resolve } from "node:path";

export async function buildApp() {
const app = Fastify({ logger: process.env.NODE_ENV !== "test", trustProxy: (_address, hop) => hop === 0 });
await migrateDatabase();
await app.register(cookie);
const allowedOrigins = [...new Set([
  ...config.webOrigin.split(",").map((value) => value.trim()).filter(Boolean),
  ...(process.env.NODE_ENV !== "production" ? ["http://127.0.0.1:5180", "http://localhost:5180"] : []),
])];
await app.register(cors, { origin: allowedOrigins, credentials: true });
app.addHook("onRequest", async (request, reply) => {
  if (!["GET", "HEAD", "OPTIONS"].includes(request.method) && request.headers.origin && !allowedOrigins.includes(request.headers.origin)) {
    return reply.code(403).send({ error: "请求来源不受信任，请从应用重新登录" });
  }
});
await app.register(rateLimit, { global: false, errorResponseBuilder: (_request, context) => ({ statusCode: 429, error: "操作过于频繁，请稍后重试", retryAfter: Math.ceil(context.ttl / 1000) }) });
await app.register(authRoutes);
await app.register(syncRoutes);
await app.register(onboardingRoutes);

const bodyObject = (body: unknown) => body && typeof body === "object" ? body : {};
function errorMessage(error: unknown) { return error instanceof Error ? error.message : String(error); }

app.get("/api/health", async () => ({ ok: true, service: "planner-api", now: new Date().toISOString() }));
app.get("/api/me", async (request, reply) => { const user = await requireUser(request, reply); return user ? { user } : undefined; });

app.get("/api/onboarding/profile", async (request, reply) => { const user = await requireUser(request, reply); if (!user) return; return { profile: await onboardingProfileVisible(user.id) ? await getProfile(user.id) : null }; });
app.post("/api/onboarding/profile", async (request, reply) => { const user = await requireUser(request, reply); if (!user) return; const parsed = ProfileSchema.safeParse(bodyObject(request.body)); if (!parsed.success) return reply.code(400).send({ error: parsed.error.issues[0]?.message ?? "学习目标格式不正确" }); await saveProfile(user.id, parsed.data); return { profile: await getProfile(user.id) }; });
// 部分更新：字段缺失表示不修改，target_date 显式传 null 表示清空。
app.patch("/api/onboarding/profile", async (request, reply) => { const user = await requireUser(request, reply); if (!user) return; const parsed = ProfileUpdateSchema.safeParse(bodyObject(request.body)); if (!parsed.success) return reply.code(400).send({ error: parsed.error.issues[0]?.message ?? "学习目标格式不正确" }); const current = await getProfile(user.id); if (!current) return reply.code(404).send({ error: "请先完成学习目标设置" }); await saveProfile(user.id, { ...current, ...parsed.data }); return { profile: await getProfile(user.id) }; });

app.post("/api/ai/plan-drafts", async (request, reply) => {
  const user = await requireUser(request, reply); if (!user) return;
  const profile = ProfileSchema.safeParse(bodyObject(request.body)); if (!profile.success) return reply.code(400).send({ error: "请先完整填写学习目标" });
  try { const requestId = request.headers["idempotency-key"] ?? null; if (requestId) { const existing = await query<{ id: string; output_payload: unknown }>("select id,output_payload from ai_jobs where user_id=$1 and kind='plan_draft' and request_id=$2 order by created_at desc limit 1", [user.id, requestId]); if (existing.rows[0]) return { id: existing.rows[0].id, draft: existing.rows[0].output_payload }; } const draft = await createPlanDraft(profile.data); const saved = await query<{ id: string }>("insert into ai_jobs(user_id,kind,status,request_id,input_payload,output_payload) values($1,'plan_draft','completed',$2,$3,$4) returning id", [user.id, requestId, JSON.stringify(profile.data), JSON.stringify(draft)]); return { id: saved.rows[0].id, draft }; }
  catch (error) { return reply.code(502).send({ error: errorMessage(error) }); }
});
app.get("/api/ai/plan-drafts/:id", async (request, reply) => { const user = await requireUser(request, reply); if (!user) return; const params = request.params as { id: string }; const result = await query<{ id: string; output_payload: unknown }>("select id,output_payload from ai_jobs where id=$1 and user_id=$2 and kind='plan_draft'", [params.id, user.id]); if (!result.rows[0]) return reply.code(404).send({ error: "找不到草案" }); return { id: result.rows[0].id, draft: result.rows[0].output_payload }; });
app.post("/api/ai/plan-drafts/:id/confirm", async (request, reply) => { const user = await requireUser(request, reply); if (!user) return; const params = request.params as { id: string }; const found = await query<{ output_payload: unknown; status: string }>("select output_payload,status from ai_jobs where id=$1 and user_id=$2 and kind='plan_draft'", [params.id, user.id]); if (!found.rows[0]) return reply.code(404).send({ error: "找不到草案" }); if (found.rows[0].status === "confirmed") return reply.code(409).send({ error: "这个草案已经确认过了" }); const submitted = bodyObject(request.body) as { draft?: unknown }; const parsed = PlanDraftSchema.safeParse(submitted.draft ?? found.rows[0].output_payload); if (!parsed.success) return reply.code(400).send({ error: "草案格式不正确" }); try { const result = await confirmDraft(user.id, parsed.data); await query("update ai_jobs set status='confirmed',updated_at=now() where id=$1 and user_id=$2", [params.id, user.id]); return { ...result, confirmed: true }; } catch (error) { return reply.code(400).send({ error: errorMessage(error) }); } });

// ---- AI 一键调整后续计划（PLAN_ADJUST_AI_DESIGN §2）----
type AdjustmentJobPayload = { base_revision?: number; document?: unknown; preview?: PlanAdjustmentPreview; ai?: unknown };
const PlanAdjustmentRequestSchema = z.object({ expectedRevision: z.number().int().min(0), requestId: z.string().min(1).max(200).optional() });
const PlanAdjustmentConfirmSchema = z.object({ expectedRevision: z.number().int().min(0) });
const adjustmentRateLimit = { config: { rateLimit: { max: 5, timeWindow: "1 minute" } } } as const;
/** 客户端按 §3 从 preview 内读取 id/base_revision；存储的预览不含这两个字段，读取时补上。 */
function adjustmentPreview(id: string, payload: AdjustmentJobPayload) {
  return { ...(payload.preview as PlanAdjustmentPreview), id, base_revision: payload.base_revision ?? 0 } satisfies PlanAdjustmentJobPreview;
}
app.post("/api/ai/plan-adjustments", adjustmentRateLimit, async (request, reply) => {
  const user = await requireUser(request, reply); if (!user) return;
  const parsed = PlanAdjustmentRequestSchema.safeParse(bodyObject(request.body));
  if (!parsed.success) return reply.code(400).send({ error: parsed.error.issues[0]?.message ?? "调整请求格式不正确" });
  const { expectedRevision, requestId } = parsed.data;
  try {
    // 幂等：同一用户同一 requestId 已生成的预览直接复用，避免重复调用 AI。
    if (requestId) {
      const existing = await query<{ id: string; output_payload: unknown }>("select id,output_payload from ai_jobs where user_id=$1 and kind='plan_adjustment' and request_id=$2 order by created_at desc limit 1", [user.id, requestId]);
      const row = existing.rows[0], payload = row?.output_payload as AdjustmentJobPayload | null;
      if (row && payload?.preview) return { id: row.id, preview: adjustmentPreview(row.id, payload) };
    }
    const state = await transaction(client => readPlannerState(client, user.id));
    if (state.revision !== expectedRevision)
      return reply.code(409).send({ error: "云端计划已更新，请先同步后再调整" });
    const document = state.data;
    if (!document || (!document.tasks.length && !document.subjects.length))
      return reply.code(409).send({ error: "当前还没有可调整的计划，请先完成学习目标与计划设置" });
    const today = dateToday();
    const context = buildAdjustmentContext(document, today);
    let ai: PlanAdjustment;
    try {
      ai = await generatePlanAdjustment(context);
    } catch (error) {
      // Zod 结构化输出失败时把具体 issues 写日志；用户只看到可操作的通用提示。
      request.log.error(JSON.stringify({ event: "plan_adjust_ai_failed", userId: user.id, error: error instanceof z.ZodError ? error.issues.slice(0, 20) : errorMessage(error) }));
      return reply.code(502).send({ error: error instanceof z.ZodError ? "AI 生成的调整方案格式不正确，请重试" : errorMessage(error) });
    }
    let result: ReturnType<typeof applyPlanAdjustment>;
    try {
      result = applyPlanAdjustment(document, ai, today);
    } catch (error) {
      if (error instanceof PlanAdjustmentError) {
        request.log.error(JSON.stringify({ event: "plan_adjust_invalid", userId: user.id, message: error.message, detail: error.detail }));
        return reply.code(422).send({ error: "AI 调整方案不合法，请重试" });
      }
      throw error;
    }
    const saved = await query<{ id: string }>(
      "insert into ai_jobs(user_id,kind,status,request_id,input_payload,output_payload) values($1,'plan_adjustment','previewed',$2,$3,$4) returning id",
      [user.id, requestId ?? null, JSON.stringify({ expectedRevision }),
        JSON.stringify({ base_revision: state.revision, document: result.document, preview: result.preview, ai })]);
    return { id: saved.rows[0].id, preview: { ...result.preview, id: saved.rows[0].id, base_revision: state.revision } };
  } catch (error) {
    if (error instanceof PlannerRevisionConflict) return reply.code(409).send({ error: error.message });
    throw error;
  }
});
app.get("/api/ai/plan-adjustments/:id", adjustmentRateLimit, async (request, reply) => {
  const user = await requireUser(request, reply); if (!user) return;
  const params = request.params as { id: string };
  if (!z.string().uuid().safeParse(params.id).success) return reply.code(404).send({ error: "找不到调整预览" });
  const result = await query<{ id: string; output_payload: unknown }>("select id,output_payload from ai_jobs where id=$1 and user_id=$2 and kind='plan_adjustment'", [params.id, user.id]);
  const row = result.rows[0], payload = row?.output_payload as AdjustmentJobPayload | null;
  if (!row || !payload?.preview) return reply.code(404).send({ error: "找不到调整预览" });
  return { id: row.id, preview: adjustmentPreview(row.id, payload) };
});
app.post("/api/ai/plan-adjustments/:id/confirm", adjustmentRateLimit, async (request, reply) => {
  const user = await requireUser(request, reply); if (!user) return;
  const params = request.params as { id: string };
  if (!z.string().uuid().safeParse(params.id).success) return reply.code(404).send({ error: "找不到调整预览" });
  const parsed = PlanAdjustmentConfirmSchema.safeParse(bodyObject(request.body));
  if (!parsed.success) return reply.code(400).send({ error: parsed.error.issues[0]?.message ?? "确认请求格式不正确" });
  const found = await query<{ id: string; status: string; output_payload: unknown }>("select id,status,output_payload from ai_jobs where id=$1 and user_id=$2 and kind='plan_adjustment'", [params.id, user.id]);
  const row = found.rows[0], payload = row?.output_payload as AdjustmentJobPayload | null;
  if (!row) return reply.code(404).send({ error: "找不到调整预览" });
  if (row.status !== "previewed") return reply.code(409).send({ error: "这次调整已经确认" });
  if (!payload || typeof payload.base_revision !== "number" || payload.document === undefined || !payload.preview)
    return reply.code(409).send({ error: "调整预览已失效，请重新预览" });
  const stored = PlannerDocumentSchema.safeParse(payload.document);
  if (!stored.success) {
    request.log.error(JSON.stringify({ event: "plan_adjust_confirm_invalid", userId: user.id, issues: stored.error.issues.slice(0, 20) }));
    return reply.code(409).send({ error: "调整预览已失效，请重新预览" });
  }
  try {
    const revision = await transaction(async client => {
      const state = await readPlannerState(client, user.id);
      if (state.revision !== payload.base_revision || state.revision !== parsed.data.expectedRevision)
        throw new PlannerRevisionConflict("计划已更新，请重新预览");
      const next = await commitPlannerState(client, user.id, stored.data, parsed.data.expectedRevision);
      await client.query("insert into plan_versions(user_id,kind,payload) values($1,'adjust',$2)",
        [user.id, JSON.stringify({ summary: payload.preview!.assessment, previous_revision: payload.base_revision,
          previous_document: state.data, preview: adjustmentPreview(row.id, payload) })]);
      await client.query("update ai_jobs set status='confirmed',updated_at=now() where id=$1 and user_id=$2", [row.id, user.id]);
      return next;
    });
    return { confirmed: true, revision };
  } catch (error) {
    if (error instanceof PlannerRevisionConflict) return reply.code(409).send({ error: error.message });
    if (error instanceof z.ZodError) {
      request.log.error(JSON.stringify({ event: "plan_adjust_confirm_commit_invalid", userId: user.id, issues: error.issues.slice(0, 20) }));
      return reply.code(422).send({ error: "调整后的计划未通过校验，请重新预览" });
    }
    throw error;
  }
});

app.get("/api/courses", async (request, reply) => { const user = await requireUser(request, reply); return user ? { courses: await listCourses(user.id) } : undefined; });
app.get("/api/items", async (request, reply) => { const user = await requireUser(request, reply); return user ? { items: await listItems(user.id) } : undefined; });
app.post("/api/items", async (request, reply) => { const user = await requireUser(request, reply); if (!user) return; const parsed = z.object({ course_id: z.string().uuid(), title: z.string().min(1).max(200), description: z.string().max(4000).default(""), completion_criteria: z.string().max(1000).default(""), estimated_minutes: z.number().int().min(30).max(100000), earliest_date: z.string().optional(), deadline: z.string(), priority: z.number().int().min(1).max(3).default(2) }).safeParse(bodyObject(request.body)); if (!parsed.success) return reply.code(400).send({ error: "事项格式不正确" }); const result = await query<ItemRow>("insert into items(user_id,course_id,title,description,completion_criteria,estimated_minutes,earliest_date,deadline,priority,confirmed) select $1,id,$3,$4,$5,$6,$7,$8,$9,false from courses where id=$2 and user_id=$1 returning id,course_id,title,description,completion_criteria,estimated_minutes,earliest_date::text,deadline::text,priority,status", [user.id, parsed.data.course_id, parsed.data.title, parsed.data.description, parsed.data.completion_criteria, parsed.data.estimated_minutes, parsed.data.earliest_date ?? null, parsed.data.deadline, parsed.data.priority]); if (!result.rows[0]) return reply.code(404).send({ error: "找不到课程" }); return reply.code(201).send({ item: itemToJson(result.rows[0]) }); });
app.get("/api/planner/snapshot", async (request, reply) => { const user = await requireUser(request, reply); if (!user) return; const data = await snapshot(user.id); return data ? { data } : reply.code(404).send({ error: "请先完成学习目标设置和计划确认" }); });
app.patch("/api/items/:id", async (request, reply) => { const user = await requireUser(request, reply); if (!user) return; const parsed = z.object({ title: z.string().min(1).max(200).optional(), description: z.string().max(4000).optional(), completion_criteria: z.string().max(1000).optional(), priority: z.number().int().min(1).max(3).optional() }).safeParse(bodyObject(request.body)); if (!parsed.success) return reply.code(400).send({ error: "事项格式不正确" }); const params = request.params as { id: string }; const result = await query<ItemRow>("update items set title=coalesce($1,title),description=coalesce($2,description),completion_criteria=coalesce($3,completion_criteria),priority=coalesce($4,priority),updated_at=now() where id=$5 and user_id=$6 and confirmed=false returning id,course_id,title,description,completion_criteria,estimated_minutes,earliest_date::text,deadline::text,priority,status", [parsed.data.title, parsed.data.description, parsed.data.completion_criteria, parsed.data.priority, params.id, user.id]); if (!result.rows[0]) return reply.code(409).send({ error: "已确认事项不能直接修改，请先生成新的事项草案并确认" }); return { item: itemToJson(result.rows[0]) }; });
app.delete("/api/items/:id", async (request, reply) => { const user = await requireUser(request, reply); if (!user) return; const params = request.params as { id: string }; const result = await query("delete from items where id=$1 and user_id=$2", [params.id, user.id]); return result.rowCount ? { deleted: true } : reply.code(404).send({ error: "找不到事项" }); });

app.get("/api/plans", async (request, reply) => { const user = await requireUser(request, reply); if (!user) return; const q = request.query as { from?: string; to?: string }; const from = q.from ?? dateToday(); const profile = await getProfile(user.id); const to = q.to ?? profile?.plan_end_date ?? profile?.target_date ?? dateAdd(from, 27); return { plans: await listDailyPlans(user.id, from, to) }; });
app.post("/api/plans/generate", async (request, reply) => { const user = await requireUser(request, reply); if (!user) return; try { return await generatePlan(user.id, (bodyObject(request.body) as { from?: string }).from ?? dateToday()); } catch (error) { return reply.code(400).send({ error: errorMessage(error) }); } });
app.post("/api/daily-reviews/:date/settle", async (request, reply) => { const user = await requireUser(request, reply); if (!user) return; const parsed = SettleSchema.safeParse(bodyObject(request.body)); if (!parsed.success) return reply.code(400).send({ error: "每日反馈格式不正确" }); const params = request.params as { date: string }; try { return await settleDay(user.id, params.date, parsed.data.entries, parsed.data.feedback); } catch (error) { return reply.code(400).send({ error: errorMessage(error) }); } });
app.post("/api/study-logs", async (request, reply) => { const user = await requireUser(request, reply); if (!user) return; const parsed = z.object({ item_id: z.string().uuid(), date: z.string(), minutes: z.number().int().min(0).max(1440), feedback: z.string().max(2000).default("") }).safeParse(bodyObject(request.body)); if (!parsed.success) return reply.code(400).send({ error: "学习记录格式不正确" }); const result = await query("with removed as (delete from study_logs where user_id=$1 and item_id=$2 and date=$3 returning id) insert into study_logs(user_id,item_id,date,minutes,feedback) values($1,$2,$3,$4,$5) returning id,date,minutes", [user.id, parsed.data.item_id, parsed.data.date, parsed.data.minutes, parsed.data.feedback]); return reply.code(201).send({ log: result.rows[0] }); });
app.patch("/api/study-logs/:id", async (request, reply) => { const user = await requireUser(request, reply); if (!user) return; const parsed = z.object({ minutes: z.number().int().min(0).max(1440).optional(), feedback: z.string().max(2000).optional() }).safeParse(bodyObject(request.body)); if (!parsed.success) return reply.code(400).send({ error: "学习记录格式不正确" }); const params = request.params as { id: string }; const result = await query("update study_logs set minutes=coalesce($1,minutes),feedback=coalesce($2,feedback) where id=$3 and user_id=$4 returning id,date,minutes,feedback", [parsed.data.minutes, parsed.data.feedback, params.id, user.id]); return result.rows[0] ? { log: result.rows[0] } : reply.code(404).send({ error: "找不到学习记录" }); });
app.get("/api/progress", async (request, reply) => { const user = await requireUser(request, reply); if (!user) return; const totals = await query("select coalesce(sum(minutes),0)::int as actual_minutes, count(distinct date)::int as study_days from study_logs where user_id=$1", [user.id]); const remaining = await query("select coalesce(sum(greatest(estimated_minutes - coalesce((select sum(minutes) from study_logs l where l.item_id=i.id and l.user_id=i.user_id),0),0)),0)::int as remaining_minutes from items i where user_id=$1 and confirmed=true", [user.id]); return { ...totals.rows[0], ...remaining.rows[0] }; });
app.get("/api/replan-runs", async (request, reply) => { const user = await requireUser(request, reply); if (!user) return; const result = await query("select id,date::text,explanation,undone_at,created_at from replan_runs where user_id=$1 order by created_at desc limit 50", [user.id]); return { runs: result.rows }; });
app.post("/api/replan-runs/:id/undo", async (request, reply) => { const user = await requireUser(request, reply); if (!user) return; const params = request.params as { id: string }; try { return await undoRun(user.id, params.id); } catch (error) { return reply.code(400).send({ error: errorMessage(error) }); } });

app.setErrorHandler((error, _request, reply) => {
  if (error instanceof AccountDeletedError) {
    clearSession(reply);
    return reply.code(410).send({ error: error.message, code: error.code });
  }
  const status = (error as { statusCode?: number }).statusCode;
  if (status === 429) return reply.code(429).send({ error: "操作过于频繁，请稍后重试" });
  app.log.error(error);
  reply.code(500).send({ error: "服务器内部错误" });
});
return app;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const app = await buildApp();
  app.listen({ port: config.port, host: "0.0.0.0" }).catch((error) => { app.log.error(error); process.exit(1); });
}
