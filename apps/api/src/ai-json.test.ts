import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { z } from "zod";
import { AI_REQUEST_TIMEOUT_MS, requestStructuredAI, SHARED_SYSTEM_PROMPT } from "./ai-json.js";
import { generateItems } from "./onboarding-ai.js";
import { newSession } from "./onboarding-contracts.js";

vi.mock("./config.js", () => ({
  config: { aiApiKey: "test-key", aiBaseUrl: "https://ai.invalid", aiModel: "test", aiReasoningEffort: "max",
    aiSimpleReasoningEffort: "low", aiPlanningReasoningEffort: "high" },
}));

const fetchMock = vi.fn<typeof fetch>();
const schema = z.object({ value: z.string() });
const timeoutMessage = /超时.*重试.*已有进度|超时.*已有进度.*重试/;
const validResponse = (result: unknown) => Response.json({ choices: [{ message: { content: JSON.stringify(result) } }] });

function rejectOnAbort<T>(signal: AbortSignal, error?: Error): Promise<T> {
  return new Promise((_, reject) => {
    signal.addEventListener("abort", () => reject(error ?? signal.reason), { once: true });
  });
}

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(new Date("2026-10-18T04:00:00Z"));
  fetchMock.mockReset();
  vi.stubGlobal("fetch", fetchMock);
  // Native AbortSignal.timeout uses Node's internal timers, outside Vitest's clock.
  vi.spyOn(AbortSignal, "timeout").mockImplementation(milliseconds => {
    const controller = new AbortController();
    setTimeout(() => controller.abort(new DOMException("The operation was aborted due to timeout", "TimeoutError")), milliseconds);
    return controller.signal;
  });
});

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
  vi.useRealTimers();
});

