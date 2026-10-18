import "dotenv/config";

const required = (name: string, fallback = "") => process.env[name]?.trim() || fallback;
export type AIReasoningEffort = "none" | "low" | "high" | "max";

function reasoningEffort(name: string, fallback: AIReasoningEffort): AIReasoningEffort {
  const value = required(name, fallback);
  if (!["none", "low", "high", "max"].includes(value)) {
    throw new Error(`${name} must be one of: none, low, high, max`);
  }
  return value as AIReasoningEffort;
}

export const config = {
  port: Number(process.env.PORT || 8787),
  databaseUrl: required("DATABASE_URL", "postgres://planner:planner@localhost:5432/planner"),
  accessSecret: required("JWT_ACCESS_SECRET", "development-access-secret-change-me"),
  refreshSecret: required("JWT_REFRESH_SECRET", "development-refresh-secret-change-me"),
  webOrigin: required("WEB_ORIGIN", "http://127.0.0.1:5180"),
  aiBaseUrl: required("AI_BASE_URL", "https://api.openai.com/v1").replace(/\/$/, ""),
  aiApiKey: required("AI_API_KEY"),
  aiModel: required("AI_MODEL", "deepseek-flash"),
  aiReasoningEffort: reasoningEffort("AI_REASONING_EFFORT", "max"),
  aiSimpleReasoningEffort: reasoningEffort("AI_SIMPLE_REASONING_EFFORT", "low"),
  aiPlanningReasoningEffort: reasoningEffort("AI_PLANNING_REASONING_EFFORT", "high"),
  researchProvider: required("RESEARCH_SEARCH_PROVIDER", process.env.NODE_ENV === "test" ? "disabled" : "bing"),
  researchApiKey: required("RESEARCH_SEARCH_API_KEY"),
  smtpHost: required("SMTP_HOST", "smtp.qq.com"),
  smtpPort: Number(required("SMTP_PORT", "465")),
  smtpUser: required("SMTP_USER"),
  smtpPass: required("SMTP_PASS"),
  smtpFrom: required("SMTP_FROM", required("SMTP_USER")),
};

if (process.env.NODE_ENV === "production" &&
    (config.accessSecret.includes("change-me") || config.refreshSecret.includes("change-me"))) {
  throw new Error("JWT_ACCESS_SECRET and JWT_REFRESH_SECRET must be set in production");
}
