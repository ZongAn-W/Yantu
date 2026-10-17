import { PlanDraftSchema, type PlanDraft, type ProfileInput } from "./contracts.js";
import { config } from "./config.js";

const priorityOutputSchema = { type: "integer", enum: [1, 2, 3] };
const idOutputSchema = { type: "string", minLength: 1, maxLength: 80 };
const dateOutputSchema = { type: "string", pattern: "^\\d{4}-\\d{2}-\\d{2}$" };
const draftOutputSchema = {
  type: "object",
  additionalProperties: false,
  required: ["courses", "items", "analysis_summary", "assumptions", "warnings"],
  properties: {
    courses: {
      type: "array", minItems: 1, maxItems: 100,
      items: {
        type: "object", additionalProperties: false,
        required: ["id", "name", "description", "priority"],
        properties: {
          id: idOutputSchema,
          name: { type: "string", minLength: 1, maxLength: 100 },
          description: { type: "string", maxLength: 1000 },
          priority: priorityOutputSchema,
        },
      },
    },
    items: {
      type: "array", minItems: 1, maxItems: 500,
      items: {
        type: "object", additionalProperties: false,
        required: ["id", "course_id", "title", "description", "completion_criteria", "estimated_minutes", "deadline", "priority"],
        properties: {
          id: idOutputSchema,
          course_id: idOutputSchema,
          title: { type: "string", minLength: 1, maxLength: 200 },
          description: { type: "string", maxLength: 4000 },
          completion_criteria: { type: "string", maxLength: 1000 },
          estimated_minutes: { type: "integer", minimum: 30, maximum: 100000 },
          earliest_date: dateOutputSchema,
          deadline: dateOutputSchema,
          priority: priorityOutputSchema,
        },
      },
    },
    analysis_summary: { type: "string", maxLength: 4000 },
    assumptions: { type: "array", maxItems: 20, items: { type: "string", maxLength: 500 } },
    warnings: { type: "array", maxItems: 20, items: { type: "string", maxLength: 500 } },
  },
};

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
  const currentDate = new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Shanghai" }).format(new Date());
  const example: PlanDraft = {
    courses: [{ id: "course-1", name: "示例课程", description: "课程说明", priority: 2 }],
    items: [{
      id: "item-1", course_id: "course-1", title: "示例事项", description: "具体学习内容",
      completion_criteria: "可以验证的完成标准", estimated_minutes: 60,
      earliest_date: currentDate, deadline: profile.exam_date, priority: 2,
    }],
    analysis_summary: "根据备考资料说明规划依据",
    assumptions: [],
    warnings: [],
  };
  const response = await fetch(`${config.aiBaseUrl}/chat/completions`, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${config.aiApiKey}` },
    body: JSON.stringify({
      model: config.aiModel,
      reasoning_effort: config.aiReasoningEffort,
      temperature: 0.2,
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: [
          "你是学习规划师。只返回满足 output_schema 的 JSON 对象，不要 Markdown 或额外说明。",
          "课程和事项的 priority 必须是 JSON 整数 1、2 或 3，分别表示低、中、高。禁止数字字符串、英文或中文等级名称。",
          "estimated_minutes 必须是 30 到 100000 之间的整数分钟，不能是字符串或小时数。assumptions 和 warnings 必须是字符串数组，没有内容时返回 []。",
          "课程和事项必须可执行、可计时，分别使用唯一的字符串 id；事项的 course_id 必须引用本次课程数组中的 id。",
          "使用 YYYY-MM-DD 日期字符串，earliest_date 可以省略但不能为 null。满足 current_date <= earliest_date <= deadline <= profile.exam_date。",
          "依据 profile 和 constraints_text 生成课程数量、事项数量、内容和时长；example 仅展示结构与类型，不代表实际学习计划。",
        ].join("\n") },
        { role: "user", content: JSON.stringify({ profile, current_date: currentDate, output_schema: draftOutputSchema, example }) },
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
