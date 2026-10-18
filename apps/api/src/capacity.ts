/**
 * Flexible weekly/date capacity resolution (CONTEXT §2.2).
 *
 * One pure implementation shared by the automatic scheduler, the manual placement
 * checks, the plan preview and the TypeScript reference engine. The Flutter mirror
 * `lib/features/planner/domain/capacity.dart` resolves the exact same rules and both
 * are checked against `packages/planner-engine/fixtures/capacity-cases.json`.
 *
 * Precedence for a date d:
 *   1. `date_capacity_overrides[d]` (wins over a week's own day value);
 *   2. the natural week override of `monday(d)`:
 *      - explicit `days[weekday]` value;
 *      - else `total_minutes` distributed over the remaining template days;
 *   3. `weekly_baseline_minutes` (fallback `weekly_range_min_minutes`) as the week total;
 *   4. the default template `weekly_minutes[weekday]`, or `daily_limit_minutes` for
 *      legacy documents without a reliable seven-day map.
 * A `capacity_basis` of `net` treats the resolved value as the study budget itself;
 * legacy `gross_buffer` keeps subtracting `max(30, buffer_minutes)` exactly once.
 */

export type CapacitySource =
  | "date_override"
  | "week_day_override"
  | "week_total"
  | "template"
  | "baseline"
  | "legacy_default";

export type CapacityBasis = "gross_buffer" | "net";

export type CapacityConflictCode = "WEEK_TOTAL_EXCEEDED" | "WEEK_TOTAL_UNALLOCATED";

export interface CapacityConflict {
  code: CapacityConflictCode;
  total: number;
  resolved: number;
}

export interface WeekCapacityOverride {
  total_minutes?: number;
  days?: Record<string, number>;
}

/** Profile fields the resolver needs; document profiles and engine profiles both fit. */
export interface CapacityProfile {
  planning_mode?: "daily" | "timed";
  weekly_minutes?: Record<string, number> | null;
  daily_limit_minutes?: number | null;
  buffer_minutes?: number | null;
  granularity_minutes?: number | null;
  capacity_basis?: CapacityBasis | null;
  weekly_baseline_minutes?: number | null;
  weekly_range_min_minutes?: number | null;
  weekly_range_max_minutes?: number | null;
  week_capacity_overrides?: Record<string, WeekCapacityOverride> | null;
  date_capacity_overrides?: Record<string, number> | null;
}

export interface DayCapacity {
  date: string;
  /** Monday (Shanghai calendar) of the natural week containing [date]. */
  monday: string;
  /** Effective study budget after the capacity basis is applied (before fixed events). */
  minutes: number;
  /** Value before `gross_buffer` deducts the buffer / `net` keeps it whole. */
  raw_minutes: number;
  source: CapacitySource;
  /** True when the value comes from a weekly-total/baseline distribution suggestion. */
  estimated: boolean;
  /** Confirmed week budget (override total or baseline) that scopes this date, else null. */
  week_budget_minutes: number | null;
}

export interface WeekCapacity {
  monday: string;
  /** Resolved raw minutes per date (Monday..Sunday). */
  days: Record<string, number>;
  sources: Record<string, CapacitySource>;
  estimated: Record<string, boolean>;
  /** Confirmed weekly budget (override total or baseline), null for pure templates. */
  budget_override_minutes: number | null;
  resolved_minutes: number;
  conflicts: CapacityConflict[];
}

export const CAPACITY_DEFAULTS = Object.freeze({
  daily_limit_minutes: 480,
  buffer_minutes: 30,
  granularity_minutes: 30,
});

/** Monday-first weekday order used for deterministic largest-remainder tie breaks. */
export const WEEK_ORDER_MONDAY_FIRST = Object.freeze([1, 2, 3, 4, 5, 6, 0] as const);

const DAY_MS = 86_400_000;
const finite = (value: unknown, fallback = 0) => {
  const number = typeof value === "number" ? value : Number(value);
  return Number.isFinite(number) ? number : fallback;
};
const positive = (value: unknown) => Math.max(0, finite(value));

