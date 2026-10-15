import { useRef, useState } from "react";
import { Link } from "react-router-dom";
import {
  Plus,
  ArrowRight,
  ChevronLeft,
  ChevronRight,
  RefreshCw,
  Check,
  Pencil,
  Trash2,
  CalendarDays,
  AlertTriangle,
  LockKeyhole,
  Clock3,
  ListChecks,
} from "lucide-react";
import { eventOccursOn, validateBlockPlacement } from "@planner/engine";
import type { Task, ScheduleBlock, SubjectId } from "@planner/engine";
import { usePlanner } from "./store";
import { CategoryProgress } from "./category-progress";
import {
  TaskDayRow,
  TaskDayEditor,
  ActualTimeEditor,
  moveTaskDay,
  TaskEditor,
  FixedEditor,
  Modal,
  SubjectLabel,
  ReplanDialog,
  UndoButton,
  DailyReviewEditor,
} from "./components";
import {
  today,
  addDate,
  uid,
  now,
  duration,
  fixedEventTime,
  statusLabels,
  priorityLabels,
  dayStats,
  refreshTaskProgress,
  groupDailyBlocks,
} from "./utils";

export function Dashboard() {
  const { data } = usePlanner();
  const date = today();
  const stats = dayStats(data, date);
  const groups = groupDailyBlocks(
    data.blocks.filter((block) => block.date === date),
    data.tasks,
  );
  const [edit, setEdit] = useState<ScheduleBlock[]>();
  const [record, setRecord] = useState<ScheduleBlock[]>();
  const [replan, setReplan] = useState(false);
  const [review, setReview] = useState(false);
  const pending = groups.filter((group) =>
    group.some((block) => block.status !== "completed" &&
      data.tasks.find((task) => task.id === block.task_id)?.status !== "completed"),
  );
  const examDays = Math.max(
    0,
    Math.ceil(
      (new Date(data.profile.exam_date + "T00:00:00+08:00").getTime() -
        new Date(date + "T00:00:00+08:00").getTime()) /
        86400000,
    ),
  );
  const dateLabel = new Intl.DateTimeFormat("zh-CN", {
    month: "long",
    day: "numeric",
    weekday: "long",
    timeZone: "Asia/Shanghai",
  }).format(new Date(date + "T12:00:00+08:00"));
  return (
    <>
      <div className="page-heading">
        <div>
          <h1>今天，专注眼前的一步</h1>
          <p>
            {dateLabel} · 距离初试 {examDays} 天
          </p>
        </div>
        <div className="page-heading-actions"><button onClick={() => setReview(true)}><Check size={16} />结束今天</button><button className="primary" onClick={() => setReplan(true)}>
          <RefreshCw size={17} />
          智能重排
        </button></div>
      </div>
      <div className="dashboard-grid">
        <section className="timeline-panel today-study-panel">
          <div className="section-heading">
            <h2>
              今日学习{" "}
              <span className="subtle-number">{groups.length - pending.length}/{groups.length} 项完成</span>
            </h2>
            <Link className="text-link" to="/calendar">
              调整计划
              <ArrowRight size={16} />
            </Link>
          </div>
          <div className="daily-summary">
            <span>
              <Clock3 size={17} />
              计划 <b>{duration(stats.planned)}</b>
            </span>
            <span className="success">
              已学{" "}
              <b
                data-testid="today-completed-minutes"
                data-minutes={stats.actual}
              >
                {duration(stats.actual)}
              </b>
            </span>
            <span>
              剩余 <b>{duration(stats.remaining)}</b>
            </span>
          </div>
          <p className="study-workflow-hint">学完后记录实际用时，再勾选「今日完成」。</p>
          <div className="daily-task-list">
            {!groups.length ? (
              <div className="empty">
                <ListChecks size={30} />
                <p>今天还没有学习事项</p>
                <Link className="text-link" to="/tasks">
                  添加事项并安排到今天
                  <ArrowRight size={16} />
                </Link>
              </div>
            ) : (
              data.subjects.map((subject) => {
                const subjectGroups = groups.filter((group) => data.tasks.find((task) => task.id === group[0].task_id)?.subject_id === subject.id);
                if (!subjectGroups.length) return null;
                return <section className="subject-day-group" key={subject.id} aria-label={`${subject.name}今日计划`}>
                  <h3 className="sr-only">{subject.name}</h3>
                  {subjectGroups.map((group) => (
                <TaskDayRow
                  key={group[0].task_id}
                  blocks={group}
                  onEdit={() => setEdit(group)}
                  onRecord={() => setRecord(group)}
                />
                  ))}
                </section>;
              })
            )}
          </div>
          <button className="text-link category-extra-record" onClick={() => setRecord([])}><Plus size={15} />记录事项用时</button>
          <div className="timeline-footnote">
            每日上限 {duration(data.profile.daily_limit_minutes)}，保留{" "}
            {duration(data.profile.buffer_minutes)} 机动时间。
          </div>
        </section>
        <aside className="day-sidebar">
          <section className="completion-section">
            <h2>今日完成</h2>
            <div className="completion-ring">
              <svg
                viewBox="0 0 160 160"
                role="img"
                aria-label={`今日完成率${stats.rate}%`}
              >
                <circle cx="80" cy="80" r="64" className="ring-track" />
                <circle
                  cx="80"
                  cy="80"
                  r="64"
                  className="ring-fill"
                  style={{ opacity: stats.rate > 0 ? 1 : 0 }}
                  strokeDasharray={`${Math.min(100, stats.rate) * 4.021} 402.1`}
                />
              </svg>
              <div>
                <strong>
                  {stats.rate}
                  <small>%</small>
                </strong>
                <span>实际 / 计划</span>
              </div>
            </div>
            <dl>
              <div>
                <dt>计划时长</dt>
                <dd>{duration(stats.planned)}</dd>
              </div>
              <div>
                <dt>实际完成</dt>
                <dd className="success">{duration(stats.actual)}</dd>
              </div>
              <div>
                <dt>剩余时长</dt>
                <dd>{duration(stats.remaining)}</dd>
              </div>
              <div>
                <dt>超额完成</dt>
                <dd>{duration(stats.excess)}</dd>
              </div>
            </dl>
          </section>
          <section className="unfinished-section">
            <h2>今日事项用时</h2>
            {data.tasks.filter((category) => data.logs.some((log) => log.task_id === category.id && log.date === date && log.minutes > 0)).map((category) => (
              <div className="unfinished-item" key={category.id}><i className={`subject-dot ${category.subject_id}`} />
                <span>{data.subjects.find((course) => course.id === category.subject_id)?.name} · {category.title}</span><small className="success">{duration(data.logs.filter((log) => log.task_id === category.id && log.date === date).reduce((sum, log) => sum + log.minutes, 0))}</small></div>
            ))}
            {!data.logs.some((log) => log.date === date) && <p className="muted">学完后按事项记录实际用时。</p>}
            <h2>
              待完成 <span className="subtle-number">{pending.length} 项</span>
            </h2>
            {pending.map((group) => (
              <div className="unfinished-item" key={group[0].task_id}>
                <i
                  className={`subject-dot ${data.tasks.find((task) => task.id === group[0].task_id)?.subject_id}`}
                />
                <span>
                  {
                    (() => { const task = data.tasks.find((task) => task.id === group[0].task_id)!; return `${data.subjects.find((course) => course.id === task.subject_id)?.name} · ${task.title}`; })()
                  }
                </span>
                <small>
                  {duration(
                    Math.max(
                      0,
                      group.reduce(
                        (sum, block) =>
                          sum + block.duration_minutes - block.actual_minutes,
                        0,
                      ),
                    ),
                  )}
                </small>
              </div>
            ))}
            {groups.length > 0 && !pending.length && (
              <p className="success">今天的计划已全部完成。</p>
            )}
            <Link className="text-link" to="/progress">
              查看学习进度
              <ArrowRight size={16} />
            </Link>
          </section>
          <div className="quiet-note">
            <p>每一次学习都按实际记录计入进度。</p>
            <UndoButton />
          </div>
        </aside>
      </div>
      {edit && (
        <TaskDayEditor blocks={edit} onClose={() => setEdit(undefined)} />
      )}
      {record && (
        <ActualTimeEditor
          blocks={record}
          onClose={() => setRecord(undefined)}
        />
      )}
      {replan && <ReplanDialog onClose={() => setReplan(false)} />}
      {review && <DailyReviewEditor date={date} onClose={() => setReview(false)} />}
    </>
  );
}

