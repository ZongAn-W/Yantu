import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useRef,
  useState,
  type Dispatch,
  type ReactNode,
  type SetStateAction,
} from "react";
import {
  createClient,
  type Session,
  type SupabaseClient,
  type User,
} from "@supabase/supabase-js";
import type { PlannerData, ReplanChange, ReplanRun } from "@planner/engine";
import { mergeTaskDayLogs } from "@planner/engine";
import {
  createInitialData,
  LOCAL_STORAGE_KEY,
  normalizePlannerData,
} from "./data";
import {
  createPlannerStorage,
  defaultStorageMetadata,
  type PlannerStorage,
  type PlannerStorageMetadata,
} from "./storage";

export type SyncStatus =
  | "demo"
  | "login_required"
  | "connecting"
  | "syncing"
  | "connected"
  | "offline"
  | "error";
const env = (
  import.meta as ImportMeta & { env: Record<string, string | undefined> }
).env;
const cloudUrl = env.VITE_SUPABASE_URL?.trim();
const cloudKey = (
  env.VITE_SUPABASE_PUBLISHABLE_KEY || env.VITE_SUPABASE_ANON_KEY
)?.trim();
export const cloudConfigured = Boolean(cloudUrl && cloudKey);
let client: SupabaseClient | null = null;
let configurationError = "";
if (cloudConfigured) {
  try {
    client = createClient(cloudUrl!, cloudKey!, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true,
      },
    });
  } catch {
    configurationError =
      "Supabase 地址无效，请检查环境变量。当前仍可使用本地 Demo。";
  }
}

export const syncStatusNames: Record<SyncStatus, string> = {
  demo: "本地 Demo",
  login_required: "云端已配置 · 请登录",
  connecting: "正在连接云端",
  syncing: "正在同步",
  connected: "云端已同步",
  offline: "离线 · 更改已保存在本机",
  error: "同步失败 · 更改已保存在本机",
};

interface PlannerContextValue {
  data: PlannerData;
  setData: Dispatch<SetStateAction<PlannerData>>;
  syncStatus: SyncStatus;
  syncMessage: string;
  cloudConfigured: boolean;
  session: Session | null;
  user: User | null;
  signIn: (email: string, password: string) => Promise<void>;
  signUp: (email: string, password: string) => Promise<void>;
  signOut: () => Promise<void>;
  retrySync: () => Promise<void>;
}

const PlannerContext = createContext<PlannerContextValue | null>(null);
const cloudStorageKey = (userId: string) =>
  `${LOCAL_STORAGE_KEY}:cloud:${userId}`;
const clone = <T,>(value: T): T => JSON.parse(JSON.stringify(value)) as T;
const same = (left: unknown, right: unknown) =>
  JSON.stringify(left) === JSON.stringify(right);

function readLocal(key: string): PlannerData | null {
  try {
    const saved = localStorage.getItem(key);
    if (!saved) return null;
    const parsed = JSON.parse(saved) as { data?: unknown };
    return normalizePlannerData(parsed?.data ?? parsed);
  } catch {
    return null;
  }
}

/** Retag the complete graph, including immutable replan snapshots, at account boundaries. */
function forUser(data: PlannerData, userId: string): PlannerData {
  const change = (item: ReplanChange): ReplanChange => ({
    ...item,
    user_id: userId,
    before: item.before ? { ...item.before, user_id: userId } : null,
    after: item.after ? { ...item.after, user_id: userId } : null,
  });
  return {
    ...data,
    profile: { ...data.profile, user_id: userId },
    subjects: data.subjects.map((item) => ({ ...item, user_id: userId })),
    tasks: data.tasks.map((item) => ({ ...item, user_id: userId })),
    blocks: data.blocks.map((item) => ({ ...item, user_id: userId })),
    logs: data.logs.map((item) => ({ ...item, user_id: userId })),
    fixed_events: data.fixed_events.map((item) => ({
      ...item,
      user_id: userId,
    })),
    replan_runs: data.replan_runs.map((item: ReplanRun) => ({
      ...item,
      user_id: userId,
      before: item.before.map((block) => ({ ...block, user_id: userId })),
      after: item.after.map((block) => ({ ...block, user_id: userId })),
      changes: item.changes.map(change),
    })),
  };
}