describe("structured AI request timeouts", () => {
  it("allows item generation to finish after the former 65-second limit", async () => {
    const session = newSession();
    session.courses = [{ id: "course-1", name: "Reading", description: "", priority: 2 }];
    const item = { id: "item-1", course_id: "course-1", title: "Read a chapter", estimated_minutes: 60, deadline: "2026-11-14", deadline_kind: "plan_end", priority: 2 };
    fetchMock.mockImplementation(async (_url, options) => {
      const signal = options!.signal!;
      const delayed = new Promise<Response>(resolve => setTimeout(() => resolve(validResponse({ items: [item], summary: "", assumptions: [], warnings: [] })), 70_000));
      return Promise.race([delayed, rejectOnAbort<Response>(signal)]);
    });

    const request = generateItems(session);
    const result = expect(request).resolves.toMatchObject({ items: [item] });
    await vi.advanceTimersByTimeAsync(70_000);
    await result;

    expect(AI_REQUEST_TIMEOUT_MS).toBe(210_000);
    expect(AbortSignal.timeout).toHaveBeenCalledWith(AI_REQUEST_TIMEOUT_MS);
    expect(fetchMock.mock.calls[0][1]!.signal!.aborted).toBe(false);
    expect(JSON.parse(String(fetchMock.mock.calls[0][1]!.body)).reasoning_effort).toBe("high");
  });

  it("selects reasoning per request without changing the fallback for other callers", async () => {
    fetchMock.mockImplementation(async () => validResponse({ value: "ok" }));
    await requestStructuredAI(schema, "instructions", {}, { reasoningEffort: "low", timeoutMs: 30_000 });
    await requestStructuredAI(schema, "instructions", {}, { reasoningEffort: "high" });
    await requestStructuredAI(schema, "instructions", {});

    expect(fetchMock.mock.calls.map(([, options]) => JSON.parse(String(options!.body)).reasoning_effort))
      .toEqual(["low", "high", "max"]);
    expect(AbortSignal.timeout).toHaveBeenNthCalledWith(1, 30_000);
    expect(AbortSignal.timeout).toHaveBeenNthCalledWith(2, AI_REQUEST_TIMEOUT_MS);
  });

  it("explains a timeout while waiting for response headers", async () => {
    fetchMock.mockImplementation(async (_url, options) => rejectOnAbort<Response>(options!.signal!));

    const request = requestStructuredAI(schema, "instructions", {});
    const result = expect(request).rejects.toThrow(timeoutMessage);
    await vi.advanceTimersByTimeAsync(AI_REQUEST_TIMEOUT_MS);
    await result;
  });

  it("explains a timeout while reading the response body", async () => {
    fetchMock.mockImplementation(async (_url, options) => {
      const response = new Response(null, { status: 200 });
      vi.spyOn(response, "json").mockImplementation(() => rejectOnAbort(options!.signal!, new DOMException("The operation was aborted", "AbortError")));
      return response;
    });

    const request = requestStructuredAI(schema, "instructions", {});
    const result = expect(request).rejects.toThrow(timeoutMessage);
    await vi.advanceTimersByTimeAsync(AI_REQUEST_TIMEOUT_MS);
    await result;
  });

  it("keeps an explicitly shorter timeout for bounded repair attempts", async () => {
    fetchMock.mockImplementation(async (_url, options) => rejectOnAbort<Response>(options!.signal!));
    let settled = false;
    const request = requestStructuredAI(schema, "instructions", {}, 1_000);
    void request.then(() => { settled = true; }, () => { settled = true; });
    const result = expect(request).rejects.toThrow(timeoutMessage);

    await vi.advanceTimersByTimeAsync(999);
    expect(settled).toBe(false);
    await vi.advanceTimersByTimeAsync(1);
    await result;
    expect(AbortSignal.timeout).toHaveBeenCalledWith(1_000);
  });

  it("preserves unrelated transport and JSON failures", async () => {
    const transportError = new TypeError("fetch failed");
    fetchMock.mockRejectedValueOnce(transportError);
    await expect(requestStructuredAI(schema, "instructions", {})).rejects.toBe(transportError);

    const parseError = new SyntaxError("Unexpected token");
    const response = new Response(null, { status: 200 });
    vi.spyOn(response, "json").mockRejectedValue(parseError);
    fetchMock.mockResolvedValueOnce(response);
    await expect(requestStructuredAI(schema, "instructions", {})).rejects.toBe(parseError);
  });

  it("preserves the actionable upstream HTTP error", async () => {
    fetchMock.mockResolvedValueOnce(new Response(null, { status: 503 }));
    await expect(requestStructuredAI(schema, "instructions", {})).rejects.toThrow("AI 请求失败（503），请重试");
  });

  it("shares one byte-identical system prefix across tasks and keeps user data after it", async () => {
    fetchMock.mockImplementation(async () => validResponse({ value: "ok" }));
    await requestStructuredAI(schema, "任务A指令", { a: 1 }, { label: "task-a" });
    await requestStructuredAI(schema, "任务B指令", { b: 2 }, { label: "task-b" });

    const bodies = fetchMock.mock.calls.map(([, options]) => JSON.parse(String(options!.body)));
    const systems = bodies.map(body => body.messages[0]);
    expect(systems[0].role).toBe("system");
    expect(systems[0].content.startsWith(`${SHARED_SYSTEM_PROMPT}\n`)).toBe(true);
    expect(systems[1].content.startsWith(`${SHARED_SYSTEM_PROMPT}\n`)).toBe(true);
    expect(systems[0].content).toContain("任务A指令");
    expect(systems[1].content).toContain("任务B指令");
    // The provider can cache exactly this shared prefix for every AI call in the app.
    const sharedPrefixLength = SHARED_SYSTEM_PROMPT.length + 1;
    expect(systems[0].content.slice(0, sharedPrefixLength)).toBe(systems[1].content.slice(0, sharedPrefixLength));
    expect(bodies[0].messages[1].role).toBe("user");
    expect(JSON.parse(bodies[0].messages[1].content)).toEqual({ a: 1 });
    expect(JSON.parse(bodies[1].messages[1].content)).toEqual({ b: 2 });
  });

  it("logs cache hit and miss tokens per labelled call", async () => {
    const info = vi.spyOn(console, "info").mockImplementation(() => {});
    fetchMock.mockResolvedValueOnce(Response.json({
      choices: [{ message: { content: JSON.stringify({ value: "ok" }) } }],
      usage: { prompt_tokens: 1200, completion_tokens: 30, prompt_cache_hit_tokens: 900, prompt_cache_miss_tokens: 300 },
    }));
    await requestStructuredAI(schema, "instructions", {}, { label: "interview" });

    const line = info.mock.calls.map(call => String(call[0])).find(text => text.includes('"ai_usage"'));
    expect(line).toBeTruthy();
    expect(JSON.parse(line!)).toMatchObject({ event: "ai_usage", label: "interview", model: "test",
      prompt_tokens: 1200, cache_hit_tokens: 900, cache_miss_tokens: 300, completion_tokens: 30 });
  });
});