export function Tasks() {
  const { data, setData } = usePlanner();
  const [subject, setSubject] = useState("all");
  const [status, setStatus] = useState("all");
  const [priority, setPriority] = useState("all");
  const [deadline, setDeadline] = useState("");
  const [search, setSearch] = useState("");
  const [editor, setEditor] = useState<Task | null | undefined>();
  const [deleteTask, setDeleteTask] = useState<Task>();
  const [scheduleTask, setScheduleTask] = useState<Task>();
  const [scheduleDate, setScheduleDate] = useState(today());
  const [scheduleMinutes, setScheduleMinutes] = useState<number | "">("");
  const [notice, setNotice] = useState("");
  const [completeTask, setCompleteTask] = useState<Task>();
  const [completeMinutes, setCompleteMinutes] = useState(0);
  const visible = data.tasks
    .filter(
      (t) =>
        (subject === "all" || subject === t.subject_id) &&
        (status === "all" || status === t.status) &&
        (priority === "all" || String(t.priority) === priority) &&
        (!deadline || t.deadline <= deadline) &&
        `${t.title} ${t.description ?? ""} ${data.subjects.find((course) => course.id === t.subject_id)?.name ?? ""}`.toLowerCase().includes(search.toLowerCase()),
    )
    .sort(
      (a, b) => a.deadline.localeCompare(b.deadline) || b.priority - a.priority,
    );
  const future = visible.filter((item) => item.earliest_date && item.earliest_date > today());
  const current = visible.filter((item) => !future.includes(item));
  const [showFuture, setShowFuture] = useState(false);
  const displayed = showFuture ? visible : current;
  function complete(t: Task, actualMinutes: number) {
    setData((d) => {
      const recorded = refreshTaskProgress({
        ...d,
        logs: actualMinutes
          ? [
              ...d.logs,
              {
                id: uid(),
                user_id: d.profile.user_id,
                task_id: t.id,
                
                block_id: null,
                date: today(),
                minutes: actualMinutes,
                started_at: now(),
                ended_at: now(),
                source: "manual",
              },
            ]
          : d.logs,
        blocks: d.blocks.filter((block) =>
          block.task_id !== t.id || block.date <= today() || block.is_fixed || block.status === "completed",
        ).map((block) =>
          block.task_id === t.id ? { ...block, status: "completed", updated_at: now() } : block,
        ),
      });
      return {
        ...recorded,
        tasks: recorded.tasks.map((task) => task.id === t.id ? {
          ...task, status: "completed", updated_at: now(),
        } : task),
      };
    });
  }
  function schedule() {
    if (!scheduleTask) return;
    let next = [...data.blocks];
    const remaining = Math.max(
      0,
      scheduleTask.estimated_minutes -
        scheduleTask.completed_minutes -
        next
          .filter(
            (b) =>
              b.task_id === scheduleTask.id &&
              b.status === "planned" &&
              b.date >= today(),
          )
          .reduce((s, b) => s + Math.max(0, b.duration_minutes - b.actual_minutes), 0),
    );
    let scheduled = 0;
    const requested = scheduleMinutes === "" ? remaining : Math.min(remaining, scheduleMinutes);
    if (requested <= 0) { setNotice("请填写大于零的安排时长"); return; }
    const chunks = Array.from({ length: Math.floor(requested / 30) }, () => 30);
    if (requested % 30) chunks.push(requested % 30);
    for (const minutes of chunks) {
      if (data.profile.planning_mode !== "timed") {
        const block: ScheduleBlock = {
          id: uid(), user_id: data.profile.user_id,
          task_id: scheduleTask.id, date: scheduleDate, start_minute: 0,
          duration_minutes: minutes, actual_minutes: 0,
          is_fixed: scheduleTask.is_fixed, status: "planned",
          created_at: now(), updated_at: now(),
        };
        if (validateBlockPlacement({ ...data, blocks: next }, block)) break;
        next.push(block);
        scheduled += minutes;
        continue;
      }
      let placed = false;
      for (
        let start = data.profile.study_start_minute;
        start + minutes <= data.profile.study_end_minute;
        start += 30
      ) {
        const b: ScheduleBlock = {
          id: uid(),
          user_id: data.profile.user_id,
          task_id: scheduleTask.id,
          date: scheduleDate,
          start_minute: start,
          duration_minutes: minutes,
          actual_minutes: 0,
          is_fixed: scheduleTask.is_fixed,
          status: "planned",
          created_at: now(),
          updated_at: now(),
        };
        const validation = validateBlockPlacement({ ...data, blocks: next }, b);
        if (!validation) {
          next.push(b);
          scheduled += minutes;
          placed = true;
          break;
        }
      }
      if (!placed) break;
    }
    setData((d) => ({
      ...d,
      blocks: next,
      tasks: d.tasks.map((t) =>
        t.id === scheduleTask.id && scheduled < requested
          ? { ...t, status: "conflict", updated_at: now() }
          : t,
      ),
    }));
    setNotice(
      remaining === 0
        ? "该事项的剩余时长已全部安排"
        : scheduled < requested
          ? `已安排 ${duration(scheduled)}，剩余 ${duration(requested - scheduled)} 容量不足，事项已标记冲突。`
          : `已安排 ${duration(scheduled)} 到 ${scheduleDate}`,
    );
    setScheduleTask(undefined);
    setScheduleMinutes("");
  }
  return (
    <>
      <div className="page-heading">
        <div>
          <h1>事项管理</h1>
          <p>{current.length} 个当前事项 · {future.length} 个后续事项</p>
        </div>
        <button className="primary" onClick={() => setEditor(null)}>
          <Plus size={17} />
          新建事项
        </button>
      </div>
      <div className="filter-bar">
        <label className="search-label">
          搜索事项
          <input
            placeholder="搜索事项名称"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </label>
        <label>
          课程
          <select
            aria-label="课程"
            value={subject}
            onChange={(e) => { setSubject(e.target.value); }}
          >
            <option value="all">全部课程</option>
            {data.subjects.map((s) => (
              <option key={s.id} value={s.id}>
                {s.name}
              </option>
            ))}
          </select>
        </label>
        <label>
          状态
          <select value={status} onChange={(e) => setStatus(e.target.value)}>
            <option value="all">全部状态</option>
            {Object.entries(statusLabels).map(([k, v]) => (
              <option key={k} value={k}>
                {v}
              </option>
            ))}
          </select>
        </label>
        <label>
          优先级
          <select
            value={priority}
            onChange={(e) => setPriority(e.target.value)}
          >
            <option value="all">全部优先级</option>
            {[3, 2, 1].map((p) => (
              <option key={p} value={p}>
                {priorityLabels[p as 1 | 2 | 3]}
              </option>
            ))}
          </select>
        </label>
        <label>
          截止日期之前
          <input
            type="date"
            value={deadline}
            onChange={(e) => setDeadline(e.target.value)}
          />
        </label>
      </div>
      {notice && (
        <p role="status" className="notice">
          {notice}
        </p>
      )}
      {future.length > 0 && <label className="future-items-control"><input type="checkbox" checked={showFuture} onChange={(event) => setShowFuture(event.target.checked)} />显示后续事项（{future.length}）</label>}
      <section className="task-table">
        <div className="task-table-header">
          <span>事项 / 课程</span>
          <span>时间投入 / 预算</span>
          <span>截止 / 优先级</span>
          <span>操作</span>
        </div>
        {displayed.map((t) => (
          <article
            key={t.id}
            className="task-row"
            data-testid={`task-row-${t.id}`}
          >
            <div className="task-description">
              <SubjectLabel id={t.subject_id} />

              <strong>{t.title}</strong>
              <span className={`status ${t.status}`}>
                {statusLabels[t.status]}
              </span>
              {t.is_fixed && <LockKeyhole size={14} aria-label="固定事项" />}
              {t.description && <details className="item-scope"><summary>学习范围与完成标准</summary><p>{t.description}</p></details>}
            </div>
            <div className="task-progress">
              <span>
                {duration(data.logs.filter((log) => log.task_id === t.id).reduce((sum, log) => sum + log.minutes, 0))} /{" "}
                {duration(t.estimated_minutes)}
              </span>
              <progress
                max={t.estimated_minutes}
                value={t.completed_minutes}
                aria-label={`${t.title}时间投入进度`}
              />
            </div>
            <div className="task-deadline">
              <span>{t.deadline}</span>
              <small>{priorityLabels[t.priority]}优先级</small>
            </div>
            <div className="task-actions">
              <button
                className="icon-button"
                title="编辑事项"
                aria-label={`编辑 ${t.title}`}
                onClick={() => setEditor(t)}
              >
                <Pencil size={16} />
              </button>
              <button
                className="icon-button"
                title="安排事项日期和时长"
                aria-label={`安排 ${t.title}`}
                disabled={t.status === "completed"}
                onClick={() => {
                  setScheduleDate(t.earliest_date && t.earliest_date > today() ? t.earliest_date : today());
                  setScheduleMinutes("");
                  setScheduleTask(t);
                }}
              >
                <CalendarDays size={16} />
              </button>
              <button
                className="icon-button"
                title="手动标记完成"
                aria-label={`标记完成 ${t.title}`}
                disabled={t.status === "completed"}
                onClick={() => {
                  setCompleteMinutes(0);
                  setCompleteTask(t);
                }}
              >
                <Check size={16} />
              </button>
              <button
                className="icon-button danger"
                title="删除事项"
                aria-label={`删除 ${t.title}`}
                onClick={() => setDeleteTask(t)}
              >
                <Trash2 size={16} />
              </button>
            </div>
          </article>
        ))}
        {!displayed.length && (
          <p className="empty">没有匹配事项，可以修改筛选条件或新建事项。</p>
        )}
      </section>
      <p className="muted">
        显示 {displayed.length} 个事项 · 共 {visible.length} 个匹配事项
      </p>
      {editor !== undefined && (
        <TaskEditor
          task={editor ?? undefined}
          onClose={() => setEditor(undefined)}
        />
      )}{" "}
      {completeTask && (
        <Modal title="标记事项完成" onClose={() => setCompleteTask(undefined)}>
          <form onSubmit={(event) => {
            event.preventDefault();
            complete(completeTask, completeMinutes);
            setCompleteTask(undefined);
          }}>
            <p className="dialog-subtitle">{completeTask.title}</p>
            {completeTask.description && <p className="completion-criteria">{completeTask.description}</p>}
            <label>
              本次实际学习时长（分钟）
              <input required type="number" min={0} max={1440} step={1}
                inputMode="numeric" value={completeMinutes}
                onChange={(event) => setCompleteMinutes(Number(event.target.value))} />
            </label>
            <p className="muted">仅把你填写的时长计入进度；标记完成会停止安排这项事项。</p>
            <footer className="dialog-actions">
              <button type="button" onClick={() => setCompleteTask(undefined)}>取消</button>
              <button type="submit" className="primary"><Check size={16} />确认完成</button>
            </footer>
          </form>
        </Modal>
      )}
      {deleteTask && (
        <Modal title="删除事项" onClose={() => setDeleteTask(undefined)}>
          <p>删除“{deleteTask.title}”及关联每日计划与学习记录？</p>
          <footer className="dialog-actions">
            <button onClick={() => setDeleteTask(undefined)}>取消</button>
            <button
              className="danger"
              onClick={() => {
                setData((d) => ({
                  ...d,
                  tasks: d.tasks.filter((t) => t.id !== deleteTask.id),
                  blocks: d.blocks.filter((b) => b.task_id !== deleteTask.id),
                  logs: d.logs.filter((l) => l.task_id !== deleteTask.id),
                }));
                setDeleteTask(undefined);
              }}
            >
              <Trash2 size={16} />
              确认删除
            </button>
          </footer>
        </Modal>
      )}{" "}
      {scheduleTask && (
        <Modal title="安排时间块" onClose={() => setScheduleTask(undefined)}>
          <p>{scheduleTask.title}</p>
          <label>
            安排日期
            <input
              type="date"
              min={scheduleTask.earliest_date}
              max={scheduleTask.deadline}
              value={scheduleDate}
              onChange={(e) => setScheduleDate(e.target.value)}
            />
          </label>
          <label>当天分配时长（分钟）<input type="number" min={1} step={30} value={scheduleMinutes} placeholder="留空安排全部剩余时长" onChange={(event) => setScheduleMinutes(event.target.value === "" ? "" : Number(event.target.value))} /></label>
          <p className="muted">
            按30分钟拆分计入当天计划，不指定开始时间；容量不足会显示冲突。
          </p>
          <footer className="dialog-actions">
            <button onClick={() => setScheduleTask(undefined)}>取消</button>
            <button className="primary" onClick={schedule}>
              <CalendarDays size={16} />
              拆分并安排
            </button>
          </footer>
        </Modal>
      )}
    </>
  );
}

