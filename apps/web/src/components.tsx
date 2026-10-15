import { useEffect, useRef, useState, type ReactNode } from "react";
import {
  X,
  Save,
  Trash2,
  Pencil,
  Check,
  LockKeyhole,
  CalendarDays,
  AlertTriangle,
  Clock3,
  Calculator,
  Languages,
  Monitor,
  BookOpen,
  ListChecks,
  Minus,
  Plus,
  ChevronDown,
  WandSparkles,
} from "lucide-react";
import type {
  Task,
  ScheduleBlock,
  PlannerData,
  FixedEvent,
  ReplanPreview,
  SubjectId,
  Priority,
} from "@planner/engine";
import {
  generateReplanPreview,
  confirmReplan,
  undoLastReplan,
  validateBlockPlacement,
  recordTaskDayMinutes,
  stagesForCourse,
} from "@planner/engine";
import { usePlanner } from "./store";
import { apiRecordLog } from "./api";
import {
  today,
  uid,
  now,
  duration,
  minuteTime,
  statusLabels,
  priorityLabels,
  refreshTaskProgress,
  dayStats,
  groupDailyBlocks,
} from "./utils";
import { apiSettleDay } from "./api";

export function Modal({
  title,
  children,
  onClose,
}: {
  title: string;
  children: ReactNode;
  onClose: () => void;
}) {
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const previous = document.activeElement as HTMLElement;
    const panel = ref.current;
    panel?.querySelector<HTMLElement>("input,button,select")?.focus();
    const handler = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
      if (e.key === "Tab" && panel) {
        const items = Array.from(
          panel.querySelectorAll<HTMLElement>(
            'button:not([disabled]),input,select,textarea,[tabindex="0"]',
          ),
        );
        const first = items[0],
          last = items.at(-1);
        if (e.shiftKey && document.activeElement === first) {
          e.preventDefault();
          last?.focus();
        } else if (!e.shiftKey && document.activeElement === last) {
          e.preventDefault();
          first?.focus();
        }
      }
    };
    document.addEventListener("keydown", handler);
    const overflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.removeEventListener("keydown", handler);
      document.body.style.overflow = overflow;
      previous?.focus();
    };
  }, [onClose]);
  return (
    <div
      className="modal-backdrop"
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div
        ref={ref}
        className="modal"
        role="dialog"
        aria-modal="true"
        aria-label={title}
      >
        <header>
          <h2>{title}</h2>
          <button
            className="icon-button"
            title="关闭"
            aria-label="关闭"
            onClick={onClose}
          >
            <X />
          </button>
        </header>
        {children}
      </div>
    </div>
  );
}
function SubjectIcon({ id }: { id: SubjectId }) {
  const Icon = ({ math: Calculator, english: Languages, cs: Monitor, politics: BookOpen } as Record<string, typeof BookOpen>)[id] ?? BookOpen;
  return <Icon size={18} aria-hidden="true" />;
}

export function SubjectLabel({ id, graphic = false }: { id: SubjectId; graphic?: boolean }) {
  const { data } = usePlanner();
  return (
    <span className={`subject-label ${id}${graphic ? " subject-label-graphic" : ""}`}>
      {graphic ? <span className={`subject-symbol subject-tone-${id}`}><SubjectIcon id={id} /></span> : <i />}
      {data.subjects.find((course) => course.id === id)?.name ?? id}
    </span>
  );
}

function TimeProgress({ planned, actual, subjectId, preview = false }: {
  planned: number; actual: number; subjectId: SubjectId; preview?: boolean;
}) {
  const rate = planned > 0 ? Math.round(actual / planned * 100) : 0;
  const reached = planned > 0 && actual >= planned;
  const message = planned === 0 ? "今天未安排此事项，可直接记录用时"
    : actual > planned ? `超出计划 ${duration(actual - planned)}`
    : reached ? "已达到计划时长"
    : actual === 0 ? "尚未记录用时" : `距计划还差 ${duration(planned - actual)}`;
  return <div className={`time-progress subject-tone-${subjectId}${reached ? " reached" : ""}`}>
    <div className="time-progress-heading">
      <span className="time-progress-actual"><Clock3 size={14} aria-hidden="true" />
        {preview ? "本次记录" : "实际"} <strong>{duration(actual)}</strong></span>
      <span className="time-progress-plan">计划 <strong>{duration(planned)}</strong></span>
    </div>
    {planned > 0 && <div className="time-progress-track" role="progressbar"
      aria-label={preview ? "记录用时与计划对比" : "事项用时进度"}
      aria-valuemin={0} aria-valuemax={planned} aria-valuenow={Math.min(planned, Math.max(0, actual))}
      aria-valuetext={`实际 ${duration(actual)}，计划 ${duration(planned)}，用时进度 ${rate}%`}>
      <span style={{ width: `${Math.min(100, Math.max(0, rate))}%` }} />
    </div>}
    <div className="time-progress-caption">
      <span>{reached && <Check size={13} aria-hidden="true" />}{message}</span>
      {planned > 0 && <span>用时进度 <b>{rate}%</b></span>}
    </div>
  </div>;
}