export function weekdayOf(date: string): number {
  return new Date(`${date}T00:00:00Z`).getUTCDay();
}

export function plusDays(date: string, days: number): string {
  return new Date(Date.parse(`${date}T00:00:00Z`) + days * DAY_MS).toISOString().slice(0, 10);
}

/** Shanghai Monday key of the natural week containing [date]. */
export function mondayOf(date: string): string {
  return plusDays(date, -((weekdayOf(date) + 6) % 7));
}

export function weekDates(monday: string): string[] {
  return Array.from({ length: 7 }, (_, index) => plusDays(monday, index));
}

export const isNetCapacity = (profile: CapacityProfile) => profile.capacity_basis === "net";

/** Per-day quantum of automatic blocks; net plans allow the lighter 10-minute minimum. */
export function minBlockMinutes(profile: CapacityProfile): number {
  if (!isNetCapacity(profile)) return Math.max(30, finite(profile.granularity_minutes, CAPACITY_DEFAULTS.granularity_minutes) || 30);
  return 10;
}

/** Block size used while filling a day; net plans keep quantum in the 10..30 minute range. */
export function blockQuantum(profile: CapacityProfile): number {
  const granularity = finite(profile.granularity_minutes, CAPACITY_DEFAULTS.granularity_minutes) || CAPACITY_DEFAULTS.granularity_minutes;
  if (!isNetCapacity(profile)) return Math.max(30, granularity);
  return Math.min(30, Math.max(10, granularity));
}

function templateOf(profile: CapacityProfile): { values: number[]; source: CapacitySource } {
  const week = profile.weekly_minutes;
  if (week && typeof week === "object" && Object.keys(week).length === 7) {
    return { values: Array.from({ length: 7 }, (_, day) => positive(week[String(day)])), source: "template" };
  }
  const limit = positive(profile.daily_limit_minutes ?? CAPACITY_DEFAULTS.daily_limit_minutes);
  return { values: Array.from({ length: 7 }, () => limit), source: "legacy_default" };
}

/**
 * Integer largest-remainder distribution.
 * `weights` is indexed by JS weekday (0=Sunday .. 6=Saturday); remainders are handed out
 * in Monday-first order `[1,2,3,4,5,6,0]` so ties are deterministic across end implementations.
 */
export function distributeMinutes(total: number, weights: number[]): number[] {
  const result = weights.map(() => 0);
  const sum = weights.reduce((acc, weight) => acc + Math.max(0, weight), 0);
  const amount = Math.max(0, Math.floor(finite(total)));
  if (amount <= 0 || sum <= 0) return result;
  let allocated = 0;
  const remainders: Array<{ day: number; fraction: number }> = [];
  WEEK_ORDER_MONDAY_FIRST.forEach(day => {
    const weight = weights[day];
    if (!weight || weight <= 0) return;
    const exact = (amount * weight) / sum;
    result[day] = Math.floor(exact);
    allocated += result[day];
    remainders.push({ day, fraction: exact - result[day] });
  });
  let left = amount - allocated;
  const order = WEEK_ORDER_MONDAY_FIRST as readonly number[];
  remainders.sort((a, b) => b.fraction - a.fraction || order.indexOf(a.day) - order.indexOf(b.day));
  for (const row of remainders) {
    if (left <= 0) break;
    result[row.day] += 1;
    left -= 1;
  }
  return result;
}

function applyBasis(profile: CapacityProfile, raw: number): number {
  if (isNetCapacity(profile)) {
    // Net input is the study budget itself; only the documented daily ceiling caps it.
    const limit = positive(profile.daily_limit_minutes ?? CAPACITY_DEFAULTS.daily_limit_minutes);
    return Math.max(0, Math.min(limit, positive(raw)));
  }
  // Legacy gross semantics stay exactly as before: 480-minute ceiling then one buffer deduction.
  return Math.max(0, Math.min(480, positive(raw))
    - Math.max(30, positive(profile.buffer_minutes ?? CAPACITY_DEFAULTS.buffer_minutes)));
}

