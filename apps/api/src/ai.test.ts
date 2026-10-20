import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { createPlanDraft } from "./ai.js";
import { PlanDraftSchema, ProfileSchema } from "./contracts.js";

const aiConfig = vi.hoisted(() => ({
  aiApiKey: "test-key",
  aiBaseUrl: "https://ai.example.invalid",
  aiModel: "deepseek-flash",
  aiReasoningEffort: "max",
}));

vi.mock("./config.js", () => ({ config: aiConfig }));

const profile = ProfileSchema.parse({
  goal_text: "从零学习 Python，能处理 CSV 并完成数据分析练习",
  goal_type: "skill",
  plan_start_date: "2026-10-17",
  plan_end_date: "2027-12-25",
});
const draft = {
  items: [{
    id: "math-1", tag_names: ["数学", "薄弱项"], title: "极限练习", description: "练习极限计算",
    completion_criteria: "完成练习并订正", estimated_minutes: 60,
    deadline: "2027-12-25", deadline_kind: "deadline", priority: 3,
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
    expect(result.items).toHaveLength(2);
    expect(result.items[0].tag_names).toEqual([]);
    expect(result.items.every((item) => item.deadline === profile.plan_end_date)).toBe(true);
    expect(result.items.every((item) => item.deadline_kind === "plan_end")).toBe(true);
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

  it("provides numeric priority constraints and a valid typed JSON example", async () => {
    fetchMock.mockResolvedValue(Response.json({ choices: [{ message: { content: JSON.stringify(draft) } }] }));

    await createPlanDraft(profile);

    const request = JSON.parse(String(fetchMock.mock.calls[0][1]?.body));
    const prompt = JSON.parse(request.messages.find((message: { role: string }) => message.role === "user").content);
    const properties = prompt.output_schema.properties;
    expect(properties.items.items.properties.priority).toEqual({ type: "integer", enum: [1, 2, 3] });
    expect(properties.items.items.required).toContain("priority");
    expect(PlanDraftSchema.parse(prompt.example)).toEqual(prompt.example);
    expect(prompt.example.items[0]).not.toHaveProperty("course_id");
    expect(prompt.profile).toEqual(profile);
    expect(prompt.current_date).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  });

  it.each([
    ["invalid JSON", "not JSON"],
    ["an invalid draft", JSON.stringify({ items: [] })],
    ["numeric-string priorities", JSON.stringify({
      ...draft,
      items: draft.items.map((item) => ({ ...item, priority: "3" })),
    })],
    ["named priorities", JSON.stringify({
      ...draft,
      items: draft.items.map((item) => ({ ...item, priority: "high" })),
    })],
  ])("reports %s without returning a fallback draft", async (_name, content) => {
    fetchMock.mockResolvedValue(Response.json({ choices: [{ message: { content } }] }));

    await expect(createPlanDraft(profile)).rejects.toThrow();
  });
});