export function TaskEditor({
  task,
  onClose,
}: {
  task?: Task;
  onClose: () => void;
}) {
  const { data, setData } = usePlanner();
  const [form, setForm] = useState({
    title: task?.title ?? "",
    description: task?.description ?? "",
    subject_id: task?.subject_id ?? data.subjects[0]?.id ?? "calculus",
    estimated_minutes: task?.estimated_minutes ?? 120,
    priority: task?.priority ?? 3,
    deadline: task?.deadline ?? today(),
    earliest_date: task?.earliest_date ?? today(),
    is_fixed: task?.is_fixed ?? false,
    status: task?.status ?? "not_started",
  });
  const [error, setError] = useState("");
  return (
    <Modal title={task ? "编辑事项" : "新建事项"} onClose={onClose}>
      <form
        onSubmit={(e) => {
          e.preventDefault();
          if (!form.title.trim() || !form.subject_id.trim()) {
            setError("请填写事项名称和课程");
            return;
          }
          if (form.deadline < form.earliest_date) {
            setError("截止日期不能早于开始日期");
            return;
          }
          if (task && form.estimated_minutes < task.completed_minutes) {
            setError("预计时长不能少于已完成时长");
            return;
          }
          setData((d) => ({
            ...d,
            subjects: d.subjects.some((course) => course.id === form.subject_id) ? d.subjects : [...d.subjects, { id: form.subject_id.trim(), name: form.subject_id.trim(), user_id: d.profile.user_id, color: "#275e91", priority: 2 }],
            tasks: task
              ? d.tasks.map((t) =>
                  t.id === task.id
                    ? {
                        ...t,
                        ...form,
                        title: form.title.trim(),
                        subject_id: form.subject_id.trim() as SubjectId,
                        priority: form.priority as Priority,
                        updated_at: now(),
                      }
                    : t,
                )
              : [
                  ...d.tasks,
                  {
                    ...form,
                    title: form.title.trim(),
                    id: uid(),
                    user_id: d.profile.user_id,
                    subject_id: form.subject_id.trim() as SubjectId,
                    priority: form.priority as Priority,
                    completed_minutes: 0,
                    created_at: now(),
                    updated_at: now(),
                  },
                ],
          }));
          onClose();
        }}
      >
        <label>
          事项名称
          <input
            name="title"
            list="item-name-options"
            required
            maxLength={150}
            value={form.title}
            onChange={(e) => setForm({ ...form, title: e.target.value })}
          />
          <datalist id="item-name-options">{stagesForCourse(form.subject_id).map((name) => <option key={name} value={name} />)}</datalist>
        </label>
        <label>
          学习范围与完成标准
          <textarea
            aria-label="学习范围与完成标准"
            rows={4}
            maxLength={1000}
            placeholder="例如：完成极限、导数和积分基础题；整理主要薄弱点。"
            value={form.description}
            onChange={(event) => setForm({ ...form, description: event.target.value })}
          />
        </label>
        <div className="form-grid">
          <label>课程
            <input aria-label="课程" list="course-options" required value={data.subjects.find((course) => course.id === form.subject_id)?.name ?? form.subject_id}
              onChange={(event) => setForm({ ...form, subject_id: data.subjects.find((course) => course.name === event.target.value)?.id ?? event.target.value })} />
            <datalist id="course-options">{data.subjects.map((course) => <option key={course.id} value={course.name} />)}</datalist>
          </label>
          <label>
            优先级
            <select
              value={form.priority}
              onChange={(e) =>
                setForm({
                  ...form,
                  priority: Number(e.target.value) as Priority,
                })
              }
            >
              {[3, 2, 1].map((p) => (
                <option key={p} value={p}>
                  {priorityLabels[p as Priority]}
                </option>
              ))}
            </select>
          </label>
          <label>
            预计总时长（分钟）
            <input
              type="number"
              min={30}
              step={30}
              max={30000}
              required
              value={form.estimated_minutes}
              onChange={(e) =>
                setForm({ ...form, estimated_minutes: Number(e.target.value) })
              }
            />
          </label>
          <label>
            截止日期
            <input
              type="date"
              required
              value={form.deadline}
              onChange={(e) => setForm({ ...form, deadline: e.target.value })}
            />
          </label>
          <label>
            开始日期
            <input
              type="date"
              required
              value={form.earliest_date}
              onChange={(e) =>
                setForm({ ...form, earliest_date: e.target.value })
              }
            />
          </label>
          <label>
            状态
            <select
              value={form.status}
              onChange={(e) =>
                setForm({ ...form, status: e.target.value as Task["status"] })
              }
            >
              {Object.entries(statusLabels)
                .filter(([k]) => k !== "completed")
                .map(([k, v]) => (
                  <option key={k} value={k}>
                    {v}
                  </option>
                ))}
              {task?.status === "completed" && (
                <option value="completed">完成</option>
              )}
            </select>
          </label>
        </div>
        <label className="checkbox">
          <input
            type="checkbox"
            checked={form.is_fixed}
            onChange={(e) => setForm({ ...form, is_fixed: e.target.checked })}
          />
          固定事项（排入后不可自动移动）
        </label>
        {error && (
          <p role="alert" className="error">
            {error}
          </p>
        )}
        <footer className="dialog-actions">
          <button type="button" onClick={onClose}>
            取消
          </button>
          <button className="primary" type="submit">
            <Save size={16} />
            保存事项
          </button>
        </footer>
      </form>
    </Modal>
  );
}

