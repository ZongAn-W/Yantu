import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { addDays, availableDailyMinutes, confirmReplan, eventOccursOn, fixedEventMinutesForDate, generateReplanPreview, remainingTaskMinutes, taskCompletedMinutes, undoLastReplan, validateBlockPlacement } from './engine';
import { mergeTaskDayLogs, recordTaskDayMinutes } from './study-records';
import { goldenClock, goldenInputs, type GoldenCase } from './golden-cases';
import type { PlannerData, ReplanInput, ScheduleBlock, Task, TimeLog, FixedEvent, Profile } from './types';

const path = resolve('packages/planner-engine/fixtures/planner-goldens.json');
const json = (value: unknown) => JSON.parse(JSON.stringify(value)) as unknown;
function run(test: GoldenCase): unknown {
  let id = 0;
  const runtime = { now: () => new Date(goldenClock), newId: () => `gold-${String(++id).padStart(4, '0')}` };
  const a = test.args;
  const data = a.data as PlannerData;
  const original = JSON.stringify(data);
  const error = (operation: () => unknown) => { try { operation(); return null; } catch (e) { return (e as Error).message; } };
  try {
    switch (test.operation) {
      case 'date': return addDays(a.date as string, a.days as number);
      case 'capacity': return { occurs: (a.events as FixedEvent[]).map(event => eventOccursOn(event, a.date as string)), union: fixedEventMinutesForDate(a.events as FixedEvent[], a.date as string), without_rest: fixedEventMinutesForDate(a.events as FixedEvent[], a.date as string, false), available: availableDailyMinutes(a.profile as Profile, a.events as FixedEvent[], a.date as string) };
      case 'totals': return { completed: taskCompletedMinutes(a.task as Task, a.logs as TimeLog[]), remaining: remainingTaskMinutes(a.task as Task, a.logs as TimeLog[]) };
      case 'placement': return validateBlockPlacement(data, a.candidate as ScheduleBlock, a.ignoreId as string | undefined);
      case 'record': return recordTaskDayMinutes(data, a.taskId as string, a.date as string, a.minutes as number, runtime);
      case 'records': return (a.entries as Array<{ taskId: string; date: string; minutes: number }>).reduce((state, entry) => recordTaskDayMinutes(state, entry.taskId, entry.date, entry.minutes, runtime), data);
      case 'merge': return mergeTaskDayLogs(a.base as TimeLog[], a.local as TimeLog[], a.remote as TimeLog[]);
      case 'lifecycle': {
        const preview = generateReplanPreview({ ...data, today: a.today, mode: a.mode, excess_minutes: a.excess_minutes } as ReplanInput, runtime);
        expect(JSON.stringify(data)).toBe(original);
        const confirmed = confirmReplan(data, preview);
        const undone = undoLastReplan(confirmed);
        return { preview, confirmed, undone,
          errors: {
            foreign: error(() => confirmReplan(data, { ...preview, user_id: 'other' })),
            duplicate: error(() => confirmReplan(confirmed, preview)),
            stale: error(() => confirmReplan({ ...data, blocks: [...data.blocks, { ...data.blocks[0], id: 'new' }] }, preview)),
            changed_undo: error(() => undoLastReplan({ ...confirmed, blocks: [...confirmed.blocks, { ...data.blocks[0], id: 'new' }] })),
            empty_undo: error(() => undoLastReplan({ ...data, replan_runs: [] })),
          },
        };
      }
      default: throw new Error(`unknown golden operation ${test.operation}`);
    }
  } catch (e) { return { error: (e as Error).message }; }
  finally { expect(JSON.stringify(data)).toBe(original); }
}

if (process.env.UPDATE_PLANNER_GOLDENS === '1') {
  writeFileSync(path, JSON.stringify({ version: 1, clock: goldenClock, id_prefix: 'gold-', cases: goldenInputs().map(test => ({ ...test, expected: json(run(test)) })) }, null, 2) + '\n');
}
const fixture = JSON.parse(readFileSync(path, 'utf8')) as { cases: GoldenCase[] };
describe('shared Dart / TypeScript JSON goldens', () => {
  it('committed inputs match documented cases', () => expect(fixture.cases.map(({ expected: _, ...input }) => input)).toEqual(json(goldenInputs())));
  for (const test of fixture.cases) it(test.name, () => expect(json(run(test))).toEqual(test.expected));
});