/** Preserve independent edits made on another device when a revision conflict occurs. */
function mergeRows<T extends { id: string }>(
  base: T[],
  local: T[],
  remote: T[],
): T[] {
  const baseById = new Map(base.map((item) => [item.id, item]));
  const localById = new Map(local.map((item) => [item.id, item]));
  const result = new Map(remote.map((item) => [item.id, item]));
  for (const id of new Set([...baseById.keys(), ...localById.keys()])) {
    const oldValue = baseById.get(id);
    const localValue = localById.get(id);
    if (same(oldValue, localValue)) continue;
    if (localValue) result.set(id, localValue);
    else result.delete(id);
  }
  return [...result.values()];
}

function mergePlans(
  base: PlannerData,
  local: PlannerData,
  remote: PlannerData,
): PlannerData {
  const merged: PlannerData = {
    ...remote,
    profile: {
      ...remote.profile,
      ...Object.fromEntries(
        Object.entries(local.profile).filter(
          ([key, value]) =>
            !same(value, base.profile[key as keyof typeof base.profile]),
        ),
      ),
    },
    phases: same(base.phases, local.phases) ? remote.phases : local.phases,
    subjects: mergeRows(base.subjects, local.subjects, remote.subjects),
    tasks: mergeRows(base.tasks, local.tasks, remote.tasks),
    blocks: mergeRows(base.blocks, local.blocks, remote.blocks),
    logs: mergeTaskDayLogs(base.logs, local.logs, remote.logs),
    fixed_events: mergeRows(
      base.fixed_events,
      local.fixed_events,
      remote.fixed_events,
    ),
    replan_runs: mergeRows(
      base.replan_runs,
      local.replan_runs,
      remote.replan_runs,
    ),
  };
  // A task deleted on one device cannot retain child blocks/logs from another.
  const taskIds = new Set(merged.tasks.map((task) => task.id));
  merged.blocks = merged.blocks.filter((block) => taskIds.has(block.task_id));
  const blockIds = new Set(merged.blocks.map((block) => block.id));
  merged.logs = merged.logs
    .filter((log) => taskIds.has(log.task_id))
    .map((log) =>
      log.block_id && !blockIds.has(log.block_id)
        ? { ...log, block_id: null }
        : log,
    );
  // Independent timer records are additive. Never overwrite one device's study with another.
  merged.tasks = merged.tasks.map((task) => {
    const records = merged.logs.filter((log) => log.task_id === task.id);
    if (!records.length) return task;
    const completed_minutes = Math.min(
      task.estimated_minutes,
      records.reduce((total, log) => total + log.minutes, 0),
    );
    return {
      ...task,
      completed_minutes,
      status: task.status,
    };
  });
  merged.blocks = merged.blocks.map((block) => {
    const records = merged.logs.filter((log) => log.block_id === block.id);
    if (!records.length) return block;
    const actual_minutes = records.reduce(
      (total, log) => total + log.minutes,
      0,
    );
    return {
      ...block,
      actual_minutes,
      status: block.status,
    };
  });
  return merged;
}

async function pullCloud(): Promise<{
  data: PlannerData | null;
  revision: number;
}> {
  if (!client) throw new Error("请先配置 Supabase。");
  const { data, error } = await client.rpc("load_planner_state");
  if (error) throw error;
  if (!data?.data) return { data: null, revision: 0 };
  const normalized = normalizePlannerData(data.data);
  if (!normalized)
    throw new Error("云端数据格式异常，请保留本地导出并检查 migration。");
  return { data: normalized, revision: Number(data.revision) };
}

