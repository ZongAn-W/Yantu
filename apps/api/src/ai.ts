import { PlanDraftSchema, type PlanDraft, type ProfileInput } from "./contracts.js";
import { config } from "./config.js";

function addDays(date: string, amount: number) {
  const value = new Date(`${date}T00:00:00Z`);
  value.setUTCDate(value.getUTCDate() + amount);
  return value.toISOString().slice(0, 10);
}

function fallback(profile: ProfileInput): PlanDraft {
  const courses = profile.exam_type === "考公"
    ? ["行测", "申论"]
    : ["数学", "英语", "专业课", "政治"];
  const ids = courses.map((name, index) => `course-${index + 1}-${name}`);
  const items = courses.flatMap((name, index) => [
    {
      id: `item-${index + 1}-foundation`, course_id: ids[index], title: "基础一轮",
      description: `${name}基础知识、例题和错题整理。当前进度：${profile.current_progress || "尚未填写"}`,
      completion_criteria: "完成一轮材料并整理薄弱点", estimated_minutes: 120 * 60,
      earliest_date: addDays(new Date().toISOString().slice(0, 10), 0), deadline: profile.exam_date, priority: index < 2 ? 3 : 2,
    },
    {
      id: `item-${index + 1}-practice`, course_id: ids[index], title: "真题与强化",
      description: `${name}真题训练、计时练习和复盘。`, completion_criteria: "完成题目并记录错因",
      estimated_minutes: 80 * 60, earliest_date: addDays(new Date().toISOString().slice(0, 10), 14), deadline: profile.exam_date, priority: 2,
    },
  ]);
  return PlanDraftSchema.parse({ courses: courses.map((name, index) => ({ id: ids[index], name, description: "AI 根据备考目标生成的课程", priority: index < 2 ? 3 : 2 })), items,
    analysis_summary: `根据${profile.exam_type}目标、考试日期和当前进度生成初始学习框架。确认后还可以逐项修改。`,
    assumptions: ["每日计划会按照每周可用时间分配", "实际学习反馈会用于每日结算"], warnings: [] });
}

async function callModel(profile: ProfileInput): Promise<PlanDraft> {
  const response = await fetch(`${config.aiBaseUrl}/chat/completions`, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${config.aiApiKey}` },
    body: JSON.stringify({
      model: config.aiModel,
      reasoning_effort: config.aiReasoningEffort,
      temperature: 0.2,
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: "你是学习规划师。只返回符合要求的 JSON，不要 Markdown。课程和事项必须可执行、可计时，事项日期不得晚于考试日期。" },
        { role: "user", content: JSON.stringify({ profile, output: { courses: "课程数组，每个有 id,name,description,priority", items: "事项数组，每个有 id,course_id,title,description,completion_criteria,estimated_minutes,earliest_date,deadline,priority", analysis_summary: "分析摘要", assumptions: "假设数组", warnings: "风险数组" } }) },
      ],
    }),
  });
  if (!response.ok) throw new Error(`AI 请求失败（${response.status}）`);
  const body = await response.json() as { choices?: Array<{ message?: { content?: string } }> };
  const content = body.choices?.[0]?.message?.content;
  if (!content) throw new Error("AI 没有返回内容");
  return PlanDraftSchema.parse(JSON.parse(content));
}

export async function createPlanDraft(profile: ProfileInput) {
  if (!config.aiApiKey) return fallback(profile);
  return callModel(profile);
}

export async function adviceFor(item: { title: string; description: string }, date: string, feedback = "") {
  const fallbackAdvice = () => ({ advice_text: `${item.title}：${item.description || "完成本事项的一个小段落并记录卡点。"}`, advice_topics: feedback ? ["根据昨日反馈复习", date] : [date] });
  if (!config.aiApiKey) return fallbackAdvice();
  try {
    const response = await fetch(`${config.aiBaseUrl}/chat/completions`, { method: "POST", headers: { "content-type": "application/json", authorization: `Bearer ${config.aiApiKey}` }, body: JSON.stringify({ model: config.aiModel, reasoning_effort: config.aiReasoningEffort, temperature: 0.2, response_format: { type: "json_object" }, messages: [{ role: "system", content: "只返回 JSON：{advice_text:string,advice_topics:string[]}" }, { role: "user", content: JSON.stringify({ item, date, feedback }) }] }) });
    if (!response.ok) throw new Error("AI advice failed");
    const body = await response.json() as { choices?: Array<{ message?: { content?: string } }> };
    const parsed = JSON.parse(body.choices?.[0]?.message?.content || "{}");
    if (typeof parsed.advice_text !== "string" || !Array.isArray(parsed.advice_topics)) throw new Error("invalid advice");
    return { advice_text: parsed.advice_text.slice(0, 4000), advice_topics: parsed.advice_topics.slice(0, 10).map(String) };
  } catch { return fallbackAdvice(); }
}
