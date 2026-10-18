import { beforeEach, describe, expect, it, vi } from "vitest";

const queryMock = vi.hoisted(() => vi.fn());
const configMock = vi.hoisted(() => ({ researchProvider: "bing", researchApiKey: "", researchLibraryDocumentDays: 30,
  researchLibrarySearchDays: 7, aiApiKey: "", aiBaseUrl: "https://ai.invalid", aiModel: "test",
  aiReasoningEffort: "none", aiSimpleReasoningEffort: "none", aiPlanningReasoningEffort: "none" }));
vi.mock("./db.js", () => ({ query: queryMock }));
vi.mock("./config.js", () => ({ config: configMock }));

import { attachExamResearch, expireExamResearch, libraryDocument, libraryNote, librarySearch, researchCacheSeconds,
  saveLibraryDocument } from "./exam-research.js";
import { ResearchSchema } from "./learning-context.js";
import { newSession } from "./onboarding-contracts.js";

const url = "https://yzb.sjtu.edu.cn/catalogue.html";

beforeEach(() => {
  queryMock.mockReset();
  queryMock.mockResolvedValue({ rows: [], rowCount: 0 });
});

describe("official research library", () => {
  it("keeps verified results for 30 days and error results for 10 minutes", () => {
    expect(researchCacheSeconds("verified")).toBe(30 * 86_400);
    expect(researchCacheSeconds("reference")).toBe(7 * 86_400);
    expect(researchCacheSeconds("not_found")).toBe(86_400);
    expect(researchCacheSeconds("error")).toBe(600);
    expect(researchCacheSeconds("pending")).toBe(3_600);
  });

  it("labels cached research as coming from the local library without duplicating the note", () => {
    const verified = ResearchSchema.parse({ status: "verified", checked_at: "2026-10-18T09:00:00.000Z", message: "已核对官方资料" });
    expect(libraryNote(verified).message).toBe("已核对官方资料（本地资料库，更新于 2026-10-18）");
    // 上海时区：UTC 16:30 已经是次日。
    expect(libraryNote(ResearchSchema.parse({ status: "reference", checked_at: "2026-10-18T16:30:00.000Z",
      message: "已找到参考资料，目标年度或报考范围仍待核实" })).message).toContain("更新于 2026-10-19");
    const once = libraryNote(verified);
    expect(libraryNote(once).message).toBe(once.message);
    const pending = ResearchSchema.parse({ status: "pending", message: "正在核对官方考试资料…" });
    expect(libraryNote(pending)).toEqual(pending);
  });

  it("reuses a stored official page without touching the network while it is fresh", async () => {
    const fetchedAt = new Date("2026-10-17T08:00:00.000Z");
    queryMock.mockResolvedValueOnce({ rows: [{ title: "招生目录", text: "408 数据结构 计算机组成原理", links: [{ url: `${url}.pdf`, title: "目录" }], fetched_at: fetchedAt }], rowCount: 1 });
    const fetcher = vi.fn();
    const document = await libraryDocument(url, { maxAgeMs: 5_000, fetch: fetcher });
    expect(fetcher).not.toHaveBeenCalled();
    expect(document).toMatchObject({ url, title: "招生目录", links: [{ url: `${url}.pdf`, title: "目录" }] });
    expect(document.fetched_at).toBe(fetchedAt.toISOString());
    const [select, params] = queryMock.mock.calls[0] as [string, unknown[]];
    expect(select).toContain("exam_research_documents");
    expect(params).toEqual([url, 5_000]);
  });

  it("fetches and stores an official page only when the library has no fresh copy", async () => {
    const fresh = { url, title: "新抓取", text: "考试科目", fetched_at: new Date().toISOString() };
    const fetcher = vi.fn(async () => fresh);
    const document = await libraryDocument(url, { fetch: fetcher });
    expect(fetcher).toHaveBeenCalledWith(url);
    expect(document).toBe(fresh);
    const insert = queryMock.mock.calls.find(([sql]) => String(sql).includes("insert into exam_research_documents"));
    expect(insert).toBeTruthy();
    expect((insert![1] as unknown[])[0]).toBe(url);
  });

  it("truncates oversized page text before persisting it", async () => {
    await saveLibraryDocument({ url, title: "t", text: "x".repeat(200_000), fetched_at: new Date().toISOString() });
    const insert = queryMock.mock.calls.at(-1)!;
    expect((insert[1] as unknown[])[2]).toHaveLength(150_000);
  });

  it("reuses cached search hits including negative results, and stores fresh hits", async () => {
    queryMock.mockResolvedValueOnce({ rows: [{ urls: [`${url}.pdf`] }], rowCount: 1 });
    const fetcher = vi.fn();
    expect(await librarySearch("上海交通大学 计算机技术 招生专业目录", { fetch: fetcher })).toEqual([`${url}.pdf`]);
    expect(fetcher).not.toHaveBeenCalled();
    // 没有命中结果的查询也缓存，避免每次访谈都重复搜索。
    queryMock.mockResolvedValueOnce({ rows: [{ urls: [] }], rowCount: 1 });
    expect(await librarySearch("没有结果的查询", { fetch: fetcher })).toEqual([]);
    expect(fetcher).not.toHaveBeenCalled();
    queryMock.mockResolvedValue({ rows: [], rowCount: 0 });
    const freshFetcher = vi.fn(async () => [url]);
    expect(await librarySearch("新的查询", { fetch: freshFetcher })).toEqual([url]);
    expect(freshFetcher).toHaveBeenCalledWith("新的查询");
    expect(queryMock.mock.calls.some(([sql]) => String(sql).includes("insert into exam_research_searches"))).toBe(true);
  });

  it("serves an unexpired target result from the local library and marks it in the message", async () => {
    const session = newSession();
    session.profile = { ...session.profile, goal_type: "exam", goal_subtype: "考研", target_school: "上海交通大学", target_program: "计算机技术" };
    session.answers = [{ question: "目标是什么？", answer: "大三考研，上海交通大学计算机技术" }];
    session.learning_context.facts.school = { value: "上海交通大学", answer_index: 0, quote: "上海交通大学" };
    const payload = ResearchSchema.parse({ key: "cached-key", status: "verified", checked_at: "2026-10-18T09:00:00.000Z",
      message: "已核对官方资料", facts: [{ statement: "计算机技术专硕初试含408", subjects: ["408"], source_url: url,
        quote: "408 计算机学科专业基础", applicable_year: 2027, reference_only: false }], sources: [{ url, title: "招生目录", fetched_at: "2026-10-18T09:00:00.000Z" }] });
    queryMock.mockResolvedValueOnce({ rows: [{ payload }], rowCount: 1 });
    const result = await attachExamResearch(session);
    expect(result.research.status).toBe("verified");
    expect(result.research.message).toContain("本地资料库");
    expect(result.research.facts).toHaveLength(1);
  });

  it("marks a target for forced online refresh when the user asks to re-check", async () => {
    const session = newSession();
    session.research = ResearchSchema.parse({ key: "target-key", status: "verified", message: "已核对官方资料" });
    await expireExamResearch(session);
    const expire = queryMock.mock.calls.find(([sql]) => String(sql).includes("update exam_research_cache set expires_at=now()"));
    expect(expire).toBeTruthy();
    expect((expire![1] as unknown[])[0]).toBe("target-key");
  });
});
