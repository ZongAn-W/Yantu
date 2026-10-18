import Fastify from "fastify";
import cors from "@fastify/cors";
import cookie from "@fastify/cookie";
import rateLimit from "@fastify/rate-limit";
import { config } from "./config.js";
import { query } from "./db.js";
import { requireUser } from "./auth.js";
import { authRoutes } from "./auth-routes.js";
import { syncRoutes } from "./sync.js";
import { onboardingRoutes, onboardingProfileVisible } from "./onboarding-routes.js";
import { migrateDatabase } from "./migrate.js";
import { PlanDraftSchema, ProfileSchema, ProfileUpdateSchema, SettleSchema } from "./contracts.js";
import { createPlanDraft } from "./ai.js";
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
