import argon2 from "argon2";
import { createHash, randomUUID } from "node:crypto";
import { SignJWT, jwtVerify } from "jose";
import type { FastifyReply, FastifyRequest } from "fastify";
import { config } from "./config.js";
import { query, transaction } from "./db.js";

const accessKey = new TextEncoder().encode(config.accessSecret);
const refreshKey = new TextEncoder().encode(config.refreshSecret);
const ACCESS_COOKIE = "planner_access";
const REFRESH_COOKIE = "planner_refresh";

export type AuthUser = { id: string; email: string; username: string };
export type BearerTokens = {
  accessToken: string;
  refreshToken: string;
  expiresIn: number;
};

async function token(user: AuthUser, key: Uint8Array, expiration: string, type: string, jti?: string) {
  const jwt = new SignJWT({ email: user.email, username: user.username, type })
    .setProtectedHeader({ alg: "HS256" })
    .setSubject(user.id)
    .setIssuedAt()
    .setExpirationTime(expiration);
  if (jti) jwt.setJti(jti);
  return jwt.sign(key);
}

const hashRefreshToken = (value: string) => createHash("sha256").update(value).digest("hex");

async function createBearerTokens(user: AuthUser, execute: (sql: string, values: unknown[]) => Promise<unknown> = query): Promise<BearerTokens> {
  const jti = randomUUID();
  const accessToken = await token(user, accessKey, "15m", "access");
  const refreshToken = await token(user, refreshKey, "30d", "refresh", jti);
  await execute(
    "insert into auth_refresh_tokens(user_id,jti,token_hash,expires_at) values($1,$2,$3,now()+interval '30 days')",
    [user.id, jti, hashRefreshToken(refreshToken)],
  );
  return { accessToken, refreshToken, expiresIn: 15 * 60 };
}

export function wantsBearer(request: FastifyRequest): boolean {
  return request.headers["x-client-auth"] === "bearer";
}

export async function issueBearerSession(user: AuthUser): Promise<BearerTokens> {
  return createBearerTokens(user);
}

export async function issueSession(reply: FastifyReply, user: AuthUser) {
  const access = await token(user, accessKey, "15m", "access");
  const refresh = await token(user, refreshKey, "30d", "refresh");
  const production = process.env.NODE_ENV === "production";
  const options = { httpOnly: true, sameSite: production ? "none" as const : "lax" as const, secure: production, path: "/" };
  reply.setCookie(ACCESS_COOKIE, access, { ...options, maxAge: 15 * 60 });
  reply.setCookie(REFRESH_COOKIE, refresh, { ...options, maxAge: 30 * 24 * 60 * 60 });
}

export function clearSession(reply: FastifyReply) {
  const production = process.env.NODE_ENV === "production";
  const options = { path: "/", httpOnly: true, secure: production, sameSite: production ? "none" as const : "lax" as const };
  reply.clearCookie(ACCESS_COOKIE, options);
  reply.clearCookie(REFRESH_COOKIE, options);
}

async function verify(raw: string, key: Uint8Array, type: string): Promise<AuthUser> {
  const { payload } = await jwtVerify(raw, key, { algorithms: ["HS256"] });
  if (payload.type !== type || !payload.sub || typeof payload.email !== "string") throw new Error("Invalid session");
  if (typeof payload.username !== "string") throw new Error("Session requires sign-in");
  return { id: payload.sub, email: payload.email, username: payload.username };
}

export async function userFromRequest(request: FastifyRequest): Promise<AuthUser | null> {
  const authorization = request.headers.authorization;
  const bearer = authorization?.match(/^Bearer\s+(.+)$/i)?.[1];
  if (authorization !== undefined) {
    if (!bearer) return null;
    try { return await verify(bearer, accessKey, "access"); } catch { return null; }
  }
  const raw = request.cookies[ACCESS_COOKIE];
  if (!raw) return null;
  try { return await verify(raw, accessKey, "access"); } catch { return null; }
}

export async function refreshBearerSession(rawRefreshToken: string): Promise<{ user: AuthUser; tokens: BearerTokens } | null> {
  let payload;
  try {
    ({ payload } = await jwtVerify(rawRefreshToken, refreshKey, { algorithms: ["HS256"] }));
  } catch { return null; }
  if (payload.type !== "refresh" || !payload.sub || typeof payload.username !== "string" || !payload.jti) return null;
  return transaction(async client => {
    const found = await client.query<AuthUser>(
      "select u.id,u.email,u.username from auth_refresh_tokens r join users u on u.id=r.user_id where r.user_id=$1 and r.jti=$2 and r.token_hash=$3 and r.revoked_at is null and r.expires_at>now() for update of r",
      [payload.sub, payload.jti, hashRefreshToken(rawRefreshToken)],
    );
    const user = found.rows[0];
    if (!user) return null;
    await client.query("update auth_refresh_tokens set revoked_at=now() where user_id=$1 and jti=$2", [user.id, payload.jti]);
    // Rotation commits together so an insert failure does not consume the old token.
    return { user, tokens: await createBearerTokens(user, (sql, values) => client.query(sql, values)) };
  });
}

export async function revokeBearerSession(rawRefreshToken: string): Promise<void> {
  await query("update auth_refresh_tokens set revoked_at=now() where token_hash=$1 and revoked_at is null", [hashRefreshToken(rawRefreshToken)]);
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
    const { payload } = await jwtVerify(raw, refreshKey, { algorithms: ["HS256"] });
    // Native refresh tokens must pass the database-backed rotation/revocation checks.
    if (payload.jti) return null;
    const user = await verify(raw, refreshKey, "refresh");
    const found = await query<AuthUser>("select id, email, username from users where id = $1", [user.id]);
    if (!found.rows[0]) return null;
    const current = found.rows[0];
    await issueSession(reply, current);
    return current;
  } catch { return null; }
}

export async function loginUser(email: string, password: string) {
  const result = await query<AuthUser & { password_hash: string }>(
    "select id, email, username, password_hash from users where lower(email) = lower($1)", [email.trim()],
  );
  const row = result.rows[0];
  if (!row || !(await argon2.verify(row.password_hash, password))) return null;
  return { id: row.id, email: row.email, username: row.username };
}