export function moveTaskDay(
  data: PlannerData,
  blocks: ScheduleBlock[],
  targetDate: string,
): { blocks: ScheduleBlock[]; error?: string } {
  if (!blocks.length) return { blocks: data.blocks };
  const firstTask = data.tasks.find((task) => task.id === blocks[0].task_id);
  if (firstTask && data.logs.filter((log) => log.task_id === firstTask.id && log.date === blocks[0].date).reduce((sum, log) => sum + log.minutes, 0) > 0)
    return { blocks: data.blocks, error: "已记录用时的事项保留在学习当天；请为剩余事项另行安排日期" };
  if (
    blocks.some(
      (block) =>
        block.is_fixed ||
        block.status === "completed" ||
        data.tasks.find((task) => task.id === block.task_id)?.is_fixed,
    )
  )
    return { blocks: data.blocks, error: "固定或已完成的事项不可移动" };
  const ids = new Set(blocks.map((block) => block.id));
  const remaining = data.blocks.filter((block) => !ids.has(block.id));
  const placed: ScheduleBlock[] = [];
  for (const block of [...blocks].sort(
    (a, b) => a.start_minute - b.start_minute,
  )) {
    if (data.profile.planning_mode !== "timed") {
      const candidate = {
        ...block,
        date: targetDate,
        start_minute: 0,
        updated_at: now(),
      };
      const validation = validateBlockPlacement(
        { ...data, blocks: [...remaining, ...placed] },
        candidate,
      );
      if (validation) return { blocks: data.blocks, error: validation };
      placed.push(candidate);
      continue;
    }
    let found: ScheduleBlock | undefined;
    for (
      let start =
        Math.ceil(
          data.profile.study_start_minute / data.profile.granularity_minutes,
        ) * data.profile.granularity_minutes;
      start + block.duration_minutes <= data.profile.study_end_minute;
      start += data.profile.granularity_minutes
    ) {
      const candidate = {
        ...block,
        date: targetDate,
        start_minute: start,
        updated_at: now(),
      };
      const validation = validateBlockPlacement(
        { ...data, blocks: [...remaining, ...placed] },
        candidate,
      );
      if (!validation) {
        found = candidate;
        break;
      }
    }
    if (!found)
      return { blocks: data.blocks, error: "目标日期容量不足，请选择其他日期" };
    placed.push(found);
  }
  return { blocks: [...remaining, ...placed] };
}

