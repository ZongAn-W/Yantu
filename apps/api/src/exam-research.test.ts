import { afterEach, describe, expect, it, vi } from "vitest";
import { extractionDocuments, officialSource, readOfficialDocument, researchExam, type ResearchDependencies } from "./exam-research.js";

vi.mock("node:dns/promises", () => ({ lookup: vi.fn(async () => [{ address: "203.0.113.1", family: 4 }]) }));
const target = { exam: "考研", school: "上海交通大学", college: "", program: "计算机技术", degree: "专硕", admission_year: 2028, subject_codes: ["408"] };
const quote = "2028年 上海交通大学 计算机技术 专硕 初试考试科目：英语一、数学一、408。";
function dependencies(overrides: Partial<ResearchDependencies> = {}): ResearchDependencies {
  return {
    search: async () => ["https://yzb.sjtu.edu.cn/catalogue"],
    document: async url => ({ url, title: "上海交通大学2028年招生目录", text: quote + " 详细要求与调整请查看对应专业目录及公告。", fetched_at: "2026-10-17T04:00:00Z" }),
    extract: async () => ({ facts: [{ statement: "计算机技术专硕初试含英语一、数学一及408", subjects: ["英语一", "数学一", "408"], source_index: 0, quote, applicable_year: 2028 }] }),
    ...overrides,
  };
}
afterEach(() => vi.unstubAllGlobals());

describe("official exam research", () => {
  it("requires real official-source quotes, target scope and matching admission year", async () => {
    const result = await researchExam(target, dependencies());
    expect(result.status).toBe("verified");
    expect(result.facts[0]).toMatchObject({ applicable_year: 2028, reference_only: false, source_url: "https://yzb.sjtu.edu.cn/catalogue" });
  });

  it("labels a previous year's requirement as reference, not a current fact", async () => {
    const result = await researchExam({ ...target, admission_year: 2029 }, dependencies());
    expect(result.status).toBe("reference");
    expect(result.facts[0].reference_only).toBe(true);
  });

  it("rejects invented quotes and subjects not supported by the cited text", async () => {
    const result = await researchExam(target, dependencies({ extract: async () => ({ facts: [
      { statement: "考英语二", subjects: ["英语二"], source_index: 0, quote, applicable_year: 2028 },
      { statement: "考英语一", subjects: ["英语一"], source_index: 0, quote: "这是模型杜撰的招生内容，不在原文之中", applicable_year: 2028 },
    ] }) }));
    expect(result.facts).toEqual([]);
    expect(result.status).toBe("not_found");
  });

  it("does not use the requirements of a different degree or university", async () => {
    expect((await researchExam({ ...target, degree: "学硕" }, dependencies())).facts).toEqual([]);
    expect((await researchExam({ ...target, school: "西安交通大学" }, dependencies())).facts).toEqual([]);
  });

  it("returns a nonblocking failure when search is unavailable", async () => {
    const result = await researchExam(target, dependencies({ search: async () => { throw new Error("timeout"); } }));
    expect(result.status).toBe("error");
    expect(result.message).toContain("继续");
  });

  it("filters private URLs, fake official domains and non-HTTPS sources", () => {
    for (const url of ["http://yzb.sjtu.edu.cn/", "https://127.0.0.1/", "https://www.chsi.com.cn.evil.test/", "https://user:pass@yzb.sjtu.edu.cn/"]) expect(officialSource(url)).toBe(false);
    expect(officialSource("https://yzb.sjtu.edu.cn/catalogue.pdf")).toBe(true);
  });

  it("marks contradictory current-year subject requirements as unresolved reference", async () => {
    const second = quote.replace("英语一", "英语二");
    const result = await researchExam(target, dependencies({
      document: async url => ({ url, title: target.school, text: quote + second, fetched_at: "2026-10-17T04:00:00Z" }),
      extract: async () => ({ facts: [
        { statement: "目录第一条含英语一", subjects: ["英语一"], source_index: 0, quote, applicable_year: 2028 },
        { statement: "另一学院的目录含英语二", subjects: ["英语二"], source_index: 0, quote: second, applicable_year: 2028 },
      ] }),
    }));
    expect(result.status).toBe("reference");
    expect(result.message).toContain("冲突");
    expect(result.facts.every(fact => fact.reference_only)).toBe(true);
  });

  it("follows official catalogue links without turning navigation hints into evidence", async () => {
    const doc = dependencies().document;
    const result = await researchExam(target, dependencies({
      search: async () => [],
      discover: async () => ["https://yzb.sjtu.edu.cn/"],
      document: async url => url.endsWith('/')
        ? { url, title: target.school, text: "上海交通大学研究生招生官方网站，以下是硕士研究生招生专业目录和相关公告。", fetched_at: "2026-10-17T04:00:00Z", links: [{url:"https://yzb.sjtu.edu.cn/catalogue",title:"2028年硕士研究生招生专业目录"}] }
        : doc(url),
    }));
    expect(result.status).toBe("verified");
    expect(result.sources).toHaveLength(1);
    expect(result.sources[0].url).toContain("catalogue");
  });

  it("parses HTML content rather than treating embedded scripts as source evidence", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response('<html><head><title>官方目录</title></head><body><script>英语二</script><table><tr><td>计算机技术</td><td>英语一</td></tr></table></body></html>', { headers: { "content-type": "text/html;charset=utf-8" } })));
    const document = await readOfficialDocument("https://yzb.sjtu.edu.cn/catalogue");
    expect(document.title).toBe("官方目录");
    expect(document.text).toContain("计算机技术");
    expect(document.text).not.toContain("英语二");
  });

  it("sends only trimmed page text to extraction and drops navigation links and fetch metadata", () => {
    const documents = extractionDocuments([{
      url: "https://yzb.sjtu.edu.cn/catalogue",
      title: "上海交通大学2028年招生目录",
      text: quote + "x".repeat(40_000),
      fetched_at: "2026-10-17T04:00:00Z",
      links: Array.from({ length: 500 }, (_, index) => ({ url: `https://yzb.sjtu.edu.cn/nav/${index}`, title: `导航${index}` })),
    }], target);
    expect(documents).toHaveLength(1);
    expect(Object.keys(documents[0])).toEqual(["url", "title", "text"]);
    expect(documents[0].text).toContain(quote);
    // Unique navigation URLs and fetch metadata would be uncacheable dead weight in the prompt.
    expect(documents[0].text.length).toBeLessThanOrEqual(16_000);
  });
});
