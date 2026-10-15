// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { createInitialData, LOCAL_STORAGE_KEY } from "./data";
import { DesktopPlannerStorage, defaultStorageMetadata, normalizeStorageData } from "./storage";

const bridge = vi.hoisted(() => ({ invoke: vi.fn(), open: vi.fn(), save: vi.fn() }));
vi.mock("@tauri-apps/api/core", () => ({ invoke: bridge.invoke }));
vi.mock("@tauri-apps/plugin-dialog", () => ({ open: bridge.open, save: bridge.save }));

beforeEach(() => {
  Object.defineProperty(window, "__TAURI_INTERNALS__", { configurable: true, value: {} });
  bridge.invoke.mockReset();
  bridge.open.mockReset();
  bridge.save.mockReset();
});
afterEach(() => { Reflect.deleteProperty(window, "__TAURI_INTERNALS__"); });

describe("desktop storage bridge", () => {
  it("serializes rapid edits and sends the account key with each write", async () => {
    const storage = new DesktopPlannerStorage();
    const data = createInitialData("2026-10-14");
    let release: () => void = () => {};
    const blocked = new Promise<void>((resolve) => { release = resolve; });
    bridge.invoke.mockImplementationOnce(() => blocked).mockResolvedValue(undefined);
    const first = storage.save(LOCAL_STORAGE_KEY, data, defaultStorageMetadata());
    const accountKey = `${LOCAL_STORAGE_KEY}:cloud:user-a`;
    const second = storage.save(accountKey, { ...data, profile: { ...data.profile, target_school: "new edit" } }, defaultStorageMetadata());
    await vi.waitFor(() => expect(bridge.invoke).toHaveBeenCalledTimes(1));
    release();
    await Promise.all([first, second]);
    expect(bridge.invoke.mock.calls[0][1].key).toBe(LOCAL_STORAGE_KEY);
    expect(bridge.invoke.mock.calls[1][1].key).toBe(accountKey);
    expect(bridge.invoke.mock.calls[1][1].envelope.data.profile.target_school).toBe("new edit");
  });

  it("surfaces a write error and allows a later retry", async () => {
    const storage = new DesktopPlannerStorage();
    const data = createInitialData("2026-10-14");
    bridge.invoke.mockRejectedValueOnce(new Error("disk full")).mockResolvedValueOnce(undefined);
    await expect(storage.save(LOCAL_STORAGE_KEY, data, defaultStorageMetadata())).rejects.toThrow("disk full");
    await expect(storage.save(LOCAL_STORAGE_KEY, data, defaultStorageMetadata())).resolves.toBeUndefined();
  });

  it("uses native save/open dialogs for a browser-compatible JSON round trip", async () => {
    const storage = new DesktopPlannerStorage();
    const data = createInitialData("2026-10-14");
    let exported: unknown;
    bridge.save.mockResolvedValue("C:\\Backups\\planner.json");
    bridge.open.mockResolvedValue("C:\\Backups\\planner.json");
    bridge.invoke.mockImplementation(async (command: string, args: { data?: unknown }) => {
      if (command === "write_json_file") exported = args.data;
      if (command === "read_json_file") return JSON.parse(JSON.stringify(exported));
    });
    await storage.exportJson(data);
    expect(normalizeStorageData(await storage.importJson())).toEqual(data);
    expect(normalizeStorageData({ version: 1, data, metadata: defaultStorageMetadata() })).toEqual(data);
    expect(bridge.save).toHaveBeenCalledTimes(1);
    expect(bridge.open).toHaveBeenCalledTimes(1);
  });

  it("refuses an invalid desktop payload without treating it as a new installation", async () => {
    bridge.invoke.mockResolvedValue({ data: {}, metadata: defaultStorageMetadata(), recovered: false });
    const result = await new DesktopPlannerStorage().load(LOCAL_STORAGE_KEY);
    expect(result.data).toBeNull();
    expect(result.error).toContain("无效");
  });
});
