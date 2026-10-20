import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { generateReplanPreview, validateBlockPlacement } from "./engine";
import { scheduleStrategy } from "../../../apps/api/src/planning-scheduler";
import type {
  PlannerData,
  ReplanInput,
  ScheduleBlock,
  TaskStatus,
  TimeLog,
  FixedEvent,
  Task,
  Profile,
} from "./types";

/**
 * Cross-entry contract: the automatic strategy scheduler (shared by the API and the
 * reference engine) and the manual placement validator must agree on prerequisites and
 * capacity. The exact same JSON is consumed by the Dart mirror, so a divergence between
 * the three entry points fails here instead of only shifting two separate goldens.
 */
const fixture = JSON.parse(
  readFileSync(
    "packages/planner-engine/fixtures/scheduler-contract-cases.json",
    "utf8",
  ),
);
const clock: string = fixture.clock;

function buildData(row: Record<string, any>): PlannerData {
  const profile = {
    ...fixture.base_profile,
    ...(row.profile ?? {}),
  } as Profile;
  const tasks: Task[] = (row.tasks ?? []).map((task: Record<string, any>) => ({
    user_id: "fixture-user",
    title: task.id as string,
    estimated_minutes: 30,
    completed_minutes: 0,
    priority: 2,
    deadline: row.to as string,
    is_fixed: false,
    status: "not_started" as TaskStatus,
    created_at: clock,
    updated_at: clock,
    ...task,
  }));
  const blocks: ScheduleBlock[] = (row.blocks ?? []).map(
    (block: Record<string, any>) => ({
      user_id: "fixture-user",
      start_minute: 0,
      duration_minutes: 30,
      actual_minutes: 0,
      is_fixed: false,
      status: "planned" as ScheduleBlock["status"],
      created_at: clock,
      updated_at: clock,
      ...block,
    }),
  );
  const logs: TimeLog[] = (row.logs ?? []).map((log: Record<string, any>) => ({
    user_id: "fixture-user",
    block_id: null,
    started_at: clock,
    ended_at: clock,
    source: "manual",
    ...log,
  }));
  const fixed_events: FixedEvent[] = (row.fixed_events ?? []).map(
    (event: Record<string, any>) => ({
      user_id: "fixture-user",
      title: event.id as string,
      date: row.from as string,
      kind: "course",
      repeat: "none",
      created_at: clock,
      updated_at: clock,
      ...event,
    }),
  );
  return {
    version: 1,
    profile,
    tags: [],
    tasks,
    blocks,
    logs,
    fixed_events,
    replan_runs: [],
    phases: [],
  };
}

function runtime() {
  let id = 0;
  return {
    now: () => new Date(clock),
    newId: () => `contract-${++id}`,
  };
}

function blockSummary(blocks: ScheduleBlock[]) {
  return blocks.map((block) => ({
    task_id: block.task_id,
    date: block.date,
    start_minute: block.start_minute,
    duration_minutes: block.duration_minutes,
  }));
}

function newBlockSummary(
  blocks: ScheduleBlock[],
  originals: ScheduleBlock[],
) {
  return blockSummary(
    blocks.filter(
      (block) => !originals.some((original) => original.id === block.id),
    ),
  );
}

function candidateBlock(
  row: Record<string, any>,
  placement: Record<string, any>,
): ScheduleBlock {
  return {
    id: "candidate",
    user_id: "fixture-user",
    task_id: placement.candidate.task_id,
    date: placement.candidate.date,
    start_minute: 0,
    duration_minutes: 30,
    actual_minutes: 0,
    is_fixed: false,
    status: "planned",
    created_at: clock,
    updated_at: clock,
    ...placement.candidate,
  } as ScheduleBlock;
}

describe("shared scheduler contract (API strategy / TS engine / Flutter mirror)", () => {
  for (const row of fixture.cases) {
    it(row.name, () => {
      const data = buildData(row);
      const snapshot = JSON.stringify(data);
      const from = row.from as string;
      const to = row.to as string;

      // 1. The automatic scheduler produces the documented allocation.
      let state = data;
      if (row.expected_auto) {
        const result = scheduleStrategy(data, from, to, runtime());
        expect(JSON.stringify(data)).toBe(snapshot);
        expect({
          scheduled: result.scheduled_minutes,
          unscheduled: result.unscheduled_minutes,
          issues: result.issues.map((issue) => issue.code).sort(),
        }).toEqual({
          scheduled: row.expected_auto.scheduled,
          unscheduled: row.expected_auto.unscheduled,
          issues: row.expected_auto.issues,
        });
        expect(newBlockSummary(result.blocks, data.blocks)).toEqual(
          row.expected_auto.new_blocks,
        );
        state = { ...data, blocks: result.blocks };
        // 2. Every legal automatically generated block must pass manual placement,
        //    excluding the candidate itself so its capacity is not counted twice.
        for (const block of result.blocks) {
          if (data.blocks.some((original) => original.id === block.id)) continue;
          expect(validateBlockPlacement(state, block, block.id)).toBeNull();
        }
      }

      // 3. Manual placements on the original state use the same rules as the scheduler.
      for (const placement of row.placements ?? []) {
        expect(
          validateBlockPlacement(data, candidateBlock(row, placement)),
        ).toBe(placement.expected);
      }
      for (const placement of row.post_schedule_placements ?? []) {
        expect(
          validateBlockPlacement(state, candidateBlock(row, placement)),
        ).toBe(placement.expected);
      }

      // 4. Replanning never rewrites protected records; shortfalls are reported.
      if (row.replan) {
        const operationData = data;
        const preview = generateReplanPreview(
          {
            ...operationData,
            today: row.replan.today as string,
            mode: row.replan.mode as ReplanInput["mode"],
          },
          runtime(),
        );
        expect(blockSummary(preview.after)).toEqual(
          row.replan.expected.after,
        );
        expect(preview.after).toHaveLength(row.replan.expected.after.length);
        for (const id of row.replan.expected.protected_block_ids as string[]) {
          const original = data.blocks.find((block) => block.id === id)!;
          expect(preview.after.find((block) => block.id === id)).toEqual(
            original,
          );
        }
        expect(
          preview.conflicts
            .map((conflict) => ({
              task_id: conflict.task_id,
              minutes: conflict.minutes,
            }))
            .sort((a, b) => a.task_id.localeCompare(b.task_id)),
        ).toEqual(row.replan.expected.conflicts);
        const replanned = { ...data, blocks: preview.after };
        for (const block of preview.after) {
          if (data.blocks.some((original) => original.id === block.id)) continue;
          expect(validateBlockPlacement(replanned, block, block.id)).toBeNull();
        }
        expect(JSON.stringify(operationData)).toBe(snapshot);
      }

      expect(JSON.stringify(data)).toBe(snapshot);
    });
  }
});