/**
 * Resolve one natural week. The returned conflict list is the shared contract:
 * `WEEK_TOTAL_EXCEEDED` when specific values consume more than the confirmed total and
 * `WEEK_TOTAL_UNALLOCATED` when no template day can receive the remaining total (or the
 * baseline week). Baselines use the very same total/distribution algorithm.
 */
export function resolveWeekCapacity(profile: CapacityProfile, monday: string): WeekCapacity {
  const template = templateOf(profile);
  const override = profile.week_capacity_overrides?.[monday];
  const dateOverrides = profile.date_capacity_overrides ?? {};
  const dates = weekDates(monday);
  const days: Record<string, number> = {};
  const sources: Record<string, CapacitySource> = {};
  const estimated: Record<string, boolean> = {};
  const conflicts: CapacityConflict[] = [];
  const setDay = (date: string, value: number, source: CapacitySource, isEstimated: boolean) => {
    days[date] = Math.max(0, Math.floor(finite(value)));
    sources[date] = source;
    estimated[date] = isEstimated;
  };
  /** A specific date value wins over the week's own day override. */
  const specific = (date: string): number | undefined => {
    const dateValue = dateOverrides[date];
    if (dateValue !== undefined && dateValue !== null) return dateValue;
    const dayValue = override?.days?.[String(weekdayOf(date))];
    return dayValue === undefined || dayValue === null ? undefined : dayValue;
  };
  const specificSource = (date: string): CapacitySource =>
    dateOverrides[date] !== undefined && dateOverrides[date] !== null ? "date_override" : "week_day_override";
  /** Weekday (0=Sunday..6=Saturday) -> date in this week. */
  const dateOfWeekday = (day: number) => dates[(day + 6) % 7];
  const finish = (budget: number | null): WeekCapacity => ({
    monday,
    days,
    sources,
    estimated,
    budget_override_minutes: budget,
    resolved_minutes: dates.reduce((sum, date) => sum + (days[date] ?? 0), 0),
    conflicts,
  });

  if (!override) {
    const baseline = profile.weekly_baseline_minutes ?? profile.weekly_range_min_minutes;
    if (baseline !== undefined && baseline !== null) {
      const total = positive(baseline);
      const explicitSum = dates.reduce((sum, date) => {
        const value = dateOverrides[date];
        return sum + (value === undefined || value === null ? 0 : positive(value));
      }, 0);
      let remaining = total - explicitSum;
      if (remaining < 0) {
        conflicts.push({ code: "WEEK_TOTAL_EXCEEDED", total, resolved: explicitSum });
        remaining = 0;
      }
      // Distribution weights are weekday-indexed (0=Sunday..6=Saturday); explicit dates consume
      // the confirmed total and are excluded from the proportional split.
      const weights = Array.from({ length: 7 }, (_, day) => {
        const date = dateOfWeekday(day);
        return dateOverrides[date] !== undefined && dateOverrides[date] !== null ? 0 : template.values[day];
      });
      const shares = distributeMinutes(remaining, weights);
      dates.forEach(date => {
        if (dateOverrides[date] !== undefined && dateOverrides[date] !== null)
          setDay(date, dateOverrides[date]!, "date_override", false);
        else setDay(date, shares[weekdayOf(date)], "baseline", true);
      });
      if (weights.every(weight => weight === 0) && remaining > 0)
        conflicts.push({ code: "WEEK_TOTAL_UNALLOCATED", total, resolved: explicitSum });
      return finish(total);
    }
    dates.forEach(date => {
      if (dateOverrides[date] !== undefined && dateOverrides[date] !== null)
        setDay(date, dateOverrides[date]!, "date_override", false);
      else setDay(date, template.values[weekdayOf(date)], template.source, false);
    });
    return finish(null);
  }

  const total = override.total_minutes;
  if (total === undefined || total === null) {
    dates.forEach(date => {
      const value = specific(date);
      if (value === undefined) setDay(date, template.values[weekdayOf(date)], template.source, false);
      else setDay(date, value, specificSource(date), false);
    });
    return finish(null);
  }

  // Specific date values and explicit week days both consume the confirmed week total.
  const confirmed = positive(total);
  const explicitSum = dates.reduce((sum, date) => sum + (specific(date) ?? 0), 0);
  let remaining = confirmed - explicitSum;
  if (remaining < 0) {
    conflicts.push({ code: "WEEK_TOTAL_EXCEEDED", total: confirmed, resolved: explicitSum });
    remaining = 0;
  }
  const weights = Array.from({ length: 7 }, (_, day) => {
    const date = dateOfWeekday(day);
    return specific(date) !== undefined ? 0 : Math.max(0, template.values[day]);
  });
  const shares = distributeMinutes(remaining, weights);
  dates.forEach(date => {
    const value = specific(date);
    if (value !== undefined) setDay(date, value, specificSource(date), false);
    else setDay(date, shares[weekdayOf(date)], "week_total", true);
  });
  if (weights.every(weight => weight === 0) && remaining > 0)
    conflicts.push({ code: "WEEK_TOTAL_UNALLOCATED", total: confirmed, resolved: explicitSum });
  return finish(confirmed);
}

