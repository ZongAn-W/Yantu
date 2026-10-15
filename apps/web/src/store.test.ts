// @vitest-environment jsdom
import { act, cleanup, renderHook, waitFor } from "@testing-library/react";
import { createElement, type ReactNode } from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { createInitialData, LOCAL_STORAGE_KEY } from "./data";
import { BrowserPlannerStorage, defaultStorageMetadata } from "./storage";
import type { PlannerData } from "@planner/engine";

const cloud = vi.hoisted(() => ({ rpc: vi.fn(), session: { user: { id: "test-user" } }, listener: null as null | ((event: string, session: unknown) => void) }));
vi.mock("@supabase/supabase-js", () => ({
  createClient: () => ({
    rpc: cloud.rpc,
    auth: {
      onAuthStateChange: (listener: typeof cloud.listener) => { cloud.listener = listener; return { data: { subscription: { unsubscribe: vi.fn() } } }; },
      getSession: async () => ({ data: { session: cloud.session } }),
    },
    channel: () => { const channel = { on: () => channel, subscribe: vi.fn() }; return channel; },
    removeChannel: vi.fn(),
  }),
}));

const key = `${LOCAL_STORAGE_KEY}:cloud:test-user`;
const storage = new BrowserPlannerStorage();
let store: typeof import("./store");
const wrapper = ({ children }: { children: ReactNode }) => createElement(store.PlannerProvider, null, children);

async function seedAccount(local: PlannerData, base = local, pending = false) {
  await storage.save(key, local, { ...defaultStorageMetadata(), base, pending, revision: 4 });
}

function accountPlan(): PlannerData {
  return JSON.parse(JSON.stringify(createInitialData("2026-10-14"), (_key, value) => value === "local-demo" ? "test-user" : value));
}

beforeEach(async () => {
  cleanup();
  localStorage.clear();
  vi.resetModules();
  vi.stubEnv("VITE_SUPABASE_URL", "https://test.supabase.co");
  vi.stubEnv("VITE_SUPABASE_ANON_KEY", "test-public-key");
  cloud.rpc.mockReset();
  cloud.listener = null;
  Object.defineProperty(navigator, "onLine", { configurable: true, value: true });
  store = await import("./store");
});
afterEach(() => { cleanup(); vi.unstubAllEnvs(); });

describe("offline persistence and cloud recovery", () => {
  it("keeps offline edits, baseline and pending across closing and restarting", async () => {
    const base = accountPlan();
    await seedAccount(base);
    cloud.rpc.mockImplementation(async () => ({ data: null, error: { message: "network unavailable" } }));
    Object.defineProperty(navigator, "onLine", { configurable: true, value: false });
    const first = renderHook(() => store.usePlanner(), { wrapper });
    await waitFor(() => expect(first.result.current.syncStatus).toBe("offline"));
    act(() => first.result.current.setData((data) => ({ ...data, profile: { ...data.profile, target_school: "离线修改" } })));
    await waitFor(async () => expect((await storage.load(key)).metadata.pending).toBe(true));
    first.unmount();
    const restarted = renderHook(() => store.usePlanner(), { wrapper });
    await waitFor(() => expect(restarted.result.current.data.profile.target_school).toBe("离线修改"));
    const snapshot = await storage.load(key);
    expect(snapshot.metadata.base?.profile.target_school).toBe(base.profile.target_school);
    expect(snapshot.metadata.revision).toBe(4);
    expect(snapshot.metadata.pending).toBe(true);

    cloud.rpc.mockImplementation(async (command: string, args?: { p_data: PlannerData }) => command === "load_planner_state"
      ? { data: { data: base, revision: 4 }, error: null }
      : { data: { revision: 5 }, error: null });
    Object.defineProperty(navigator, "onLine", { configurable: true, value: true });
    act(() => window.dispatchEvent(new Event("online")));
    await waitFor(() => expect(restarted.result.current.syncStatus).toBe("connected"));
    const resumed = await storage.load(key);
    expect(resumed.data?.profile.target_school).toBe("离线修改");
    expect(resumed.metadata.pending).toBe(false);
    expect(resumed.metadata.revision).toBe(5);
  });

  it("merges a revision conflict without discarding local changes or remote edits", async () => {
    const base = accountPlan();
    const local = { ...base, profile: { ...base.profile, target_school: "本机更改" } };
    const remote = { ...base, profile: { ...base.profile, target_program: "其他设备更改" } };
    await seedAccount(local, base, true);
    let pulls = 0;
    let saves = 0;
    let uploaded: PlannerData | undefined;
    cloud.rpc.mockImplementation(async (command: string, args?: { p_data: PlannerData }) => {
      if (command === "load_planner_state") return { data: { data: ++pulls === 1 ? base : remote, revision: pulls === 1 ? 4 : 5 }, error: null };
      if (++saves === 1) return { data: null, error: { message: "PLANNER_REVISION_CONFLICT" } };
      uploaded = args?.p_data;
      return { data: { revision: 6 }, error: null };
    });
    const hook = renderHook(() => store.usePlanner(), { wrapper });
    await waitFor(() => expect(hook.result.current.syncStatus).toBe("connected"));
    expect(uploaded?.profile.target_school).toBe("本机更改");
    expect(uploaded?.profile.target_program).toBe("其他设备更改");
    const persisted = await storage.load(key);
    expect(persisted.data?.profile).toEqual(uploaded?.profile);
    expect(persisted.metadata.pending).toBe(false);
  });

  it("blocks damaged data until explicit JSON recovery", async () => {
    vi.stubEnv("VITE_SUPABASE_URL", "");
    vi.stubEnv("VITE_SUPABASE_ANON_KEY", "");
    vi.resetModules();
    store = await import("./store");
    localStorage.setItem(LOCAL_STORAGE_KEY, "{broken");
    const hook = renderHook(() => store.usePlanner(), { wrapper });
    await waitFor(() => expect(hook.result.current.storageBlocked).toBe(true));
    act(() => hook.result.current.setData(createInitialData("2026-10-14")));
    expect(localStorage.getItem(LOCAL_STORAGE_KEY)).toBe("{broken");
    await act(() => hook.result.current.restoreData(createInitialData("2026-10-14")));
    expect(hook.result.current.storageBlocked).toBe(false);
    expect((await storage.load(LOCAL_STORAGE_KEY)).data).not.toBeNull();
  });
});