export function ActualTimeEditor({ blocks, onClose }: {
  blocks: ScheduleBlock[]; onClose: () => void;
}) {
  const { data, setData, apiConfigured, refreshApiData } = usePlanner();
  const task = data.tasks.find((item) => item.id === blocks[0]?.task_id);
  const date = blocks[0]?.date ?? today();
  const [subjectId, setSubjectId] = useState<SubjectId>(task?.subject_id ?? data.subjects[0]?.id);
  const [categoryId, setCategoryId] = useState(task?.id ?? data.tasks.find((item) => item.subject_id === subjectId)?.id ?? "");
  const [minutesInput, setMinutesInput] = useState<number | "">(() => data.logs.filter((log) => log.task_id === categoryId && log.date === date).reduce((sum, log) => sum + log.minutes, 0));
  const minutes = minutesInput === "" ? 0 : minutesInput;
  const planned = data.blocks.filter((block) => {
    const blockTask = data.tasks.find((item) => item.id === block.task_id);
    return block.date === date && blockTask && blockTask.id === categoryId;
  }).reduce((sum, block) => sum + block.duration_minutes, 0);
  const [error, setError] = useState("");
  const changeMinutes = (value: number | "") => { setMinutesInput(value); setError(""); };
  const selectCategory = (id: string) => {
    setCategoryId(id); changeMinutes(data.logs.filter((log) => log.task_id === id && log.date === date).reduce((sum, log) => sum + log.minutes, 0));
  };
  return <Modal title="记录实际用时" onClose={onClose}>
    <form className="actual-time-form" onSubmit={async (event) => {
      event.preventDefault();
      try { setData((current) => recordTaskDayMinutes(current, categoryId, date, minutes)); if (apiConfigured) { await apiRecordLog({ item_id: categoryId, date, minutes }); await refreshApiData(); } onClose(); }
      catch (caught) { setError(String((caught as Error).message)); }
    }}>
      <p className="dialog-subtitle actual-time-date"><CalendarDays size={15} aria-hidden="true" />{date} · 当天累计用时</p>
      {task ? <div className="record-item-heading"><SubjectLabel id={task.subject_id} /><strong>{task.title}</strong></div> : <div className="form-grid">
        <label><span className={`time-field-label subject-tone-${subjectId}`}><SubjectIcon id={subjectId} />课程</span><select aria-label="课程" value={subjectId} onChange={(event) => {
          const id = event.target.value as SubjectId; setSubjectId(id);
          selectCategory(data.tasks.find((item) => item.subject_id === id)?.id ?? "");
        }}>{data.subjects.map((subject) => <option value={subject.id} key={subject.id}>{subject.name}</option>)}</select></label>
        <label>事项<select aria-label="事项" value={categoryId} onChange={(event) => selectCategory(event.target.value)}>
          {data.tasks.filter((item) => item.subject_id === subjectId).map((item) => <option value={item.id} key={item.id}>{item.title}</option>)}
        </select></label>
      </div>}
      <div className="time-preview" aria-live="polite" aria-atomic="true">
        <TimeProgress planned={planned} actual={Math.max(0, minutes)} subjectId={subjectId} preview />
      </div>
      <div className="time-entry-section">
        <label htmlFor="actual-minutes">实际用时（分钟）</label>
        <div className="minutes-stepper">
          <button type="button" aria-label="减少15分钟" disabled={minutes <= 0}
            onClick={() => changeMinutes(Math.max(0, minutes - 15))}><Minus size={18} aria-hidden="true" /></button>
          <input id="actual-minutes" autoFocus required aria-label="实际用时（分钟）"
            type="number" min={0} max={1440} step={1} inputMode="numeric" value={minutesInput}
            onChange={(event) => changeMinutes(event.target.value === "" ? "" : event.target.valueAsNumber)} />
          <button type="button" aria-label="增加15分钟" disabled={minutes >= 1440}
            onClick={() => changeMinutes(Math.min(1440, minutes + 15))}><Plus size={18} aria-hidden="true" /></button>
        </div>
        <div className="time-presets" role="group" aria-label="快捷填写累计用时">
          {[30, 60, 90, 120].map((value) => <button key={value} type="button"
            aria-pressed={minutesInput === value} onClick={() => changeMinutes(value)}>{duration(value)}</button>)}
        </div>
        {planned > 0 && planned <= 1440 && <button className="text-link fill-planned-time" type="button"
          onClick={() => changeMinutes(planned)}><Check size={14} aria-hidden="true" />按计划填写 · {duration(planned)}</button>}
      </div>
      {error && <p className="error" role="alert">{error}</p>}
      <footer className="dialog-actions"><button type="button" onClick={onClose}>取消</button>
        <button className="primary" type="submit"><Save size={16} />保存实际用时</button></footer>
    </form>
  </Modal>;
}

