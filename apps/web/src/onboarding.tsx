import { useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { ArrowLeft, ArrowRight, Check, Plus, Trash2, WandSparkles } from "lucide-react";
import { apiConfirmDraft, apiCreateDraft, apiSaveProfile, type ApiDraft, type ApiProfile } from "./api";
import { usePlanner } from "./store";
import { today } from "./utils";

const days = [["1", "周一"], ["2", "周二"], ["3", "周三"], ["4", "周四"], ["5", "周五"], ["6", "周六"], ["0", "周日"]] as const;

const initialProfile = (): ApiProfile => ({ exam_type: "考研", exam_date: `${new Date().getFullYear() + 1}-12-25`, target_school: "", target_program: "", current_progress: "", weekly_minutes: { "0": 0, "1": 120, "2": 120, "3": 120, "4": 120, "5": 120, "6": 180 }, constraints_text: "" });

export function Onboarding() {
  const navigate = useNavigate();
  const { refreshApiData } = usePlanner();
  const [step, setStep] = useState(1);
  const [profile, setProfile] = useState<ApiProfile>(initialProfile);
  const [draftId, setDraftId] = useState("");
  const [draft, setDraft] = useState<ApiDraft | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const progress = Math.round((step / 7) * 100);
  const selectedCourse = useMemo(() => draft?.courses[0]?.id ?? "", [draft]);

  const submitProfile = async () => {
    setError(""); setLoading(true);
    try {
      await apiSaveProfile(profile);
      const result = await apiCreateDraft(profile);
      setDraftId(result.id); setDraft(result.draft); setStep(7);
    } catch (caught) { setError(caught instanceof Error ? caught.message : String(caught)); }
    finally { setLoading(false); }
  };

  const confirm = async () => {
    if (!draft) return;
    setError(""); setLoading(true);
    try { await apiConfirmDraft(draftId, draft); await refreshApiData(); navigate("/"); }
    catch (caught) { setError(caught instanceof Error ? caught.message : String(caught)); }
    finally { setLoading(false); }
  };

  return <main className="onboarding-page">
    <div className="onboarding-header">
      <div><span className="eyebrow"><WandSparkles size={15} />AI 备考规划</span><h1>先把你的目标说清楚</h1><p>AI 会根据考试时间、当前进度和真实可用时间生成可调整的课程与事项。</p></div>
      <span className="onboarding-step">{step < 7 ? `第 ${step} / 6 步` : "确认计划"}</span>
    </div>
    <div className="onboarding-progress"><span style={{ width: `${progress}%` }} /></div>
    <section className="onboarding-panel">
      {step === 1 && <div className="onboarding-section"><h2>你准备参加什么考试？</h2><div className="choice-grid">{(["考研", "考公", "其他"] as const).map((kind) => <button key={kind} className={profile.exam_type === kind ? "selected" : ""} onClick={() => setProfile({ ...profile, exam_type: kind })}>{kind}</button>)}</div><p className="muted">后续课程和事项会围绕这个考试类型生成。</p></div>}
      {step === 2 && <div className="onboarding-section"><h2>考试日期</h2><label>正式考试日期<input type="date" value={profile.exam_date} min={today()} onChange={(event) => setProfile({ ...profile, exam_date: event.target.value })} /></label><p className="muted">如果日期尚未公布，先填预计日期，之后可以重新生成计划。</p></div>}
      {step === 3 && <div className="onboarding-section"><h2>你的目标</h2><label>目标院校／单位<input autoFocus value={profile.target_school} placeholder="例如：上海交通大学" onChange={(event) => setProfile({ ...profile, target_school: event.target.value })} /></label><label>专业／岗位方向<input value={profile.target_program} placeholder="例如：计算机技术、行政执法" onChange={(event) => setProfile({ ...profile, target_program: event.target.value })} /></label></div>}
      {step === 4 && <div className="onboarding-section"><h2>你现在学到哪里了？</h2><label>当前进度<textarea value={profile.current_progress} placeholder="例如：高数刚学完极限，英语词汇完成约 30%，还没有开始政治。" onChange={(event) => setProfile({ ...profile, current_progress: event.target.value })} /></label></div>}
      {step === 5 && <div className="onboarding-section"><h2>每周每天能学多久？</h2><div className="weekly-inputs">{days.map(([key, label]) => <label key={key}>{label}<div className="minutes-input"><input type="number" min={0} max={1440} step={30} value={profile.weekly_minutes[key] ?? 0} onChange={(event) => setProfile({ ...profile, weekly_minutes: { ...profile.weekly_minutes, [key]: Number(event.target.value) } })} /><span>分钟</span></div></label>)}</div><p className="muted">只填写真正能用于学习的时间，计划会自动保留机动时间。</p></div>}
      {step === 6 && <div className="onboarding-section"><h2>还有哪些限制？</h2><label>固定课程、休息时间和学习偏好<textarea value={profile.constraints_text} placeholder="例如：周三晚上有课；早上效率高；希望每次学习不超过 90 分钟。" onChange={(event) => setProfile({ ...profile, constraints_text: event.target.value })} /></label><p className="muted">填写越具体，AI 给出的事项和每日建议越容易落地。</p></div>}
      {step === 7 && draft && <div className="onboarding-section draft-section"><div className="draft-summary"><div><span className="eyebrow"><Check size={15} />AI 分析完成</span><h2>确认你的课程与事项</h2></div><p>{draft.analysis_summary}</p></div><div className="draft-notes">{draft.assumptions.map((note) => <span key={note}>假设：{note}</span>)}{draft.warnings.map((note) => <span className="warning" key={note}>提醒：{note}</span>)}</div><div className="draft-courses">{draft.courses.map((course) => <article className="draft-course" key={course.id}><header><strong>{course.name}</strong><small>{draft.items.filter((item) => item.course_id === course.id).length} 个事项</small></header><p>{course.description}</p>{draft.items.filter((item) => item.course_id === course.id).map((item) => <div className="draft-item" key={item.id}><div><input value={item.title} onChange={(event) => setDraft({ ...draft, items: draft.items.map((candidate) => candidate.id === item.id ? { ...candidate, title: event.target.value } : candidate) })} /><textarea value={item.description} onChange={(event) => setDraft({ ...draft, items: draft.items.map((candidate) => candidate.id === item.id ? { ...candidate, description: event.target.value } : candidate) })} /><small>{item.earliest_date} 至 {item.deadline}</small></div><label>预算<input type="number" min={30} step={30} value={item.estimated_minutes} onChange={(event) => setDraft({ ...draft, items: draft.items.map((candidate) => candidate.id === item.id ? { ...candidate, estimated_minutes: Number(event.target.value) } : candidate) })} />分钟</label><button className="icon-button" title="删除事项" aria-label={`删除 ${item.title}`} onClick={() => setDraft({ ...draft, items: draft.items.filter((candidate) => candidate.id !== item.id) })}><Trash2 size={15} /></button></div>)}</article>)}</div><button className="text-link" onClick={() => setDraft({ ...draft, items: [...draft.items, { id: crypto.randomUUID(), course_id: selectedCourse, title: "新事项", description: "", completion_criteria: "", estimated_minutes: 60, deadline: profile.exam_date, priority: 2 }] })}><Plus size={15} />新增事项</button></div>}
      {error && <p className="error" role="alert">{error}</p>}
      <footer className="onboarding-actions">{step > 1 && step < 7 && <button onClick={() => setStep(step - 1)}><ArrowLeft size={16} />上一步</button>}{step < 6 && <button className="primary" disabled={loading} onClick={() => setStep(step + 1)}>下一步<ArrowRight size={16} /></button>}{step === 6 && <button className="primary" disabled={loading} onClick={() => void submitProfile()}><WandSparkles size={16} />{loading ? "AI 正在分析…" : "生成课程与事项"}</button>}{step === 7 && <><button onClick={() => setStep(6)} disabled={loading}>返回修改资料</button><button className="primary" disabled={loading || !draft?.items.length} onClick={() => void confirm()}><Check size={16} />{loading ? "正在生成每日计划…" : "确认并生成每日计划"}</button></>}</footer>
    </section>
  </main>;
}
