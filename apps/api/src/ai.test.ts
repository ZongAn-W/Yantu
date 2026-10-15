import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { createPlanDraft } from "./ai.js";
import { ProfileSchema } from "./contracts.js";

const aiConfig = vi.hoisted(() => ({
  aiApiKey: "test-key",
  aiBaseUrl: "https://ai.example.invalid",
  aiModel: "deepseek-flash",
  aiReasoningEffort: "max",
}));

vi.mock("./config.js", () => ({ config: aiConfig }));

const profile = ProfileSchema.parse({ exam_type: "考研", exam_date: "2027-12-25" });
const draft = {
  courses: [{ id: "math", name: "数学", description: "数学复习", priority: 3 }],
  items: [{
    id: "math-1", course_id: "math", title: "极限练习", description: "练习极限计算",
    completion_criteria: "完成练习并订正", estimated_minutes: 60,
    deadline: "2027-12-25", priority: 3,
  }],
  analysis_summary: "按当前进度安排练习",
  assumptions: [],
  warnings: [],
};

describe("AI plan draft generation", () => {
  const fetchMock = vi.fn<typeof fetch>();

  beforeEach(() => {
    aiConfig.aiApiKey = "test-key";
    fetchMock.mockReset();
    vi.stubGlobal("fetch", fetchMock);
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("keeps deterministic planning available without an API key", async () => {
    aiConfig.aiApiKey = "";

    const result = await createPlanDraft(profile);

    expect(fetchMock).not.toHaveBeenCalled();
    expect(result.courses.map((course) => course.name)).toEqual(["数学", "英语", "专业课", "政治"]);
    expect(result.items).toHaveLength(8);
    expect(result.items.every((item) => item.deadline === profile.exam_date)).toBe(true);
  });

  it("returns validated model output using the configured model and reasoning effort", async () => {
    fetchMock.mockResolvedValue(Response.json({ choices: [{ message: { content: JSON.stringify(draft) } }] }));

    expect(await createPlanDraft(profile)).toEqual(draft);
    const [url, options] = fetchMock.mock.calls[0];
    expect(url).toBe("https://ai.example.invalid/chat/completions");
    expect(JSON.parse(String(options?.body))).toMatchObject({
      model: "deepseek-flash",
      reasoning_effort: "max",
    });
  });

  it("reports upstream failures when a key is configured", async () => {
    fetchMock.mockResolvedValue(new Response(null, { status: 503 }));

    await expect(createPlanDraft(profile)).rejects.toThrow("AI 请求失败（503）");
  });

  it.each([
    ["invalid JSON", "not JSON"],
    ["an invalid draft", JSON.stringify({ courses: [], items: [] })],
  ])("reports %s without returning a fallback draft", async (_name, content) => {
    fetchMock.mockResolvedValue(Response.json({ choices: [{ message: { content } }] }));

    await expect(createPlanDraft(profile)).rejects.toThrow();
  });
});