export function Calendar() {
  const { data, setData } = usePlanner();
  const [date, setDate] = useState(today());
  const [view, setView] = useState<"day" | "week">("week");
  const [edit, setEdit] = useState<ScheduleBlock[]>();
  const [record, setRecord] = useState<ScheduleBlock[]>();
  const [fixed, setFixed] = useState(false);
  const [notice, setNotice] = useState("");
  const dragged = useRef<string | null>(null);
  const days =
    view === "day"
      ? [date]
      : Array.from({ length: 7 }, (_, i) => addDate(date, i));
  function move(id: string, day: string) {
    const block = data.blocks.find((item) => item.id === id);
    if (!block) return;
    const group = data.blocks.filter(
      (item) => item.date === block.date && item.task_id === block.task_id,
    );
    const result = moveTaskDay(data, group, day);
    if (result.error) {
      setNotice(result.error);
      return;
    }
    setData((current) => ({
      ...current,
      blocks: result.blocks,
    }));
    setNotice("事项已移动到 " + day);
    dragged.current = null;
  }
  return (
    <>
      <div className="page-heading">
        <div>
          <h1>学习日历</h1>
          <p>按事项安排每日时长，分别记录实际用时与完成状态。</p>
        </div>
        <button className="primary" onClick={() => setFixed(true)}>
          <Plus size={17} />
          创建固定事件
        </button>
      </div>
      <div className="calendar-toolbar">
        <div className="date-controls">
          <button
            className="icon-button"
            aria-label="上一时段"
            title="上一时段"
            onClick={() => setDate(addDate(date, view === "day" ? -1 : -7))}
          >
            <ChevronLeft />
          </button>
          <input
            aria-label="日历起始日期"
            type="date"
            value={date}
            onChange={(event) => setDate(event.target.value)}
          />
          <button
            className="icon-button"
            aria-label="下一时段"
            title="下一时段"
            onClick={() => setDate(addDate(date, view === "day" ? 1 : 7))}
          >
            <ChevronRight />
          </button>
          <button onClick={() => setDate(today())}>今天</button>
        </div>
        <div className="segmented">
          <button
            className={view === "day" ? "selected" : ""}
            onClick={() => setView("day")}
          >
            日视图
          </button>
          <button
            className={view === "week" ? "selected" : ""}
            onClick={() => setView("week")}
          >
            周视图
          </button>
        </div>
      </div>
      {notice && (
        <p className="notice" role="status">
          {notice}
        </p>
      )}
      <p className="calendar-help">
        拖动事项或点击“调整日期”修改安排，学完后直接记录实际用时。
      </p>
      <div className={`calendar-grid ${view}`}>
        {days.map((day) => (
          <section
            className="calendar-day"
            data-testid="calendar-day"
            data-date={day}
            key={day}
            onDragOver={(event) => event.preventDefault()}
            onDrop={(event) => {
              event.preventDefault();
              move(
                dragged.current || event.dataTransfer.getData("text/plain"),
                day,
              );
            }}
          >
            <header>
              <div>
                <strong>
                  {new Intl.DateTimeFormat("zh-CN", {
                    weekday: "short",
                  }).format(new Date(day + "T12:00:00"))}
                </strong>
                <span className={day === today() ? "today-date" : ""}>
                  {day.slice(5)}
                </span>
              </div>
              <small>计划 {duration(dayStats(data, day).planned)}</small>
            </header>
            {groupDailyBlocks(
              data.blocks.filter((block) => block.date === day),
              data.tasks,
            ).map((group) => (
              <TaskDayRow
                key={group[0].task_id}
                blocks={group}
                draggable
                onEdit={() => setEdit(group)}
                onRecord={() => setRecord(group)}
                onDragStart={(event) => {
                  dragged.current = group[0].id;
                  event.dataTransfer.setData("text/plain", group[0].id);
                }}
              />
            ))}
            {!data.blocks.some((block) => block.date === day) && (
              <p className="empty-day">尚未安排学习事项</p>
            )}
            {data.fixed_events
              .filter((event) => eventOccursOn(event, day))
              .map((event) => (
                <div key={event.id} className="calendar-fixed">
                  <LockKeyhole size={13} />
                  <span>
                    {fixedEventTime(event.start_minute)} · {event.title} · {duration(event.duration_minutes)}
                  </span>
                </div>
              ))}
          </section>
        ))}
      </div>
      {edit && (
        <TaskDayEditor blocks={edit} onClose={() => setEdit(undefined)} />
      )}
      {record && (
        <ActualTimeEditor
          blocks={record}
          onClose={() => setRecord(undefined)}
        />
      )}
      {fixed && <FixedEditor onClose={() => setFixed(false)} />}
    </>
  );
}

