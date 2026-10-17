import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { FIRST_QUESTION, normalizeQuestionPresentation, newSession, SessionSchema } from "./onboarding-contracts.js";
import { nextInterview } from "./onboarding-ai.js";
import { sanitizeInterviewSession } from "./onboarding-evidence.js";
import { advanceOnboarding } from "./onboarding.js";

const aiConfig = vi.hoisted(() => ({ aiApiKey: "test-only", aiBaseUrl: "https://ai.invalid", aiModel: "test", aiReasoningEffort: "max" }));
vi.mock("./config.js", () => ({ config: aiConfig }));
const fetchMock = vi.fn<typeof fetch>();
const sessionForMaterials = () => ({ ...newSession(), answers: [
  { question: FIRST_QUESTION, answer: "从零学习Python，能独立做数据分析" },
  { question: "目前基础与困难？", answer: "Python基础学过，文件读写有困难" },
  { question: "希望达到什么结果？", answer: "完成CSV清理脚本" },
  { question: "每天投入多久？", answer: "每天2小时，周日休息" },
] });
const respond = (extra: Record<string, unknown> = {}) => {
  fetchMock.mockResolvedValue(Response.json({ choices: [{ message: { content: JSON.stringify({
    question: "你正在用哪些教材或课程？", question_fields: ["materials"], profile: newSession().profile, ...extra,
  }) } }] }));
};
beforeEach(() => {
  vi.useFakeTimers(); vi.setSystemTime(new Date("2026-10-17T04:00:00Z"));
  fetchMock.mockReset(); vi.stubGlobal("fetch", fetchMock);
});
afterEach(() => { vi.useRealTimers(); vi.unstubAllGlobals(); });

describe("AI-selected interview response modes", () => {
  it("uses the explicit text mode even if the model accidentally includes options", async () => {
    respond({ question_type: "text", question_options: ["教材", "网课"], question_multiple: true });
    const result = await nextInterview(sessionForMaterials());
    expect(result).toMatchObject({ question_type: "text", question_options: [], question_multiple: false });
    const prompt = JSON.parse(String(fetchMock.mock.calls[0][1]?.body)).messages[0].content;
    expect(prompt).toContain("由你逐题决定");
    expect(prompt).not.toContain("尽可能给3到6个");
  });
  it("lets the AI choose single choice for the same information field", async () => {
    respond({ question_type: "single_choice", question_options: ["教材", "网课", "边做边查"], question_multiple: true });
    const result = await nextInterview(sessionForMaterials());
    expect(result).toMatchObject({ question_type: "single_choice", question_options: ["教材", "网课", "边做边查"], question_multiple: false });
  });
  it("lets the AI choose multiple choice and carries the type through the saved session", async () => {
    respond({ question_type: "multiple_choice", question_options: ["教材", "网课"], question_multiple: false });
    const next = await advanceOnboarding({ ...sessionForMaterials(), question: "还有什么补充？" }, { type: "answer", answer: "想先了解可用资料" });
    expect(next.question_type).toBe("multiple_choice");
    expect(next.question_multiple).toBe(true);
    expect(sanitizeInterviewSession(SessionSchema.parse(next)).question_type).toBe("multiple_choice");
  });
  it("preserves the model's text exam clarification instead of forcing category buttons", async () => {
    respond({ question: "你准备参加什么考试？可以填写具体考试名称。", question_fields: [], question_type: "text", question_options: [] });
    const next = await advanceOnboarding(newSession(), { type: "answer", answer: "考试备考" });
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(next.question_type).toBe("text");
    expect(next.question).toContain("具体考试名称");
    const restored = sanitizeInterviewSession(SessionSchema.parse(next));
    expect(restored.question_type).toBe("text");
    expect(restored.question).toBe(next.question);
  });
  it("conservatively infers old drafts and normalizes empty option sets", () => {
    expect(normalizeQuestionPresentation({ question_options: ["A", "B"] }).question_type).toBe("single_choice");
    expect(normalizeQuestionPresentation({ question_options: ["A", "B"], question_multiple: true }).question_type).toBe("multiple_choice");
    expect(normalizeQuestionPresentation({ question_options: [] }).question_type).toBe("text");
    expect(normalizeQuestionPresentation({ question_type: "multiple_choice", question_options: ["其他"] }))
      .toEqual({ question_type: "text", question_options: [], question_multiple: false });
    const saved = SessionSchema.parse({ ...newSession(), question_type: "text", question_options: ["A", "B"], question_multiple: true });
    expect(sanitizeInterviewSession(saved)).toMatchObject({ question_type: "text", question_options: [], question_multiple: false });
  });
  it("still clarifies exam identity before an unrelated date question", async () => {
    respond({ question: "你准备哪一年参加考试？", question_fields: [], question_type: "text", question_options: [] });
    const next = await advanceOnboarding(newSession(), { type: "answer", answer: "考试备考" });
    expect(next.question).toBe("你准备参加哪一类考试？");
    expect(next.profile.goal_subtype).toBe("");
  });
});
