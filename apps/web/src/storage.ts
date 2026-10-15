import type { PlannerData } from "@planner/engine";
import { isPlannerData, normalizePlannerData } from "./data";

export const STORAGE_SCHEMA_VERSION = 1;

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
  save(key: string, data: PlannerData, metadata: PlannerStorageMetadata, recovery?: boolean): Promise<void>;
  importJson(): Promise<unknown | null>;
  exportJson(data: PlannerData): Promise<void>;
}

function parseMetadata(value: unknown): PlannerStorageMetadata {
  if (!value || typeof value !== "object") throw new Error("同步元数据格式异常。");
  const metadata = { ...emptyMetadata(), ...value } as PlannerStorageMetadata;
  if (metadata.version !== STORAGE_SCHEMA_VERSION || !Number.isSafeInteger(metadata.revision)
      || metadata.revision < 0 || typeof metadata.pending !== "boolean"
      || (metadata.base !== null && !isPlannerData(metadata.base))) {
    throw new Error("同步基线或版本号异常，请从备份恢复。");
  }
  return metadata;
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
  const metadata = parseMetadata(envelope.metadata ?? emptyMetadata());
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
      const raw = localStorage.getItem(key);
      if (!raw) {
        const backupRaw = localStorage.getItem(`${key}:backup`);
        if (backupRaw) {
          const backup = parseEnvelope(backupRaw);
          if (backup.data) return { ...backup, recovered: true, error: "主数据缺失，已从最近备份恢复。" };
        }
      }
      const parsed = parseEnvelope(raw);
      const rawMeta = localStorage.getItem(`${key}:meta`);
      const metadata = rawMeta ? parseMetadata(JSON.parse(rawMeta)) : parsed.metadata;
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

  async save(key: string, data: PlannerData, metadata: PlannerStorageMetadata, recovery = false): Promise<void> {
    // localStorage has no atomic primitive; retain the previous value in a separate backup key.
    const previous = localStorage.getItem(key);
    if (previous) {
      try {
        const snapshot = parseEnvelope(previous);
        const rawMeta = localStorage.getItem(`${key}:meta`);
        const priorMetadata = rawMeta ? parseMetadata(JSON.parse(rawMeta)) : snapshot.metadata;
        localStorage.setItem(`${key}:backup`, JSON.stringify({ version: STORAGE_SCHEMA_VERSION, data: snapshot.data, metadata: priorMetadata }));
      } catch (error) {
        if (!recovery) {
          const backup = localStorage.getItem(`${key}:backup`);
          if (!backup) throw new Error(`本地数据无法读取，已停止覆盖原数据：${String(error)}`);
          try { parseEnvelope(backup); } catch { throw new Error(`主数据和最近备份都无法读取，已停止覆盖原数据：${String(error)}`); }
        }
      }
    }
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
      input.oncancel = () => resolve(null);
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
  if (!isDesktopRuntime()) return null;
  const { invoke } = await import("@tauri-apps/api/core");
  return { invoke };
}

export class DesktopPlannerStorage implements PlannerStorage {
  readonly kind = "desktop" as const;
  private writes: Promise<void> = Promise.resolve();

  async load(key: string): Promise<PlannerStorageSnapshot> {
    const bridge = await tauriBridge();
    if (!bridge) return new BrowserPlannerStorage().load(key);
    try {
      await this.writes.catch(() => {});
      const result = await bridge.invoke<PlannerStorageSnapshot>("read_planner_data", { key });
      if (result.data !== null && !isPlannerData(result.data)) throw new Error("本地计划内容无效，请导入有效备份。");
      return { ...result, metadata: parseMetadata(result.metadata), recovered: Boolean(result.recovered) };
    } catch (error) {
      return { data: null, metadata: emptyMetadata(), recovered: false, error: String(error) };
    }
  }

  save(key: string, data: PlannerData, metadata: PlannerStorageMetadata, recovery = false): Promise<void> {
    const envelope = JSON.parse(JSON.stringify({ version: STORAGE_SCHEMA_VERSION, data, metadata }));
    const next = this.writes.catch(() => {}).then(async () => {
      const bridge = await tauriBridge();
      if (!bridge) throw new Error("桌面存储连接不可用。");
      await bridge.invoke("write_planner_data", { key, envelope, recovery });
    });
    this.writes = next;
    return next;
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

let plannerStorage: PlannerStorage | undefined;
export function createPlannerStorage(): PlannerStorage {
  return plannerStorage ??= isDesktopRuntime() ? new DesktopPlannerStorage() : new BrowserPlannerStorage();
}

export function defaultStorageMetadata(): PlannerStorageMetadata { return emptyMetadata(); }

export function normalizeStorageData(value: unknown): PlannerData | null {
  const raw = normalizePlannerData(value);
  if (raw) return raw;
  if (value && typeof value === "object" && "version" in value && value.version === STORAGE_SCHEMA_VERSION && "data" in value) {
    return normalizePlannerData(value.data);
  }
  return null;
}
