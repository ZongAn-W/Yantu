import { afterAll, describe, expect, it, vi } from "vitest";
import { randomUUID } from "node:crypto";
import { newSession } from "./onboarding-contracts.js";
import { attachExamResearch, libraryDocument, librarySearch, type ResearchDependencies } from "./exam-research.js";
import { query, pool } from "./db.js";
vi.mock("./config.js", async importOriginal => ({ config: { ...(await importOriginal<typeof import("./config.js")>()).config, researchProvider: "bing" } }));

describe.skipIf(!process.env.AUTH_TEST_DATABASE_URL)("persisted official research jobs", () => {
  afterAll(async () => { await pool.end(); });

  it("persists fetched official pages and search hits so later checks can reuse them offline", async () => {
    const unique = randomUUID();
    const pageUrl = `https://yzb.sjtu.edu.cn/library-${unique}.html`;
    const search = `本地资料库隔离查询 ${unique}`;
    const page = { url: pageUrl, title: "招生目录", text: "408 计算机学科专业基础 数据结构 计算机组成原理 操作系统 计算机网络", fetched_at: new Date().toISOString() };
    expect(await libraryDocument(pageUrl, { fetch: async () => page })).toMatchObject({ url: pageUrl, title: "招生目录" });
    // 第二次必须命中本地资料库，不允许再联网。
    expect(await libraryDocument(pageUrl, { fetch: async () => { throw new Error("不应联网抓取"); } })).toMatchObject({ title: "招生目录" });
    expect(await librarySearch(search, { fetch: async () => [pageUrl] })).toEqual([pageUrl]);
    expect(await librarySearch(search, { fetch: async () => { throw new Error("不应联网搜索"); } })).toEqual([pageUrl]);
    const stored = await query<{ text: string }>("select text from exam_research_documents where url=$1", [pageUrl]);
    expect(stored.rows[0]?.text).toContain("408");
    await query("delete from exam_research_documents where url=$1", [pageUrl]);
    await query("delete from exam_research_searches where search_query=$1", [search]);
  });

  it("shares public results, does not change session revisions, and separates changed goals from late jobs", async () => {
    const school = `隔离${randomUUID().slice(0, 8)}大学`;
    const session = newSession();
    session.profile = { ...session.profile, goal_type: "exam", goal_subtype: "考研", target_school: school, target_program: "计算机技术" };
    session.answers = [{ question: "目标是什么？", answer: `大三，考研，${school}，计算机技术专硕，408` }];
    // The artificial school name is an explicit target; it never becomes a real user record.
    session.learning_context.facts.school = { value: school, answer_index: 0, quote: school };
    let release!: () => void;
    const hold = new Promise<void>(resolve => { release = resolve; });
    const searches = vi.fn(async () => { await hold; return ["https://yzb.sjtu.edu.cn/catalogue"]; });
    const quote = `${school} 2028年计算机技术专硕初试科目为英语一和408。`;
    const deps: ResearchDependencies = {
      search: searches,
      document: async url => ({ url, title: school, text: `${quote} 具体要求以对应年度专业目录和更新公告为准。`, fetched_at: new Date().toISOString() }),
      extract: async () => ({ facts: [{ statement: "计算机技术专硕初试含英语一和408", subjects: ["英语一", "408"], source_index: 0, quote, applicable_year: 2028 }] }),
    };
    const pending = await attachExamResearch(session, deps);
    const again = await attachExamResearch(session, deps);
    expect(pending.research.status).toBe("pending");
    expect(again.research.key).toBe(pending.research.key);
    expect(again.revision).toBe(session.revision);
    const nextExam = `CATTI-${randomUUID()}`;
    const changed = { ...session, profile: { ...session.profile, goal_subtype: nextExam, target_school: "", target_program: "" }, answers: [...session.answers, { question: "新的目标是什么？", answer: `不考研了，改为${nextExam}` }] };
    const other = await attachExamResearch(changed, deps);
    expect(other.research.key).not.toBe(pending.research.key);
    release();
    await vi.waitFor(async () => {
      const rows = await query<{ payload: { status: string } }>("select payload from exam_research_cache where cache_key in ($1,$2)", [pending.research.key, other.research.key]);
      expect(rows.rows).toHaveLength(2);
      expect(rows.rows.every(row => row.payload.status !== "pending")).toBe(true);
    });
    const completed = await attachExamResearch(session, deps);
    expect(completed.research.status).toBe("verified");
    const changedResult = await attachExamResearch(changed, deps);
    expect(changedResult.research.facts).toEqual([]);
    expect(completed.answers).toEqual(session.answers);
    // One job per target, even if multiple clients poll it.
    expect(searches.mock.calls.length).toBe(3);
  });
});
