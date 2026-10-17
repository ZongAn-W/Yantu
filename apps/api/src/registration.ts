import { createHmac, randomInt, timingSafeEqual } from "node:crypto";
import argon2 from "argon2";
import { z } from "zod";
import { config } from "./config.js";
import { transaction } from "./db.js";
import { mailConfigured, sendRegistrationCode } from "./mail.js";
import type { AuthUser } from "./auth.js";

export const EmailSchema = z.string().trim().toLowerCase().email("请输入有效的邮箱地址").max(254);
export const RegistrationSchema = z.object({
  email: EmailSchema,
  username: z.string().trim().min(2, "用户名需为 2 至 24 个字符").max(24, "用户名需为 2 至 24 个字符")
    .regex(/^[\p{Script=Han}A-Za-z0-9_]+$/u, "用户名只能包含中文、英文字母、数字和下划线"),
  password: z.string().min(9, "密码至少 9 位，且需包含英文字母和数字").max(128, "密码不能超过 128 位")
    .regex(/[A-Za-z]/, "密码需包含英文字母").regex(/[0-9]/, "密码需包含数字"),
  code: z.string().regex(/^\d{6}$/, "请输入 6 位邮箱验证码"),
});
export type RegistrationInput = z.infer<typeof RegistrationSchema>;

export class RegistrationError extends Error {
  constructor(message: string, public status = 400, public retryAfter?: number) { super(message); }
}

function codeHash(email: string, code: string) {
  return createHmac("sha256", config.refreshSecret).update(`registration:${email}:${code}`).digest("hex");
}

export async function requestRegistrationCode(email: string) {
  if (!mailConfigured()) throw new RegistrationError("验证码邮件服务暂未配置，请联系管理员", 503);
  await transaction(async client => {
    // Serialize both first-time sends and resends for an address, including multiple API instances.
    await client.query("select pg_advisory_xact_lock(hashtextextended($1, 0))", [email]);
    const existing = await client.query("select 1 from users where lower(email)=$1", [email]);
    if (existing.rowCount) throw new RegistrationError("该邮箱已注册，请直接登录", 409);
    const previous = await client.query<{ since_sent: number; since_window: number; sends_in_window: number }>(
      "select extract(epoch from now()-sent_at)::float8 as since_sent, extract(epoch from now()-window_started_at)::float8 as since_window, sends_in_window from registration_codes where email=$1", [email]);
    const row = previous.rows[0];
    if (row && row.since_sent < 60) throw new RegistrationError("发送过于频繁，请稍后重试", 429, Math.ceil(60 - row.since_sent));
    if (row && row.since_window < 3600 && row.sends_in_window >= 5) throw new RegistrationError("此邮箱发送次数已达上限，请稍后重试", 429, Math.ceil(3600 - row.since_window));
    const code = String(randomInt(0, 1000000)).padStart(6, "0");
    try { await sendRegistrationCode(email, code); }
    catch { throw new RegistrationError("验证码发送失败，请稍后重试", 503); }
    await client.query(`insert into registration_codes(email,code_hash,expires_at,sent_at,window_started_at)
      values($1,$2,now()+interval '10 minutes',now(),now())
      on conflict(email) do update set code_hash=$2, expires_at=now()+interval '10 minutes', sent_at=now(), attempts=0, consumed=false,
      sends_in_window=case when registration_codes.window_started_at <= now()-interval '1 hour' then 1 else registration_codes.sends_in_window+1 end,
      window_started_at=case when registration_codes.window_started_at <= now()-interval '1 hour' then now() else registration_codes.window_started_at end`, [email, codeHash(email, code)]);
  });
}

export async function registerWithCode(input: RegistrationInput): Promise<AuthUser> {
  const passwordHash = await argon2.hash(input.password, { type: argon2.argon2id });
  try {
    const result = await transaction(async client => {
      await client.query("select pg_advisory_xact_lock(hashtextextended($1, 0))", [input.email]);
      const codes = await client.query<{ code_hash: string; valid: boolean; attempts: number; consumed: boolean }>(
        "select code_hash,expires_at>now() as valid,attempts,consumed from registration_codes where email=$1 for update", [input.email]);
      const code = codes.rows[0];
      if (!code || !code.valid || code.consumed || code.attempts >= 5) return { error: "验证码无效或已过期，请重新获取" };
      const expected = Buffer.from(codeHash(input.email, input.code), "hex");
      const stored = Buffer.from(code.code_hash, "hex");
      if (stored.length !== expected.length || !timingSafeEqual(stored, expected)) {
        await client.query("update registration_codes set attempts=attempts+1 where email=$1", [input.email]);
        // Commit failed attempts before returning an error, so retries cannot reset the counter.
        return { error: "验证码错误，请检查邮箱中的最新验证码" };
      }
      const user = await client.query<AuthUser>(
        "insert into users(email,username,password_hash,email_verified_at) values($1,$2,$3,now()) returning id,email,username", [input.email, input.username, passwordHash]);
      await client.query("update registration_codes set consumed=true where email=$1", [input.email]);
      return { user: user.rows[0] };
    });
    if (result.error) throw new RegistrationError(result.error);
    return result.user!;
  } catch (error) {
    if ((error as { code?: string }).code === "23505") throw new RegistrationError("邮箱或用户名已被使用", 409);
    throw error;
  }
}
