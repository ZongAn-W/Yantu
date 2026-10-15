import type { PlannerData } from "@planner/engine";

export type ApiUser = { id: string; email: string };
export type ApiProfile = {
  exam_type: "考研" | "考公" | "其他";
  exam_date: string;
  target_school: string;
  target_program: string;
  current_progress: string;
  weekly_minutes: Record<string, number>;
  constraints_text: string;
};
export type ApiDraft = {
  courses: Array<{ id: string; name: string; description: string; priority: number }>;
  items: Array<{ id: string; course_id: string; title: string; description: string; completion_criteria: string; estimated_minutes: number; earliest_date?: string; deadline: string; priority: number }>;
  analysis_summary: string;
  assumptions: string[];
  warnings: string[];
};

export const apiBaseUrl = (import.meta.env.VITE_API_URL?.trim() || "").replace(/\/$/, "");
export const apiConfigured = Boolean(apiBaseUrl);

async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
  const options = { ...init, credentials: "include" as const, headers: { "content-type": "application/json", ...(init.headers || {}) } };
  let response = await fetch(`${apiBaseUrl}${path}`, options);
  if (response.status === 401 && path !== "/api/auth/refresh" && path !== "/api/auth/login" && path !== "/api/auth/register") {
    const refreshed = await fetch(`${apiBaseUrl}/api/auth/refresh`, { method: "POST", credentials: "include" });
    if (refreshed.ok) response = await fetch(`${apiBaseUrl}${path}`, options);
  }
  const body = await response.json().catch(() => ({})) as { error?: string } & T;
  if (!response.ok) throw new Error(body.error || `请求失败（${response.status}）`);
  return body;
}

export const apiLogin = (email: string, password: string) => request<{ user: ApiUser }>("/api/auth/login", { method: "POST", body: JSON.stringify({ email, password }) });
export const apiRegister = (email: string, password: string) => request<{ user: ApiUser }>("/api/auth/register", { method: "POST", body: JSON.stringify({ email, password }) });
export const apiMe = () => request<{ user: ApiUser }>("/api/me");
export const apiLogout = () => request<{ ok: true }>("/api/auth/logout", { method: "POST" });
export const apiGetProfile = () => request<{ profile: ApiProfile | null }>("/api/onboarding/profile");
export const apiSaveProfile = (profile: ApiProfile) => request<{ profile: ApiProfile }>("/api/onboarding/profile", { method: "POST", body: JSON.stringify(profile) });
export const apiCreateDraft = (profile: ApiProfile) => request<{ id: string; draft: ApiDraft }>("/api/ai/plan-drafts", { method: "POST", headers: { "Idempotency-Key": crypto.randomUUID() }, body: JSON.stringify(profile) });
export const apiConfirmDraft = (id: string, draft: ApiDraft) => request<{ confirmed: true }>(`/api/ai/plan-drafts/${id}/confirm`, { method: "POST", body: JSON.stringify({ draft }) });
export const apiSnapshot = () => request<{ data: PlannerData }>("/api/planner/snapshot");
export const apiRecordLog = (payload: { item_id: string; date: string; minutes: number; feedback?: string }) => request<{ log: { id: string } }>("/api/study-logs", { method: "POST", body: JSON.stringify(payload) });
export const apiSettleDay = (date: string, payload: { feedback: string; entries: Array<{ item_id: string; actual_minutes: number; completion_status: "not_started" | "partial" | "completed" | "skipped"; feedback: string }> }) => request<{ runId: string }>(`/api/daily-reviews/${date}/settle`, { method: "POST", body: JSON.stringify(payload) });