export function Progress() {
  const { data } = usePlanner();
  const date = today();
  const [month, setMonth] = useState(date.slice(0, 7));
  const week = Array.from({ length: 7 }, (_, i) => addDate(date, i - 6));
  const monthStart = month + "-01";
  const monthDays = new Date(
    Number(month.slice(0, 4)),
    Number(month.slice(5, 7)),
    0,
  ).getDate();
  const days = Array.from({ length: monthDays }, (_, i) =>
    addDate(monthStart, i),
  );
  const total = data.logs.reduce((s, l) => s + l.minutes, 0);
  const remaining = data.tasks.reduce(
    (s, t) => s + Math.max(0, t.estimated_minutes - t.completed_minutes),
    0,
  );
  const pastLogs = data.logs.filter((l) => l.date <= date);
  const first = pastLogs.length
    ? pastLogs.reduce((a, b) => (a.date < b.date ? a : b)).date
    : date;
  const elapsed = Math.max(
    1,
    Math.ceil(
      (new Date(date).getTime() - new Date(first).getTime()) / 86400000,
    ) + 1,
  );
  const pace = pastLogs.reduce((s, l) => s + l.minutes, 0) / elapsed;
  const forecast = pace
    ? addDate(date, Math.ceil(remaining / pace))
    : "尚无实际记录";
  const lag = pace ? forecast > data.profile.exam_date : false;
  const overall = data.tasks.reduce((s, t) => s + t.estimated_minutes, 0);
  const burnDays = Array.from({ length: 15 }, (_, i) => addDate(date, i - 14));
  const values = burnDays.map((day) =>
    Math.max(
      0,
      overall -
        data.tasks.reduce(
          (s, t) =>
            s +
            Math.min(
              t.estimated_minutes,
              data.logs
                .filter((l) => l.task_id === t.id && l.date <= day)
                .reduce((a, l) => a + l.minutes, 0),
            ),
          0,
        ),
    ),
  );
  const maxWeekly = Math.max(
    60,
    ...data.subjects.flatMap((s) => [
      data.blocks
        .filter(
          (b) =>
            week.includes(b.date) &&
            data.tasks.find((t) => t.id === b.task_id)?.subject_id === s.id,
        )
        .reduce((a, b) => a + b.duration_minutes, 0),
      data.logs
        .filter(
          (l) =>
            week.includes(l.date) &&
            data.tasks.find((task) => task.id === l.task_id)?.subject_id === s.id,
        )
        .reduce((a, l) => a + l.minutes, 0),
    ]),
  );
  const interrupted = days.filter(
    (day) =>
      day <= date &&
      data.blocks.some((b) => b.date === day) &&
      !data.logs.some((l) => l.date === day && l.minutes > 0),
  ).length;
  return (
    <>
      <div className="page-heading">
        <div>
          <h1>学习进度</h1>
          <p>计划指明方向，真实记录呈现进步。</p>
        </div>
        <span className="record-total">
          累计实际学习 <b>{duration(total)}</b>
        </span>
      </div>
      <div className="progress-layout">
        <CategoryProgress />
        <section className="chart-panel">
          <div className="section-heading">
            <h2>近7天 · 课程进度</h2>
            <span className="muted">
              {week[0].slice(5)} — {date.slice(5)}
            </span>
          </div>
          <div className="chart-legend">
            <span>
              <i className="legend-planned" />
              计划
            </span>
            <span>
              <i className="legend-actual" />
              实际完成
            </span>
          </div>
          <div
            className="weekly-chart"
            role="img"
            aria-label="课程周计划与实际时长柱状图"
          >
            {data.subjects.map((s) => {
              const planned = data.blocks
                .filter(
                  (b) =>
                    week.includes(b.date) &&
                    data.tasks.find((t) => t.id === b.task_id)?.subject_id ===
                      s.id,
                )
                .reduce((a, b) => a + b.duration_minutes, 0);
              const actual = data.logs
                .filter(
                  (l) =>
                    week.includes(l.date) &&
                    data.tasks.find((task) => task.id === l.task_id)?.subject_id ===
                      s.id,
                )
                .reduce((a, l) => a + l.minutes, 0);
              return (
                <div className="bar-group" key={s.id}>
                  <div className="bars">
                    <div
                      className="bar planned"
                      style={{ height: `${(planned / maxWeekly) * 100}%` }}
                    >
                      <span>{duration(planned)}</span>
                    </div>
                    <div
                      className="bar actual"
                      style={{
                        height: `${(actual / maxWeekly) * 100}%`,
                        background: s.color,
                      }}
                    >
                      <span>{duration(actual)}</span>
                    </div>
                  </div>
                  <SubjectLabel id={s.id} />
                </div>
              );
            })}
          </div>
          <div className="actual-totals">
            {data.subjects.map((s) => (
              <div key={s.id}>
                <SubjectLabel id={s.id} />
                <strong>
                  {duration(
                    data.logs
                      .filter(
                        (l) =>
                          data.tasks.find((task) => task.id === l.task_id)?.subject_id === s.id,
                      )
                      .reduce((a, l) => a + l.minutes, 0),
                  )}
                </strong>
              </div>
            ))}
          </div>
        </section>
        <section className="chart-panel heatmap-panel">
          <div className="section-heading">
            <h2>月度学习热力图</h2>
            <input
              aria-label="热力图月份"
              type="month"
              value={month}
              onChange={(e) => setMonth(e.target.value)}
            />
          </div>
          <p className="muted">
            本月中断 {interrupted} 天 · 仅统计有计划但没有实际记录的过去日期
          </p>
          <div className="heatmap-weekdays">
            {["一", "二", "三", "四", "五", "六", "日"].map((d) => (
              <span key={d}>{d}</span>
            ))}
          </div>
          <div className="heatmap">
            {Array.from(
              { length: (new Date(monthStart + "T12:00:00").getDay() + 6) % 7 },
              (_, i) => (
                <div key={`space${i}`} />
              ),
            )}
            {days.map((day) => {
              const stats = dayStats(data, day);
              return (
                <div
                  key={day}
                  className={`heat-cell level-${stats.actual === 0 ? 0 : Math.min(4, Math.ceil(stats.actual / 120))}`}
                  tabIndex={0}
                  title={`${day} · 实际${duration(stats.actual)} · 完成率${stats.rate}%`}
                  aria-label={`${day} 实际${duration(stats.actual)} 完成率${stats.rate}%`}
                >
                  <b>{Number(day.slice(-2))}</b>
                  <small>{stats.actual ? duration(stats.actual) : "—"}</small>
                  <span>{stats.planned ? `${stats.rate}%` : ""}</span>
                </div>
              );
            })}
          </div>
          <div className="heatmap-legend">
            <span>少</span>
            {[0, 1, 2, 3, 4].map((n) => (
              <i className={`level-${n}`} key={n} />
            ))}
            <span>多</span>
          </div>
        </section>
        <section className="chart-panel burn-panel">
          <div className="section-heading">
            <h2>总体燃尽</h2>
            <span className={lag ? "warning" : "muted"}>
              {lag
                ? "当前进度落后"
                : pace
                  ? "按当前速度推进"
                  : "记录学习后可估算进度"}
            </span>
          </div>
          <div className="burn-stats">
            <span>
              剩余事项量 <b>{duration(remaining)}</b>
            </span>
            <span>
              预计完成 <b>{forecast}</b>
            </span>
            <span>
              目标截止 <b>{data.profile.exam_date}</b>
            </span>
          </div>
          <svg
            className="burn-chart"
            viewBox="0 0 800 180"
            role="img"
            aria-label="按实际完成记录计算的剩余事项量燃尽图"
          >
            <line x1="40" y1="150" x2="770" y2="150" stroke="#dce3eb" />
            <text x="5" y="22">
              {Math.round(overall / 60)}h
            </text>
            <text x="5" y="150">
              0
            </text>
            <polyline
              fill="none"
              stroke="#275e91"
              strokeWidth="3"
              points={values
                .map(
                  (v, i) =>
                    `${40 + (i * 730) / 14},${150 - (overall ? v / overall : 0) * 128}`,
                )
                .join(" ")}
            />
            {values.map((v, i) => (
              <circle
                key={i}
                cx={40 + (i * 730) / 14}
                cy={150 - (overall ? v / overall : 0) * 128}
                r="3"
                fill="#275e91"
              />
            ))}
            <text x="40" y="176">
              {burnDays[0]}
            </text>
            <text x="690" y="176">
              {date}
            </text>
          </svg>
          <p className="muted">
            蓝线按各事项实际完成量封顶后绘制。预计完成日期使用首次记录以来的日均实际用时，尚无记录时不作预测。
          </p>
        </section>
      </div>
    </>
  );
}