export function PlannerProvider({ children }: { children: ReactNode }) {
  const [data, setInternalData] = useState<PlannerData>(
    () => readLocal(LOCAL_STORAGE_KEY) ?? createInitialData(),
  );
  const [session, setSession] = useState<Session | null>(null);
  const [syncStatus, setSyncStatus] = useState<SyncStatus>(
    client ? "login_required" : "demo",
  );
  const [syncMessage, setSyncMessage] = useState(configurationError);
  const dataRef = useRef(data);
  const baseRef = useRef<PlannerData>(clone(data));
  const userRef = useRef<string | null>(null);
  const readyRef = useRef(false);
  const pendingRef = useRef(false);
  const revisionRef = useRef(0);
  const generationRef = useRef(0);
  const inFlightRef = useRef(false);
  const needsRefreshRef = useRef(false);
  const storageRef = useRef<PlannerStorage>(createPlannerStorage());
  const hydratedRef = useRef(false);
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const flushRef = useRef<() => Promise<void>>(async () => {});
  const refreshRef = useRef<() => Promise<void>>(async () => {});

  const persist = useCallback((value: PlannerData, key: string, metadata?: Partial<PlannerStorageMetadata>) => {
    const nextMetadata: PlannerStorageMetadata = {
      ...defaultStorageMetadata(),
      revision: revisionRef.current,
      pending: pendingRef.current,
      base: baseRef.current,
      updatedAt: new Date().toISOString(),
      ...metadata,
    };
    void storageRef.current.save(key, value, nextMetadata).catch((error) => {
      setSyncMessage(`本机数据保存失败：${error instanceof Error ? error.message : String(error)}。原有数据已保留。`);
      setSyncStatus("error");
    });
  }, []);

  const applyData = useCallback(
    (value: PlannerData) => {
      dataRef.current = value;
      setInternalData(value);
      persist(
        value,
        userRef.current ? cloudStorageKey(userRef.current) : LOCAL_STORAGE_KEY,
      );
    },
    [persist],
  );

  const scheduleFlush = useCallback(() => {
    if (debounceRef.current) clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => {
      void flushRef.current();
    }, 350);
  }, []);

  const setData = useCallback<Dispatch<SetStateAction<PlannerData>>>(
    (action) => {
      let value =
        typeof action === "function" ? action(dataRef.current) : action;
      const normalized = normalizePlannerData(value);
      if (!normalized) throw new Error("计划数据格式不正确，原有数据已保留。");
      value = normalized;
      if (userRef.current) value = forUser(value, userRef.current);
      if (userRef.current) {
        pendingRef.current = true;
        if (readyRef.current) {
          setSyncStatus("syncing");
          scheduleFlush();
        }
      }
      applyData(value);
    },
    [applyData, scheduleFlush],
  );

  const flush = useCallback(async () => {
    if (
      !client ||
      !userRef.current ||
      !readyRef.current ||
      inFlightRef.current ||
      !pendingRef.current
    )
      return;
    inFlightRef.current = true;
    const generation = generationRef.current;
    try {
      // Serial writes prevent late responses from losing newer UI changes.
      for (let attempt = 0; pendingRef.current && attempt < 5; attempt += 1) {
        if (generation !== generationRef.current) return;
        const snapshot = clone(dataRef.current);
        const { data: response, error } = await client.rpc(
          "save_planner_state",
          { p_data: snapshot, p_expected_revision: revisionRef.current },
        );
        if (generation !== generationRef.current) return;
        if (error) {
          if (error.message.includes("PLANNER_REVISION_CONFLICT")) {
            const remote = await pullCloud();
            if (generation !== generationRef.current) return;
            if (!remote.data) throw new Error("云端计划暂不可用，请重试同步。");
            const merged = mergePlans(
              baseRef.current,
              dataRef.current,
              remote.data,
            );
            baseRef.current = clone(remote.data);
            revisionRef.current = remote.revision;
            applyData(merged);
            continue;
          }
          throw error;
        }
        revisionRef.current = Number(response.revision);
        baseRef.current = snapshot;
        pendingRef.current = !same(snapshot, dataRef.current);
      }
      setSyncStatus(pendingRef.current ? "syncing" : "connected");
      setSyncMessage(
        pendingRef.current
          ? "正在合并设备更改…"
          : "数据已保存到云端，支持多设备实时同步。",
      );
      persist(dataRef.current, userRef.current ? cloudStorageKey(userRef.current) : LOCAL_STORAGE_KEY);
    } catch (error) {
      if (generation === generationRef.current) {
        setSyncStatus(navigator.onLine ? "error" : "offline");
        setSyncMessage(
          error instanceof Error
            ? error.message
            : String(
                (error as { message?: string })?.message ??
                  "云端同步失败，请检查网络和数据库 migration。",
              ),
        );
      }
    } finally {
      inFlightRef.current = false;
      if (generation === generationRef.current && needsRefreshRef.current) {
        needsRefreshRef.current = false;
        void refreshRef.current();
      }
    }
  }, [applyData]);
  flushRef.current = flush;

  const refresh = useCallback(async () => {
    if (!userRef.current || !readyRef.current) return;
    if (inFlightRef.current) {
      needsRefreshRef.current = true;
      return;
    }
    if (pendingRef.current) {
      await flushRef.current();
      return;
    }
    const generation = generationRef.current;
    try {
      const remote = await pullCloud();
      if (
        generation !== generationRef.current ||
        !remote.data ||
        remote.revision <= revisionRef.current
      )
        return;
      if (inFlightRef.current) {
        needsRefreshRef.current = true;
        return;
      }
      if (pendingRef.current) {
        const merged = mergePlans(
          baseRef.current,
          dataRef.current,
          remote.data,
        );
        baseRef.current = clone(remote.data);
        revisionRef.current = remote.revision;
        applyData(merged);
        await flushRef.current();
      } else {
        baseRef.current = clone(remote.data);
        revisionRef.current = remote.revision;
        applyData(remote.data);
        setSyncStatus("connected");
        setSyncMessage("已接收其他设备的最新更改。");
      }
    } catch (error) {
      if (generation !== generationRef.current) return;
      setSyncStatus(navigator.onLine ? "error" : "offline");
      setSyncMessage(
        String(
          (error as { message?: string })?.message ?? "获取云端更改失败。",
        ),
      );
    }
  }, [applyData]);
  refreshRef.current = refresh;

  useEffect(() => {
    let disposed = false;
    void storageRef.current.load(LOCAL_STORAGE_KEY).then((snapshot) => {
      if (disposed) return;
      if (snapshot.data) {
        dataRef.current = snapshot.data;
        baseRef.current = snapshot.metadata.base ? clone(snapshot.metadata.base) : clone(snapshot.data);
        revisionRef.current = snapshot.metadata.revision;
        pendingRef.current = snapshot.metadata.pending;
        setInternalData(snapshot.data);
        if (snapshot.error) {
          setSyncStatus("error");
          setSyncMessage(`${snapshot.error} 当前已载入恢复数据，请尽快导出备份。`);
        }
      } else if (snapshot.error) {
        setSyncStatus("error");
        setSyncMessage(`${snapshot.error} 未覆盖原数据，请导出备份或从 JSON 恢复。`);
      } else {
        persist(dataRef.current, LOCAL_STORAGE_KEY);
      }
      hydratedRef.current = true;
    });
    return () => { disposed = true; };
  }, [persist]);

  useEffect(() => {
    if (!client) return;
    let disposed = false;
    let channel: ReturnType<SupabaseClient["channel"]> | null = null;
    let realtimeTimer: ReturnType<typeof setTimeout> | null = null;

    const adoptSession = async (nextSession: Session | null) => {
      if (disposed) return;
      setSession(nextSession);
      const nextUser = nextSession?.user.id ?? null;
      if (nextUser === userRef.current) return;
      generationRef.current += 1;
      const generation = generationRef.current;
      if (channel) {
        void client!.removeChannel(channel);
        channel = null;
      }
      if (realtimeTimer) clearTimeout(realtimeTimer);
      readyRef.current = false;
      pendingRef.current = false;
      revisionRef.current = 0;
      userRef.current = nextUser;
      if (!nextUser) {
        const localSnapshot = await storageRef.current.load(LOCAL_STORAGE_KEY);
        applyData(localSnapshot.data ?? createInitialData());
        setSyncStatus("login_required");
        setSyncMessage("本地 Demo 可继续使用。登录后自动同步云端计划。");
        return;
      }
      setSyncStatus("connecting");
      const cachedSnapshot = await storageRef.current.load(cloudStorageKey(nextUser));
      const localSnapshot = await storageRef.current.load(LOCAL_STORAGE_KEY);
      const cached = cachedSnapshot.data;
      const startingLocal = forUser(
        cached ?? localSnapshot.data ?? createInitialData(),
        nextUser,
      );
      applyData(startingLocal);
      baseRef.current = clone(startingLocal);
      try {
        const remote = await pullCloud();
        if (disposed || generation !== generationRef.current) return;
        revisionRef.current = remote.revision;
        if (remote.data) {
          const hasConnectingEdits = !same(startingLocal, dataRef.current);
          const combined = hasConnectingEdits
            ? mergePlans(startingLocal, dataRef.current, remote.data)
            : remote.data;
          baseRef.current = clone(remote.data);
          applyData(combined);
          pendingRef.current = hasConnectingEdits;
        } else {
          // Import Demo only when this account truly has no cloud profile.
          pendingRef.current = true;
        }
        readyRef.current = true;
        if (pendingRef.current) await flushRef.current();
        else {
          setSyncStatus("connected");
          setSyncMessage("数据已保存到云端，支持多设备实时同步。");
        }
        if (disposed || generation !== generationRef.current) return;
        channel = client!.channel(`planner:${nextUser}`);
        for (const table of [
          "profiles",
          "subjects",
          "tasks",
          "schedule_blocks",
          "time_logs",
          "fixed_events",
          "replan_runs",
          "replan_changes",
        ]) {
          channel.on(
            "postgres_changes",
            {
              event: "*",
              schema: "public",
              table,
              filter: `user_id=eq.${nextUser}`,
            },
            () => {
              if (realtimeTimer) clearTimeout(realtimeTimer);
              realtimeTimer = setTimeout(() => {
                void refreshRef.current();
              }, 200);
            },
          );
        }
        channel.subscribe((status) => {
          if (disposed || generation !== generationRef.current) return;
          if (status === "SUBSCRIBED") void refreshRef.current();
          if (status === "CHANNEL_ERROR" || status === "TIMED_OUT") {
            setSyncMessage("实时连接暂时断开，正在自动重连；更改仍会保存。");
          }
        });
      } catch (error) {
        if (disposed || generation !== generationRef.current) return;
        setSyncStatus(navigator.onLine ? "error" : "offline");
        setSyncMessage(
          String(
            (error as { message?: string })?.message ??
              "云端初始化失败。请应用 migration 后重新登录。",
          ),
        );
      }
    };

    // Avoid awaiting Supabase requests inside its auth callback lock.
    const { data: authListener } = client.auth.onAuthStateChange(
      (_event, nextSession) => {
        setTimeout(() => {
          void adoptSession(nextSession);
        }, 0);
      },
    );
    void client.auth
      .getSession()
      .then(({ data: auth }) => adoptSession(auth.session));
    const online = () => {
      void flushRef.current().then(() => refreshRef.current());
    };
    const offline = () => {
      if (userRef.current) setSyncStatus("offline");
    };
    window.addEventListener("online", online);
    window.addEventListener("offline", offline);
    return () => {
      disposed = true;
      generationRef.current += 1;
      authListener.subscription.unsubscribe();
      if (channel) void client!.removeChannel(channel);
      if (realtimeTimer) clearTimeout(realtimeTimer);
      if (debounceRef.current) clearTimeout(debounceRef.current);
      window.removeEventListener("online", online);
      window.removeEventListener("offline", offline);
    };
  }, [applyData, persist]);

  const signIn = useCallback(async (email: string, password: string) => {
    if (!client)
      throw new Error(
        "请在 apps/web/.env.local 配置 Supabase 后重启开发服务器。",
      );
    const { error } = await client.auth.signInWithPassword({
      email: email.trim(),
      password,
    });
    if (error) throw new Error(error.message);
  }, []);

  const signUp = useCallback(async (email: string, password: string) => {
    if (!client)
      throw new Error(
        "请在 apps/web/.env.local 配置 Supabase 后重启开发服务器。",
      );
    const { data: auth, error } = await client.auth.signUp({
      email: email.trim(),
      password,
    });
    if (error) throw new Error(error.message);
    if (!auth.session)
      setSyncMessage("账号已创建。请在邮箱中确认注册，再返回登录。");
  }, []);

  const signOut = useCallback(async () => {
    if (!client) return;
    await flushRef.current();
    const { error } = await client.auth.signOut();
    if (error) throw new Error(error.message);
  }, []);

  const retrySync = useCallback(async () => {
    if (!readyRef.current && userRef.current) {
      const remote = await pullCloud();
      if (remote.data) {
        const merged = pendingRef.current
          ? mergePlans(baseRef.current, dataRef.current, remote.data)
          : remote.data;
        baseRef.current = clone(remote.data);
        revisionRef.current = remote.revision;
        applyData(merged);
      } else pendingRef.current = true;
      readyRef.current = true;
    }
    await flushRef.current();
    await refreshRef.current();
  }, [applyData]);

  return (
    <PlannerContext.Provider
      value={{
        data,
        setData,
        syncStatus,
        syncMessage,
        cloudConfigured: Boolean(client),
        session,
        user: session?.user ?? null,
        signIn,
        signUp,
        signOut,
        retrySync,
      }}
    >
      {children}
    </PlannerContext.Provider>
  );
}

export function usePlannerStore(): PlannerContextValue {
  const context = useContext(PlannerContext);
  if (!context)
    throw new Error("usePlannerStore 必须在 PlannerProvider 中使用。");
  return context;
}
export const usePlanner = usePlannerStore;