/** Effective capacity of one calendar date, before fixed events/recorded work. */
export function resolveDayCapacity(profile: CapacityProfile, date: string): DayCapacity {
  const monday = mondayOf(date);
  const week = resolveWeekCapacity(profile, monday);
  const raw = week.days[date] ?? 0;
  return {
    date,
    monday,
    minutes: applyBasis(profile, raw),
    raw_minutes: raw,
    source: week.sources[date] ?? "template",
    estimated: week.estimated[date] ?? false,
    week_budget_minutes: week.budget_override_minutes,
  };
}

/** Inclusive range resolution used by the preview and the capacity-change projection. */
export function resolveRangeCapacity(profile: CapacityProfile, from: string, to: string): DayCapacity[] {
  const result: DayCapacity[] = [];
  for (let date = from; date <= to; date = plusDays(date, 1)) result.push(resolveDayCapacity(profile, date));
  return result;
}

/**
 * Natural weeks touched by an inclusive range, resolved in full even when the range
 * only intersects part of the week (the caller only uses the intersecting days).
 */
export function resolveWeeksInRange(profile: CapacityProfile, from: string, to: string): WeekCapacity[] {
  const weeks: WeekCapacity[] = [];
  if (from > to) return weeks;
  for (let monday = mondayOf(from); monday <= to; monday = plusDays(monday, 7)) weeks.push(resolveWeekCapacity(profile, monday));
  return weeks;
}

/**
 * Whether a weekly total/baseline can be distributed over the template days.
 * Used to explain partial-week and rest-day assumptions in the preview.
 */
export function hasConfirmedWeekBudget(profile: CapacityProfile): boolean {
  return profile.weekly_baseline_minutes !== undefined && profile.weekly_baseline_minutes !== null
    || profile.weekly_range_min_minutes !== undefined && profile.weekly_range_min_minutes !== null;
}

/** Adopted weekly value with its source: confirming the baseline makes the range reachable evidence. */
export function adoptedWeeklyCapacity(profile: CapacityProfile): { minutes: number | null; source: "baseline" | "range_min" | "template" | "legacy_default" } {
  if (profile.weekly_baseline_minutes !== undefined && profile.weekly_baseline_minutes !== null)
    return { minutes: positive(profile.weekly_baseline_minutes), source: "baseline" };
  if (profile.weekly_range_min_minutes !== undefined && profile.weekly_range_min_minutes !== null)
    return { minutes: positive(profile.weekly_range_min_minutes), source: "range_min" };
  const template = templateOf(profile);
  return { minutes: template.source === "template" ? template.values.reduce((sum, value) => sum + value, 0) : null,
    source: template.source === "template" ? "template" : "legacy_default" };
}
