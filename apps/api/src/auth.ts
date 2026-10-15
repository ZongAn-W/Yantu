import argon2 from "argon2";
import { SignJWT, jwtVerify } from "jose";
import type { FastifyReply, FastifyRequest } from "fastify";
import { config } from "./config.js";
import { query } from "./db.js";

const accessKey = new TextEncoder().encode(config.accessSecret);
const refreshKey = new TextEncoder().encode(config.refreshSecret);
const ACCESS_COOKIE = "planner_access";
const REFRESH_COOKIE = "planner_refresh";

export type AuthUser = { id: string; email: string };

async function token(user: AuthUser, key: Uint8Array, expiration: string, type: string) {
  return new SignJWT({ email: user.email, type })
    .setProtectedHeader({ alg: "HS256" })
    .setSubject(user.id)
    .setIssuedAt()
    .setExpirationTime(expiration)
    .sign(key);
}

export async function issueSession(reply: FastifyReply, user: AuthUser) {
  const access = await token(user, accessKey, "15m", "access");
  const refresh = await token(user, refreshKey, "30d", "refresh");
  const options = { httpOnly: true, sameSite: "lax" as const, secure: process.env.NODE_ENV === "production", path: "/" };
  reply.setCookie(ACCESS_COOKIE, access, { ...options, maxAge: 15 * 60 });
  reply.setCookie(REFRESH_COOKIE, refresh, { ...options, maxAge: 30 * 24 * 60 * 60 });
}

export function clearSession(reply: FastifyReply) {
  reply.clearCookie(ACCESS_COOKIE, { path: "/" });
  reply.clearCookie(REFRESH_COOKIE, { path: "/" });
}

async function verify(raw: string, key: Uint8Array, type: string): Promise<AuthUser> {
  const { payload } = await jwtVerify(raw, key);
  if (payload.type !== type || !payload.sub || typeof payload.email !== "string") throw new Error("Invalid session");
  return { id: payload.sub, email: payload.email };
}

export async function userFromRequest(request: FastifyRequest): Promise<AuthUser | null> {
  const raw = request.cookies[ACCESS_COOKIE];
  if (!raw) return null;
  try { return await verify(raw, accessKey, "access"); } catch { return null; }
}

export async function requireUser(request: FastifyRequest, reply: FastifyReply): Promise<AuthUser | null> {
  const user = await userFromRequest(request);
  if (!user) {
    reply.code(401).send({ error: "请先登录" });
    return null;
  }
  return user;
}

export async function refreshSession(request: FastifyRequest, reply: FastifyReply) {
  const raw = request.cookies[REFRESH_COOKIE];
  if (!raw) return null;
  try {
    const user = await verify(raw, refreshKey, "refresh");
    const found = await query<{ id: string; email: string }>("select id, email from users where id = $1", [user.id]);
    if (!found.rows[0]) return null;
    const current = { id: found.rows[0].id, email: found.rows[0].email };
    await issueSession(reply, current);
    return current;
  } catch { return null; }
}

export async function registerUser(email: string, password: string) {
  const passwordHash = await argon2.hash(password, { type: argon2.argon2id });
  const result = await query<{ id: string; email: string }>(
    "insert into users(email, password_hash) values(lower($1), $2) returning id, email",
    [email.trim(), passwordHash],
  );
  return result.rows[0];
}

export async function loginUser(email: string, password: string) {
  const result = await query<{ id: string; email: string; password_hash: string }>(
    "select id, email, password_hash from users where email = lower($1)", [email.trim()],
  );
  const row = result.rows[0];
  if (!row || !(await argon2.verify(row.password_hash, password))) return null;
  return { id: row.id, email: row.email };
}
