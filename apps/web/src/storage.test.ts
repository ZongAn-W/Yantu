import { beforeEach, describe, expect, it } from "vitest";
import { createInitialData } from "./data";
import {
  BrowserPlannerStorage,
  defaultStorageMetadata,
  STORAGE_SCHEMA_VERSION,
} from "./storage";

function installStorage() {
  const values = new Map<string, string>();
  const storage = {
    get length() { return values.size; },
    clear: () => values.clear(),
    getItem: (key: string) => values.get(key) ?? null,
    key: (index: number) => [...values.keys()][index] ?? null,
    removeItem: (key: string) => values.delete(key),
    setItem: (key: string, value: string) => { values.set(key, String(value)); },
  } as unknown as Storage;
  Object.defineProperty(globalThis, "localStorage", { configurable: true, value: storage });
  return storage;
}

describe("BrowserPlannerStorage", () => {
  beforeEach(() => installStorage().clear());

  it("保存后可重新打开读取带版本的数据", async () => {
    const storage = new BrowserPlannerStorage();
    const data = createInitialData("2026-10-14");
    await storage.save("planner", data, defaultStorageMetadata());
    const loaded = await storage.load("planner");
    expect(loaded.data?.version).toBe(1);
    expect(JSON.parse(localStorage.getItem("planner")!).version).toBe(1);
    expect(localStorage.getItem("planner:meta")).toContain("updatedAt");
  });

  it("主数据损坏时从最近备份恢复，并保留恢复提示", async () => {
    const storage = new BrowserPlannerStorage();
    const first = createInitialData("2026-10-14");
    await storage.save("planner", first, defaultStorageMetadata());
    const second = { ...first, profile: { ...first.profile, target_school: "备份前" } };
    await storage.save("planner", second, defaultStorageMetadata());
    localStorage.setItem("planner", "{broken");
    const loaded = await storage.load("planner");
    expect(loaded.recovered).toBe(true);
    expect(loaded.data?.profile.target_school).toBe(first.profile.target_school);
    expect(loaded.error).toContain("主数据损坏");
  });

  it("主数据丢失时也从最近备份恢复", async () => {
    const storage = new BrowserPlannerStorage();
    const data = createInitialData("2026-10-14");
    await storage.save("planner", data, defaultStorageMetadata());
    await storage.save("planner", { ...data, profile: { ...data.profile, target_school: "second" } }, defaultStorageMetadata());
    localStorage.removeItem("planner");
    const loaded = await storage.load("planner");
    expect(loaded.recovered).toBe(true);
    expect(loaded.data?.profile.target_school).toBe(data.profile.target_school);
  });

  it("写入失败时不会覆盖旧数据", async () => {
    const storage = new BrowserPlannerStorage();
    const data = createInitialData("2026-10-14");
    await storage.save("planner", data, defaultStorageMetadata());
    const original = localStorage.getItem("planner");
    const originalSet = localStorage.setItem;
    localStorage.setItem = ((key: string) => {
      if (key === "planner") throw new Error("disk full");
      return originalSet.call(localStorage, key, "");
    }) as Storage["setItem"];
    await expect(storage.save("planner", { ...data, version: 1 }, defaultStorageMetadata())).rejects.toThrow("disk full");
    expect(localStorage.getItem("planner")).toBe(original);
  });
});
