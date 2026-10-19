import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { clearSession, issueBearerSession, issueSession, loginUser, refreshBearerSession, refreshSession, revokeBearerSession, userFromRequest, wantsBearer } from "./auth.js";
import { AccountDeletionError, deleteAccount } from "./account-deletion.js";
import { EmailSchema, RegistrationError, RegistrationSchema, registerWithCode, requestRegistrationCode } from "./registration.js";

export async function authRoutes(app: FastifyInstance) {
  app.addHook("onSend", async (_request, reply) => {
    reply.header("Cache-Control", "no-store");
  });
  app.post("/api/auth/registration-code", { config: { rateLimit: { max: 5, timeWindow: "15 minutes" } } }, async (request, reply) => {
    const parsed = z.object({ email: EmailSchema }).safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.issues[0].message });
    try {
      await requestRegistrationCode(parsed.data.email);
      return { ok: true, expiresIn: 600, retryAfter: 60 };
    } catch (error) {
      if (!(error instanceof RegistrationError)) throw error;
      if (error.retryAfter) reply.header("Retry-After", error.retryAfter);
      return reply.code(error.status).send({ error: error.message, retryAfter: error.retryAfter });
    }
  });

  app.post("/api/auth/register", { config: { rateLimit: { max: 10, timeWindow: "15 minutes" } } }, async (request, reply) => {
    const parsed = RegistrationSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.issues[0].message });
    try {
      const user = await registerWithCode(parsed.data);
      if (wantsBearer(request)) return reply.code(201).send({ user, ...(await issueBearerSession(user)) });
      await issueSession(reply, user);
      return reply.code(201).send({ user });
    } catch (error) {
      if (!(error instanceof RegistrationError)) throw error;
      return reply.code(error.status).send({ error: error.message });
    }
  });

  app.post("/api/auth/login", { config: { rateLimit: { max: 10, timeWindow: "1 minute" } } }, async (request, reply) => {
    const parsed = z.object({ email: EmailSchema, password: z.string().min(1).max(200) }).safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: "请输入有效的邮箱和密码" });
    const user = await loginUser(parsed.data.email, parsed.data.password);
    if (!user) return reply.code(401).send({ error: "邮箱或密码错误" });
    if (wantsBearer(request)) return { user, ...(await issueBearerSession(user)) };
    await issueSession(reply, user);
    return { user };
  });
  app.post("/api/auth/refresh", async (request, reply) => {
    const user = await refreshSession(request, reply);
    return user ? { user } : reply.code(401).send({ error: "登录已过期" });
  });
  app.post("/api/auth/token/refresh", { config: { rateLimit: { max: 30, timeWindow: "1 minute" } } }, async (request, reply) => {
    const parsed = z.object({ refreshToken: z.string().min(1).max(4096) }).safeParse(request.body);
    if (!parsed.success) return reply.code(401).send({ error: "登录已过期" });
    const refreshed = await refreshBearerSession(parsed.data.refreshToken);
    return refreshed ? { user: refreshed.user, ...refreshed.tokens } : reply.code(401).send({ error: "登录已过期" });
  });
  app.post("/api/auth/token/revoke", async (request, reply) => {
    const parsed = z.object({ refreshToken: z.string().min(1).max(4096) }).safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: "缺少刷新凭据" });
    await revokeBearerSession(parsed.data.refreshToken);
    return { ok: true };
  });
  app.post("/api/auth/delete-account", { config: { rateLimit: { max: 10, timeWindow: "15 minutes" } } }, async (request, reply) => {
    const user = await userFromRequest(request, { allowDeleted: true });
    if (!user) return reply.code(401).send({ error: "请先登录" });
    const parsed = z.object({ password: z.string().min(1).max(200) }).strict().safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: "请输入当前密码" });
    try {
      await deleteAccount(user.id, parsed.data.password);
      clearSession(reply);
      return { ok: true };
    } catch (error) {
      if (!(error instanceof AccountDeletionError)) throw error;
      if (error.retryAfter) reply.header("Retry-After", error.retryAfter);
      return reply.code(error.status).send({ error: error.message, ...(error.retryAfter ? { retryAfter: error.retryAfter } : {}) });
    }
  });
  app.post("/api/auth/logout", async (_request, reply) => { clearSession(reply); return { ok: true }; });
}