export function TaskDayEditor({
  blocks,
  onClose,
}: {
  blocks: ScheduleBlock[];
  onClose: () => void;
}) {
  const { data, setData } = usePlanner();
  const [date, setDate] = useState(blocks[0]?.date ?? today());
  const [error, setError] = useState("");
  const task = data.tasks.find((item) => item.id === blocks[0]?.task_id);
  const canMove = Boolean(task) && data.logs.filter((log) => log.task_id === task!.id && log.date === blocks[0].date).reduce((sum, log) => sum + log.minutes, 0) === 0 && blocks.every(
    (block) =>
      !block.is_fixed &&
      block.status !== "completed" &&
      block.actual_minutes === 0 &&
      !data.tasks.find((task) => task.id === block.task_id)?.is_fixed,
  );
  return (
    <Modal title="调整事项日期" onClose={onClose}>
      <p className="dialog-subtitle">
        {data.tasks.find((task) => task.id === blocks[0]?.task_id)!.title} ·{" "}
        {duration(
          blocks.reduce((sum, block) => sum + block.duration_minutes, 0),
        )}
      </p>
      <label>
        安排日期
        <input
          aria-label="安排日期"
          type="date"
          value={date}
          onChange={(event) => setDate(event.target.value)}
          disabled={!canMove}
        />
      </label>
      <p className="muted">
        只调整日期，不指定学习开始时间。实际学习用时请使用“记录用时”。
      </p>
      {!canMove && <p className="muted">已记录用时、已完成或固定的计划保留在原日期。</p>}
      {error && (
        <p className="error" role="alert">
          {error}
        </p>
      )}
      <footer className="dialog-actions">
        <button onClick={onClose}>取消</button>
        <button
          className="primary"
          disabled={!canMove}
          onClick={() => {
            const result = moveTaskDay(data, blocks, date);
            if (result.error) {
              setError(result.error);
              return;
            }
            setData((current) => ({
              ...current,
              blocks: result.blocks,
            }));
            onClose();
          }}
        >
          <CalendarDays size={16} />
          保存日期
        </button>
      </footer>
    </Modal>
  );
}

