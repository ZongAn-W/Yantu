import { useState } from "react";
import { usePlanner } from "./store";
import { addDate, duration, today } from "./utils";

export function CategoryProgress() {
  const { data } = usePlanner();
  const [date, setDate] = useState(today());
  const [period, setPeriod] = useState<"day" | "week" | "all">("day");
  const dates = period === "all" ? null : Array.from({ length: period === "week" ? 7 : 1 }, (_, index) => addDate(date, -index));
  const planned = (id: string) => data.blocks.filter((block) => block.task_id === id && (!dates || dates.includes(block.date))).reduce((sum, block) => sum + block.duration_minutes, 0);
  const actual = (id: string) => data.logs.filter((log) => log.task_id === id && (!dates || dates.includes(log.date))).reduce((sum, log) => sum + log.minutes, 0);
  return <section className="chart-panel">
    <div className="section-heading"><h2>课程与事项学习时长</h2></div>
    <p className="muted">时间分配到事项，课程汇总其下事项的计划与实际用时。</p>
    <div className="category-progress-controls">
      <div className="segmented" aria-label="统计范围">
        {([["day", "当天"], ["week", "近7天"], ["all", "累计"]] as const).map(([key, label]) => <button key={key} className={period === key ? "selected" : ""} onClick={() => setPeriod(key)}>{label}</button>)}
      </div>
      {period !== "all" && <input type="date" aria-label="统计日期" value={date} onChange={(event) => setDate(event.target.value)} />}
    </div>
    <table className="category-stats"><thead><tr><th>课程</th><th>事项</th><th>计划时长</th><th>实际用时</th></tr></thead>
      {data.subjects.filter((course) => data.tasks.some((task) => task.subject_id === course.id && (period === "all" || planned(task.id) > 0 || actual(task.id) > 0))).map((course) => {
        const items = data.tasks.filter((task) => task.subject_id === course.id && (period === "all" || planned(task.id) > 0 || actual(task.id) > 0));
        return <tbody key={course.id}>
          <tr className="subject-total"><td>{course.name}</td><td>合计</td><td>{duration(items.reduce((sum, item) => sum + planned(item.id), 0))}</td><td className="success">{duration(items.reduce((sum, item) => sum + actual(item.id), 0))}</td></tr>
          {items.map((item) => <tr key={item.id}><td></td><td>{item.title}</td><td>{duration(planned(item.id))}</td><td className="success">{duration(actual(item.id))}</td></tr>)}
        </tbody>;
      })}
    </table>
  </section>;
}
