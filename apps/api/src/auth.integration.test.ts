import { readFile } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { SignJWT } from "jose";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";

const mail = vi.hoisted(() => ({ send: vi.fn(), configured: true, codes: new Map<string, string>() }));
vi.mock("./mail.js", () => ({ mailConfigured: () => mail.configured, sendRegistrationCode: mail.send }));

describe.skipIf(!process.env.AUTH_TEST_DATABASE_URL)("registration against PostgreSQL", () => {
  let app: Awaited<ReturnType<typeof import("./server.js")["buildApp"]>>;
  let db: typeof import("./db.js");
  let ip = 0;
  const account = () => ({ email: `${randomUUID()}@example.com`, username: `user_${randomUUID().slice(0, 8)}`, password: "Study4089", code: "000000" });
  const post = (url: string, payload: Record<string, unknown>, origin = "http://127.0.0.1:5180", address = `192.0.2.${++ip}`) => app.inject({ method: "POST", url, payload, headers: { origin, "x-forwarded-for": address } });
  async function send(email: string) {
    const response = await post("/api/auth/registration-code", { email });
    expect(response.statusCode).toBe(200);
    return mail.codes.get(email)!;
  }

  beforeAll(async () => {
    vi.stubEnv("DATABASE_URL", process.env.AUTH_TEST_DATABASE_URL!);
    vi.stubEnv("JWT_ACCESS_SECRET", "auth-test-access-01234567890123456789");
    vi.stubEnv("JWT_REFRESH_SECRET", "auth-test-refresh-01234567890123456789");
    vi.stubEnv("WEB_ORIGIN", "http://127.0.0.1:5180");
    vi.stubEnv("NODE_ENV", "production");
    mail.send.mockImplementation(async (email: string, code: string) => { mail.codes.set(email, code); });
    db = await import("./db.js");
    await db.query(await readFile(new URL("../db/schema.sql", import.meta.url), "utf8"));
    const { buildApp } = await import("./server.js");
    app = await buildApp();
    await app.ready();
    const { migrateDatabase } = await import("./migrate.js");
    await migrateDatabase();
  });
  afterAll(async () => { await app?.close(); await db?.pool.end(); vi.unstubAllEnvs(); });

  it("rejects unauthenticated planner access and untrusted mutations", async () => {
    for (const url of ["/api/me", "/api/planner/snapshot", "/api/onboarding/profile", "/api/items", "/api/plans"]) {
      expect((await app.inject({ url })).statusCode).toBe(401);
    }
    expect((await post("/api/auth/logout", {}, "https://untrusted.example")).statusCode).toBe(403);
    const cors = await app.inject({ method: "OPTIONS", url: "/api/me", headers: { origin: "http://127.0.0.1:5180", "access-control-request-method": "GET" } });
    expect(cors.headers["access-control-allow-origin"]).toBe("http://127.0.0.1:5180");
    for (const origin of ["http://tauri.localhost", "tauri://localhost", "http://127.0.0.1:5174"]) {
      const retired = await app.inject({ method: "OPTIONS", url: "/api/me", headers: { origin, "access-control-request-method": "GET" } });
      expect(retired.headers["access-control-allow-origin"]).toBeUndefined();
      expect((await post("/api/auth/logout", {}, origin)).statusCode).toBe(403);
    }
  });

  it("requires verification, issues a session, supports email login and logout", async () => {
    const input = account();
    expect((await post("/api/auth/register", input)).statusCode).toBe(400);
    input.code = await send(input.email);
    const stored = await db.query<{ code_hash: string }>("select code_hash from registration_codes where email=$1", [input.email]);
    expect(stored.rows[0].code_hash).not.toBe(input.code);
    const registered = await post("/api/auth/register", input);
    expect(registered.statusCode).toBe(201);
    expect(registered.json().user.username).toBe(input.username);
    const cookies = registered.cookies.map(value => `${value.name}=${value.value}`).join("; ");
    expect(registered.cookies.every(value => value.httpOnly && value.secure && value.sameSite === "None")).toBe(true);
    expect((await app.inject({ url: "/api/me", headers: { cookie: cookies } })).json().user.email).toBe(input.email);
    expect((await post("/api/auth/login", { email: input.email.toUpperCase(), password: input.password })).statusCode).toBe(200);
    expect((await post("/api/auth/login", { email: input.email, password: "wrong" })).statusCode).toBe(401);
    expect((await post("/api/auth/register", input)).statusCode).toBe(400);
    expect((await post("/api/auth/registration-code", { email: input.email })).statusCode).toBe(409);
    const logout = await post("/api/auth/logout", {});
    expect(logout.cookies.every(value => value.value === "")).toBe(true);
    const user = await db.query<{ email_verified_at: Date; password_hash: string }>("select email_verified_at,password_hash from users where email=$1", [input.email]);
    expect(user.rows[0].email_verified_at).toBeTruthy();
    expect(user.rows[0].password_hash).toMatch(/^\$argon2id\$/);
  });

  it("commits failed attempts and locks the code after five errors", async () => {
    const input = account();
    const code = await send(input.email);
    const wrong = code === "000000" ? "111111" : "000000";
    for (let index = 0; index < 5; index++) expect((await post("/api/auth/register", { ...input, code: wrong })).statusCode).toBe(400);
    const attempts = await db.query<{ attempts: number }>("select attempts from registration_codes where email=$1", [input.email]);
    expect(attempts.rows[0].attempts).toBe(5);
    expect((await post("/api/auth/register", { ...input, code })).statusCode).toBe(400);
  });

  it("rejects expired codes and invalidates old codes after resending", async () => {
    const input = account();
    const old = await send(input.email);
    await db.query("update registration_codes set expires_at=now()-interval '1 second',sent_at=now()-interval '61 seconds' where email=$1", [input.email]);
    expect((await post("/api/auth/register", { ...input, code: old })).statusCode).toBe(400);
    const code = await send(input.email);
    if (code !== old) expect((await post("/api/auth/register", { ...input, code: old })).statusCode).toBe(400);
    expect((await post("/api/auth/register", { ...input, code })).statusCode).toBe(201);
  });

  it("limits simultaneous sends and hourly sends without returning the code", async () => {
    const input = account();
    const results = await Promise.all([post("/api/auth/registration-code", { email: input.email }), post("/api/auth/registration-code", { email: input.email })]);
    expect(results.map(result => result.statusCode).sort()).toEqual([200, 429]);
    expect(results.find(result => result.statusCode === 200)!.json()).toEqual({ ok: true, expiresIn: 600, retryAfter: 60 });
    await db.query("update registration_codes set sends_in_window=5,sent_at=now()-interval '61 seconds' where email=$1", [input.email]);
    expect((await post("/api/auth/registration-code", { email: input.email })).statusCode).toBe(429);
  });

  it("does not reserve a code after SMTP failure and rejects case-insensitive username collisions", async () => {
    const first = account();
    mail.send.mockRejectedValueOnce(new Error("SMTP unavailable"));
    expect((await post("/api/auth/registration-code", { email: first.email })).statusCode).toBe(503);
    expect((await db.query("select 1 from registration_codes where email=$1", [first.email])).rowCount).toBe(0);
    first.code = await send(first.email);
    expect((await post("/api/auth/register", first)).statusCode).toBe(201);
    const second = account(); second.code = await send(second.email);
    expect((await post("/api/auth/register", { ...second, username: first.username.toUpperCase() })).statusCode).toBe(409);
    expect((await post("/api/auth/register", second)).statusCode).toBe(201);
  });

  it("rejects missing fields and applies an IP limit even for different email addresses", async () => {
    expect((await post("/api/auth/register", { email: "test@example.com", password: "Study4089" })).statusCode).toBe(400);
    const address = "198.51.100.1";
    for (let count = 0; count < 5; count++) expect((await post("/api/auth/registration-code", { email: account().email }, "http://127.0.0.1:5180", address)).statusCode).toBe(200);
    expect((await post("/api/auth/registration-code", { email: account().email }, "http://127.0.0.1:5180", address)).statusCode).toBe(429);
  });

  async function nativeAccount() {
    const input = account();
    input.code = await send(input.email);
    const registered = await app.inject({ method: "POST", url: "/api/auth/register", payload: input, headers: { "x-client-auth": "bearer" } });
    expect(registered.statusCode).toBe(201);
    expect(registered.cookies).toHaveLength(0);
    expect(registered.headers["cache-control"]).toBe("no-store");
    return { input, session: registered.json() };
  }

  it("supports native registration and login without exposing tokens in Cookie responses", async () => {
    const { input, session } = await nativeAccount();
    expect(session.expiresIn).toBe(900);
    const me = await app.inject({ url: "/api/me", headers: { authorization: `Bearer ${session.accessToken}` } });
    expect(me.json().user.email).toBe(input.email);
    const login = await app.inject({ method: "POST", url: "/api/auth/login", payload: { email: input.email, password: input.password }, headers: { "x-client-auth": "bearer" } });
    expect(login.json().refreshToken).toBeTypeOf("string");
    expect(login.cookies).toHaveLength(0);
    const cookieLogin = await post("/api/auth/login", { email: input.email, password: input.password });
    expect(cookieLogin.json()).not.toHaveProperty("accessToken");
    expect(cookieLogin.cookies).toHaveLength(2);
    const stored = await db.query<{ token_hash: string }>("select token_hash from auth_refresh_tokens where user_id=$1", [session.user.id]);
    expect(stored.rows.length).toBeGreaterThanOrEqual(2);
    expect(stored.rows.every(row => /^[a-f0-9]{64}$/.test(row.token_hash) && row.token_hash !== session.refreshToken)).toBe(true);
  });

  it("rotates native refresh tokens exactly once and rejects invalid access tokens", async () => {
    const { session } = await nativeAccount();
    const results = await Promise.all([post("/api/auth/token/refresh", { refreshToken: session.refreshToken }), post("/api/auth/token/refresh", { refreshToken: session.refreshToken })]);
    expect(results.map(result => result.statusCode).sort()).toEqual([200, 401]);
    const rotated = results.find(result => result.statusCode === 200)!.json();
    expect(rotated.refreshToken).not.toBe(session.refreshToken);
    expect((await post("/api/auth/token/refresh", { refreshToken: rotated.refreshToken })).statusCode).toBe(200);
    for (const access of [session.refreshToken, "invalid", ""]) {
      expect((await app.inject({ url: "/api/me", headers: { authorization: `Bearer ${access}` } })).statusCode).toBe(401);
    }
    const expired = await new SignJWT({ type: "access", email: session.user.email, username: session.user.username })
      .setProtectedHeader({ alg: "HS256" }).setSubject(session.user.id).setExpirationTime("0s")
      .sign(new TextEncoder().encode("auth-test-access-01234567890123456789"));
    expect((await app.inject({ url: "/api/me", headers: { authorization: `Bearer ${expired}` } })).statusCode).toBe(401);
  });

  it("revokes native refresh tokens and prevents using them through Cookie refresh", async () => {
    const { session } = await nativeAccount();
    const revoked = await post("/api/auth/token/revoke", { refreshToken: session.refreshToken });
    expect(revoked.statusCode).toBe(200);
    expect((await post("/api/auth/token/refresh", { refreshToken: session.refreshToken })).statusCode).toBe(401);
    const cookieAttempt = await app.inject({ method: "POST", url: "/api/auth/refresh", headers: { cookie: `planner_refresh=${session.refreshToken}` } });
    expect(cookieAttempt.statusCode).toBe(401);
    expect((await post("/api/auth/token/refresh", { refreshToken: "tampered" })).statusCode).toBe(401);
  });

  it("keeps Cookie refresh working and never falls back from invalid Bearer to Cookie", async () => {
    const { input } = await nativeAccount();
    const login = await post("/api/auth/login", { email: input.email, password: input.password });
    const cookies = login.cookies.map(value => `${value.name}=${value.value}`).join("; ");
    const refreshed = await app.inject({ method: "POST", url: "/api/auth/refresh", headers: { cookie: cookies } });
    expect(refreshed.statusCode).toBe(200);
    expect(refreshed.cookies).toHaveLength(2);
    expect(refreshed.json()).not.toHaveProperty("refreshToken");
    for (const authorization of ["Bearer invalid", "Basic abc"]) {
      expect((await app.inject({ url: "/api/me", headers: { cookie: cookies, authorization } })).statusCode).toBe(401);
    }
    const missingUser = await new SignJWT({ type: "refresh", email: input.email, username: "removed" })
      .setProtectedHeader({ alg: "HS256" }).setSubject(randomUUID()).setJti(randomUUID()).setExpirationTime("30d")
      .sign(new TextEncoder().encode("auth-test-refresh-01234567890123456789"));
    expect((await post("/api/auth/token/refresh", { refreshToken: missingUser })).statusCode).toBe(401);
  });
});