export function TaskDayRow({ blocks, draggable = false, onEdit, onRecord, onDragStart }: {
  blocks: ScheduleBlock[]; draggable?: boolean; onEdit: () => void;
  onRecord: () => void; onDragStart?: (event: React.DragEvent) => void;
}) {
  const { data, setData } = usePlanner();
  if (!blocks.length) return null;
  const task = data.tasks.find((item) => item.id === blocks[0].task_id);
  if (!task) return null;
  const planned = blocks.reduce((sum, block) => sum + block.duration_minutes, 0);
  const actual = data.logs.filter((log) => log.task_id === task.id && log.date === blocks[0].date).reduce((sum, log) => sum + log.minutes, 0);
  const completed = task.status === "completed" || blocks.every((block) => block.status === "completed");
  const course = data.subjects.find((item) => item.id === task.subject_id);
  const rate = planned > 0 ? Math.round(actual / planned * 100) : 0;
  const tone = { "--course-color": course?.color ?? "#275e91" } as React.CSSProperties;
  const advice = blocks.find((block) => block.advice_text)?.advice_text;
  return <article className={`study-row ${completed ? "done" : ""} ${actual >= planned && planned > 0 ? "time-reached" : ""}`} style={tone}
    draggable={draggable && actual === 0 && blocks.every((block) => !block.is_fixed && block.status !== "completed") && !task.is_fixed}
    onDragStart={onDragStart} data-testid="schedule-block" data-block-id={blocks[0].id}
    data-category-day-id={`${task.id}:${blocks[0].date}`} data-task-day-id={`${task.id}:${blocks[0].date}`}>
    <div className="study-row-heading">
      <span className="course-marker" aria-hidden="true" />
      <strong className="study-course-name">{course?.name ?? task.subject_id}</strong>
      <span className="study-item-name">{task.title}</span>
    </div>
    <div className="study-row-time">
      <div className="study-time-values"><span>今日目标 <strong>{duration(planned)}</strong></span><span className={actual > 0 ? "has-actual" : ""}>已学 <b>{duration(actual)}</b></span></div>
      <div className="study-time-track" role="progressbar" aria-label={`${course?.name ?? task.subject_id} · ${task.title}用时进度`}
        aria-valuemin={0} aria-valuemax={planned} aria-valuenow={Math.min(planned, actual)} aria-valuetext={`已学 ${duration(actual)}，目标 ${duration(planned)}`}>
        <span style={{ width: `${Math.min(100, rate)}%` }} />
      </div>
      {actual > planned && <small className="study-time-overrun">超出目标 {duration(actual - planned)}</small>}
    </div>
    <div className="study-row-actions">
      <button className="study-record-button" aria-label={`记录实际用时：${task.title}`} onClick={onRecord}>
        <Clock3 size={16} /><span>{actual > 0 ? "修改用时" : "记录用时"}</span>
      </button>
      <label className="study-completion" title={task.status === "completed" ? "整项学习已完成" : "标记今天的学习安排完成"}>
        <input type="checkbox" aria-label={`完成当天安排：${task.title}`} checked={completed} disabled={task.status === "completed"}
          onChange={(event) => {
            const status = event.target.checked ? "completed" : "planned";
            const ids = new Set(blocks.map((block) => block.id));
            setData((current) => ({ ...current, blocks: current.blocks.map((block) => ids.has(block.id)
              ? { ...block, status, updated_at: now() } : block) }));
          }} />
        <span>{completed ? "今日已完成" : "今日完成"}</span>
      </label>
      <button className="study-date-button" title="调整日期" aria-label={`调整日期：${task.title}`} onClick={onEdit}><CalendarDays size={15} /><span>改日期</span></button>
    </div>
    <details className="study-row-details">
      <summary>学习内容 <ChevronDown size={13} aria-hidden="true" /></summary>
      <div>{advice && <p className="study-advice"><WandSparkles size={13} />今日建议：{advice}</p>}{task.description && <p>{task.description}</p>}<span className="study-item-deadline"><CalendarDays size={13} />事项截止 {task.deadline}</span></div>
    </details>
  </article>;
}

export function DailyReviewEditor({ date, onClose }: { date: string; onClose: () => void }) {
  const { data, setData, apiConfigured, refreshApiData } = usePlanner();
  const groups = groupDailyBlocks(data.blocks.filter((block) => block.date === date), data.tasks);
  const [entries, setEntries] = useState(() => groups.map((group) => ({
    item_id: group[0].task_id,
    actual_minutes: data.logs.filter((log) => log.task_id === group[0].task_id && log.date === date).reduce((sum, log) => sum + log.minutes, 0),
    completion_status: (group.every((block) => block.status === "completed") ? "completed" : "not_started") as "not_started" | "partial" | "completed" | "skipped",
    feedback: "",
  })));
  const [feedback, setFeedback] = useState("");
  const [error, setError] = useState("");
  const update = (itemId: string, change: Partial<typeof entries[number]>) => setEntries((current) => current.map((entry) => entry.item_id === itemId ? { ...entry, ...change } : entry));
  return <Modal title={`${date} · 结束今天`} onClose={onClose}>
    <p className="dialog-subtitle">记录今天完成到哪里，服务器会据此调整后续安排。</p>
    <div className="review-list">{entries.map((entry) => { const task = data.tasks.find((item) => item.id === entry.item_id); return <div className="review-row" key={entry.item_id}><strong>{data.subjects.find((subject) => subject.id === task?.subject_id)?.name} · {task?.title}</strong><label>实际用时<input type="number" min={0} max={1440} step={1} value={entry.actual_minutes} onChange={(event) => update(entry.item_id, { actual_minutes: Number(event.target.value) })} /></label><label>完成程度<select value={entry.completion_status} onChange={(event) => update(entry.item_id, { completion_status: event.target.value as typeof entry.completion_status })}><option value="not_started">未开始</option><option value="partial">部分完成</option><option value="completed">已完成</option><option value="skipped">跳过</option></select></label><label>卡点或反馈<input value={entry.feedback} onChange={(event) => update(entry.item_id, { feedback: event.target.value })} placeholder="可选" /></label></div>; })}</div>
    <label>今天整体反馈<textarea value={feedback} onChange={(event) => setFeedback(event.target.value)} placeholder="例如：上午效率低，复合函数求导仍不熟。" /></label>
    {error && <p className="error" role="alert">{error}</p>}
    <footer className="dialog-actions"><button onClick={onClose}>取消</button><button className="primary" onClick={async () => { try { setData((current) => entries.reduce((next, entry) => { const recorded = recordTaskDayMinutes(next, entry.item_id, date, entry.actual_minutes); return { ...recorded, blocks: recorded.blocks.map((block) => block.task_id === entry.item_id && block.date === date ? { ...block, status: entry.completion_status === "completed" ? "completed" : "planned", completion_status: entry.completion_status, feedback: entry.feedback, updated_at: now() } : block) }; }, current)); if (apiConfigured) { await apiSettleDay(date, { feedback, entries }); await refreshApiData(); } onClose(); } catch (caught) { setError(caught instanceof Error ? caught.message : String(caught)); } }}><Check size={16} />保存并调整后续计划</button></footer>
  </Modal>;
}

