/** Per-call dependencies keep fixtures deterministic without changing production defaults. */
export interface PlannerRuntime {
  now(): Date;
  newId(): string;
}

export const defaultPlannerRuntime: PlannerRuntime = {
  now: () => new Date(),
  newId: () => globalThis.crypto?.randomUUID?.() ??
    `plan-${Date.now()}-${Math.random().toString(36).slice(2)}`,
};
