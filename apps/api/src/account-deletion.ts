import argon2 from "argon2";
import { transaction } from "./db.js";

export class AccountDeletionError extends Error {
  constructor(message: string, public readonly status: number, public readonly retryAfter?: number) { super(message); }
}

/** The caller's identity must come from a verified access token, never the body. */
export async function deleteAccount(owner: string, password: string): Promise<void> {
  for (let attempt = 0; ; attempt++) {
    try {
      const failure = await transaction(async client => {
        const candidate = (await client.query<{ email: string }>("select email from users where id=$1", [owner])).rows[0];
        // An already committed deletion is a successful retry. Do not touch the
        // email's records here: someone may have registered a new account since.
        if (!candidate) return null;
        // Registration uses this same email lock before touching users/codes.
        await client.query("select pg_advisory_xact_lock(hashtextextended($1, 0))", [candidate.email.toLowerCase()]);
        const user = (await client.query<{ email: string; password_hash: string }>(
          "select email,password_hash from users where id=$1 for update", [owner],
        )).rows[0];
        if (!user) return null;
        const previous = (await client.query<{ attempts: number; retry_after: number }>(
          "select attempts,ceil(extract(epoch from window_started_at+interval '15 minutes'-now()))::int as retry_after from account_deletion_attempts where user_id=$1", [owner],
        )).rows[0];
        if (previous && previous.retry_after > 0 && previous.attempts >= 5)
          return new AccountDeletionError("密码尝试次数过多，请稍后重试", 429, previous.retry_after);
        if (!(await argon2.verify(user.password_hash, password))) {
          await client.query(`insert into account_deletion_attempts(user_id,attempts,window_started_at) values($1,1,now())
            on conflict(user_id) do update set
              attempts=case when account_deletion_attempts.window_started_at<=now()-interval '15 minutes' then 1 else account_deletion_attempts.attempts+1 end,
              window_started_at=case when account_deletion_attempts.window_started_at<=now()-interval '15 minutes' then now() else account_deletion_attempts.window_started_at end`, [owner]);
          // Commit failed attempts so another IP or API instance cannot reset them.
          return new AccountDeletionError("当前密码错误，账号未注销", 403);
        }
        // Sync obtains a user lock before this state lock too. The user lock
        // blocks new FK writes/refresh rotations until this transaction commits.
        await client.query("select user_id from planner_sync_state where user_id=$1 for update", [owner]);
        // 学习事实先于事项/账号删除，保持删除顺序确定；其余子表都由外键级联清理。
        await client.query("delete from study_logs where user_id=$1", [owner]);
        await client.query("delete from registration_codes where lower(email)=lower($1)", [user.email]);
        await client.query("delete from users where id=$1", [owner]);
        return null;
      });
      if (failure) throw failure;
      return;
    } catch (error) {
      // Legacy relational writers can already hold a child row. PostgreSQL
      // aborts one participant; retry the entire atomic operation on contention.
      if (attempt < 2 && ["40001", "40P01"].includes((error as { code?: string }).code ?? "")) continue;
      throw error;
    }
  }
}