export function FixedEditor({ onClose }: { onClose: () => void }) {
  const { data, setData } = usePlanner();
  const [title, setTitle] = useState("");
  const [date, setDate] = useState(today());
  const [time, setTime] = useState("12:00");
  const [minutes, setMinutes] = useState(60);
  const [kind, setKind] = useState<FixedEvent["kind"]>("rest");
  const [repeat, setRepeat] = useState<FixedEvent["repeat"]>("none");
  const [error, setError] = useState("");
  return (
    <Modal title="创建固定事件" onClose={onClose}>
      <form
        onSubmit={(e) => {
          e.preventDefault();
          const event: FixedEvent = {
            id: uid(),
            user_id: data.profile.user_id,
            title,
            date,
            start_minute: minuteTime(time),
            duration_minutes: minutes,
            kind,
            repeat,
            created_at: now(),
            updated_at: now(),
          };
          const blocks = data.profile.planning_mode === "timed" ? data.blocks.filter(
            (b) =>
              b.date === date &&
              b.start_minute < event.start_minute + minutes &&
              b.start_minute + b.duration_minutes > event.start_minute,
          ) : [];
          if (blocks.length) {
            setError("该时段已有学习时间块，请先移动时间块再添加固定事件");
            return;
          }
          setData((d) => ({ ...d, fixed_events: [...d.fixed_events, event] }));
          onClose();
        }}
      >
        <label>
          事件名称
          <input
            required
            maxLength={100}
            value={title}
            onChange={(e) => setTitle(e.target.value)}
          />
        </label>
        <div className="form-grid">
          <label>
            日期
            <input
              required
              type="date"
              value={date}
              onChange={(e) => setDate(e.target.value)}
            />
          </label>
          <label>
            开始时间
            <input
              required
              type="time"
              step={1800}
              value={time}
              onChange={(e) => setTime(e.target.value)}
            />
          </label>
          <label>
            时长（分钟）
            <input
              required
              type="number"
              min={30}
              max={840}
              step={30}
              value={minutes}
              onChange={(e) => setMinutes(Number(e.target.value))}
            />
          </label>
          <label>
            类型
            <select
              aria-label="类型"
              value={kind}
              onChange={(e) => setKind(e.target.value as FixedEvent["kind"])}
            >
              <option value="rest">休息</option>
              <option value="course">固定课程</option>
              <option value="exam">模拟考试</option>
              <option value="official_exam">正式考试</option>
            </select>
          </label>
          <label>
            重复
            <select
              aria-label="重复"
              value={repeat}
              onChange={(e) =>
                setRepeat(e.target.value as FixedEvent["repeat"])
              }
            >
              <option value="none">不重复</option>
              <option value="daily">每天</option>
              <option value="weekly">每周</option>
            </select>
          </label>
        </div>
        {error && (
          <p role="alert" className="error">
            {error}
          </p>
        )}
        <footer className="dialog-actions">
          <button type="button" onClick={onClose}>
            取消
          </button>
          <button type="submit" className="primary">
            <LockKeyhole size={16} />
            保存固定事件
          </button>
        </footer>
      </form>
    </Modal>
  );
}

