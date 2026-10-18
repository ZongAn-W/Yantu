import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

beforeEach(() => {
  vi.resetModules();
  for (const name of ["AI_REASONING_EFFORT", "AI_SIMPLE_REASONING_EFFORT", "AI_PLANNING_REASONING_EFFORT"]) vi.stubEnv(name, "");
});
afterEach(() => vi.unstubAllEnvs());

describe("AI reasoning configuration", () => {
  it("uses faster onboarding tiers independently of the existing global setting", async () => {
    vi.stubEnv("AI_REASONING_EFFORT", "max");
    const { config } = await import("./config.js");
    expect(config).toMatchObject({ aiReasoningEffort: "max", aiSimpleReasoningEffort: "low", aiPlanningReasoningEffort: "high" });
  });

  it("allows the simple and planning tiers to be tuned separately", async () => {
    vi.stubEnv("AI_SIMPLE_REASONING_EFFORT", "none");
    vi.stubEnv("AI_PLANNING_REASONING_EFFORT", "max");
    const { config } = await import("./config.js");
    expect(config).toMatchObject({ aiSimpleReasoningEffort: "none", aiPlanningReasoningEffort: "max" });
  });

  it.each(["AI_REASONING_EFFORT", "AI_SIMPLE_REASONING_EFFORT", "AI_PLANNING_REASONING_EFFORT"])("rejects unsupported values for %s at startup", async name => {
    vi.stubEnv(name, "invalid");
    await expect(import("./config.js")).rejects.toThrow(`${name} must be one of: none, low, high, max`);
  });
});
