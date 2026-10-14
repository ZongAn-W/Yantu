import type { PlannerData } from "@planner/engine";
import { isPlannerData, normalizePlannerData } from "./data";

export const STORAGE_SCHEMA_VERSION = 1;
export const STORAGE_METADATA_KEY = "sjtu-study-planner:sync-meta-v1";

export interface PlannerStorageMetadata {
  version: number;
  revision: number;
  pending: boolean;
  base: PlannerData | null;
  updatedAt: string;
}

export interface PlannerStorageSnapshot {
  data: PlannerData | null;
  metadata: PlannerStorageMetadata;
  recovered: boolean;
  error?: string;
}

export interface PlannerStorage {
  readonly kind: "browser" | "desktop";
  load(key: string): Promise<PlannerStorageSnapshot>;
  save(key: string, data: PlannerData, metadata: PlannerStorageMetadata): Promise<void>;
  importJson(): Promise<unknown | null>;
  exportJson(data: PlannerData): Promise<void>;
}

const emptyMetadata = (): PlannerStorageMetadata => ({
  version: STORAGE_SCHEMA_VERSION,
  revision: 0,
  pending: false,
  base: null,
  updatedAt: new Date(0).toISOString(),
});

function parseEnvelope(raw: string | null): { data: PlannerData | null; metadata: PlannerStorageMetadata } {
  if (!raw) return { data: null, metadata: emptyMetadata() };
  const parsed: unknown = JSON.parse(raw);
  // Existing browser exports were raw PlannerData. Keep them readable.
  if (isPlannerData(parsed)) return { data: parsed, metadata: emptyMetadata() };
  if (!parsed || typeof parsed !== "object") throw new Error("本地数据格式异常。");
  const envelope = parsed as { version?: unknown; data?: unknown; metadata?: unknown };
  if (envelope.version !== STORAGE_SCHEMA_VERSION || !isPlannerData(envelope.data)) {
    throw new Error("本地数据版本不兼容。");
  }
  const metadata = envelope.metadata && typeof envelope.metadata === "object"
    ? { ...emptyMetadata(), ...(envelope.metadata as Partial<PlannerStorageMetadata>) }
    : emptyMetadata();
  return { data: envelope.data, metadata };
}