export function ReplanDialog({ onClose }: { onClose: () => void }) {
  const { data, setData } = usePlanner();
  const [mode, setMode] = useState<"unfinished" | "overcompleted">(
    "unfinished",
  );
  const [error, setError] = useState("");
  const excess = dayStats(data, today()).excess;
  const preview: ReplanPreview = generateReplanPreview({
    ...data,
    profile: data.profile,
    tasks: data.tasks,
    blocks: data.blocks,
    logs: data.logs,
    fixed_events: data.fixed_events,
    today: today(),
    mode,
    excess_minutes: excess,
  });
  return (
    <Modal title="重排预览" onClose={onClose}>
      <p className="dialog-subtitle">保守调整 · 确认前不会修改计划</p>
      <div className="segmented">
        <button
          className={mode === "unfinished" ? "selected" : ""}
          onClick={() => setMode("unfinished")}
        >
          未完成顺延 · 未来14天
        </button>
        <button
          className={mode === "overcompleted" ? "selected" : ""}
          onClick={() => setMode("overcompleted")}
        >
          超额提前 · 未来7天
        </button>
      </div>
      {mode === "overcompleted" && (
        <p className="muted">
          今日可用超额容量：{duration(excess)}，仅小范围提前事项。
        </p>
      )}
      <div className="preview-counts">
        <span>
          顺延 <b>{preview.postponed.length}</b>
        </span>
        <span>
          提前 <b>{preview.advanced.length}</b>
        </span>
        <span>
          新增 <b>{preview.changes.filter((c) => c.type === "added").length}</b>
        </span>
        <span>
          删除{" "}
          <b>{preview.changes.filter((c) => c.type === "deleted").length}</b>
        </span>
      </div>
      <h3>事项变化</h3>
      {!preview.changes.length && (
        <p className="empty">没有需要调整的时间块。</p>
      )}
      <div className="preview-list">
        {preview.changes.map((c) => (
          <div key={c.id}>
            <span>
              {
                data.tasks.find((t) => t.id === (c.after ?? c.before)?.task_id)
                  ?.title
              }
            </span>
            <small>
              {c.before ? c.before.date : "新增"}{" "}
              <span aria-hidden="true">→</span>{" "}
              {c.after ? c.after.date : "删除"} ·{" "}
              {duration((c.after ?? c.before)!.duration_minutes)}
            </small>
          </div>
        ))}
      </div>
      <h3>每日学习时长</h3>
      <div className="preview-list">
        {preview.daily_changes.map((d) => (
          <div key={d.date}>
            <span>{d.date}</span>
            <small>
              {duration(d.before_minutes)} → {duration(d.after_minutes)}
            </small>
          </div>
        ))}
      </div>
      {preview.conflicts.length > 0 && (
        <>
          <h3 className="warning">
            <AlertTriangle size={18} />
            容量冲突
          </h3>
          {preview.conflicts.map((c) => (
            <p className="conflict" key={c.task_id}>
              {c.title} · {duration(c.minutes)}
              <small>{c.reason}</small>
            </p>
          ))}
        </>
      )}
      {error && (
        <p className="error" role="alert">
          {error}
        </p>
      )}
      <footer className="dialog-actions">
        <button onClick={onClose}>取消调整</button>
        <button
          className="primary"
          onClick={() => {
            try {
              setData((d) => confirmReplan(d, preview));
              onClose();
            } catch (e) {
              setError(String(e));
            }
          }}
        >
          <Check size={16} />
          确认调整
        </button>
      </footer>
    </Modal>
  );
}
export function UndoButton() {
  const { data, setData } = usePlanner();
  const [error, setError] = useState("");
  return (
    <>
      <button
        disabled={!data.replan_runs.some((r) => r.status === "confirmed")}
        onClick={() => {
          try {
            setData((d) => undoLastReplan(d));
            setError("");
          } catch (e) {
            setError(String(e));
          }
        }}
        title="恢复最近一次重排前的计划"
      >
        <Clock3 size={16} />
        撤销最近调整
      </button>
      {error && (
        <p role="alert" className="error">
          {error}
        </p>
      )}
    </>
  );
}