function browserDownload(data: PlannerData): void {
  const blob = new Blob([JSON.stringify(data, null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = `sjtu-study-planner-${new Date().toISOString().slice(0, 10)}.json`;
  anchor.click();
  setTimeout(() => URL.revokeObjectURL(url), 0);
}

export class BrowserPlannerStorage implements PlannerStorage {
  readonly kind = "browser" as const;

  async load(key: string): Promise<PlannerStorageSnapshot> {
    try {
      const parsed = parseEnvelope(localStorage.getItem(key));
      const rawMeta = localStorage.getItem(`${key}:meta`);
      const metadata = rawMeta ? { ...parsed.metadata, ...JSON.parse(rawMeta) } : parsed.metadata;
      return { ...parsed, metadata, recovered: false };
    } catch (error) {
      try {
        const backup = parseEnvelope(localStorage.getItem(`${key}:backup`));
        if (backup.data) return {
          ...backup,
          recovered: true,
          error: `主数据损坏，已从最近备份恢复：${String(error)}`,
        };
      } catch {
        // Report both failures below without replacing the main value.
      }
      return { data: null, metadata: emptyMetadata(), recovered: false, error: String(error) };
    }
  }

  async save(key: string, data: PlannerData, metadata: PlannerStorageMetadata): Promise<void> {
    // localStorage has no atomic primitive; retain the previous value in a separate backup key.
    const previous = localStorage.getItem(key);
    if (previous) localStorage.setItem(`${key}:backup`, previous);
    // Keep the established browser key as raw PlannerData so existing exports,
    // Playwright fixtures, and older browser sessions remain compatible.
    localStorage.setItem(key, JSON.stringify(data));
    localStorage.setItem(`${key}:meta`, JSON.stringify(metadata));
  }

  async importJson(): Promise<unknown | null> {
    return new Promise((resolve, reject) => {
      const input = document.createElement("input");
      input.type = "file";
      input.accept = "application/json,.json";
      input.onchange = () => {
        const file = input.files?.[0];
        if (!file) return resolve(null);
        const reader = new FileReader();
        reader.onerror = () => reject(reader.error ?? new Error("读取文件失败。"));
        reader.onload = () => {
          try { resolve(JSON.parse(String(reader.result))); }
          catch (error) { reject(error); }
        };
        reader.readAsText(file);
      };
      input.click();
    });
  }

  async exportJson(data: PlannerData): Promise<void> { browserDownload(data); }
}

type TauriBridge = {
  invoke: <T>(command: string, args?: Record<string, unknown>) => Promise<T>;
};

async function tauriBridge(): Promise<TauriBridge | null> {
  const tauriWindow = window as Window & { __TAURI_INTERNALS__?: unknown };
  if (!tauriWindow.__TAURI_INTERNALS__ && !["tauri:", "https://tauri.localhost"].some((prefix) => window.location.href.startsWith(prefix))) return null;
  const { invoke } = await import("@tauri-apps/api/core");
  return { invoke };
}

class DesktopPlannerStorage implements PlannerStorage {
  readonly kind = "desktop" as const;

  async load(key: string): Promise<PlannerStorageSnapshot> {
    const bridge = await tauriBridge();
    if (!bridge) return new BrowserPlannerStorage().load(key);
    try {
      const result = await bridge.invoke<PlannerStorageSnapshot>("read_planner_data");
      return { ...result, recovered: Boolean(result.recovered) };
    } catch (error) {
      return { data: null, metadata: emptyMetadata(), recovered: false, error: String(error) };
    }
  }

  async save(_key: string, data: PlannerData, metadata: PlannerStorageMetadata): Promise<void> {
    const bridge = await tauriBridge();
    if (!bridge) return new BrowserPlannerStorage().save(_key, data, metadata);
    await bridge.invoke("write_planner_data", {
      envelope: { version: STORAGE_SCHEMA_VERSION, data, metadata },
    });
  }

  async importJson(): Promise<unknown | null> {
    const bridge = await tauriBridge();
    if (!bridge) return new BrowserPlannerStorage().importJson();
    const { open } = await import("@tauri-apps/plugin-dialog");
    const selected = await open({
      multiple: false,
      directory: false,
      filters: [{ name: "JSON", extensions: ["json"] }],
    });
    if (!selected || Array.isArray(selected)) return null;
    return bridge.invoke<unknown>("read_json_file", { path: selected });
  }

  async exportJson(data: PlannerData): Promise<void> {
    const bridge = await tauriBridge();
    if (!bridge) return new BrowserPlannerStorage().exportJson(data);
    const { save } = await import("@tauri-apps/plugin-dialog");
    const selected = await save({
      defaultPath: `sjtu-study-planner-${new Date().toISOString().slice(0, 10)}.json`,
      filters: [{ name: "JSON", extensions: ["json"] }],
    });
    if (selected) await bridge.invoke("write_json_file", { path: selected, data });
  }
}

export function isDesktopRuntime(): boolean {
  return typeof window !== "undefined" && Boolean(
    (window as Window & { __TAURI_INTERNALS__?: unknown }).__TAURI_INTERNALS__ ||
    window.location.protocol === "tauri:" ||
    window.location.hostname === "tauri.localhost",
  );
}

export function createPlannerStorage(): PlannerStorage {
  return isDesktopRuntime() ? new DesktopPlannerStorage() : new BrowserPlannerStorage();
}

export function defaultStorageMetadata(): PlannerStorageMetadata { return emptyMetadata(); }

export function normalizeStorageData(value: unknown): PlannerData | null {
  return normalizePlannerData(value);
}
