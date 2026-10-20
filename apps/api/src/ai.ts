import { z } from "zod";
import { requestStructuredAI } from "./ai-json.js";
import { PlanDraftSchema, type PlanDraft, type ProfileInput } from "./contracts.js";
import { config } from "./config.js";

const priorityOutputSchema = { type: "integer", enum: [1, 2, 3] };
const idOutputSchema = { type: "string", minLength: 1, maxLength: 80 };
const dateOutputSchema = { type: "string", pattern: "^\\d{4}-\\d{2}-\\d{2}$" };
const draftOutputSchema = {
  type: "object",
  additionalProperties: false,
  required: ["items", "analysis_summary", "assumptions", "warnings"],
  properties: {
    items: {
      type: "array", minItems: 1, maxItems: 500,
      items: {
        type: "object", additionalProperties: false,
        required: ["id", "title", "description", "completion_criteria", "estimated_minutes", "deadline", "priority"],
        properties: {
          id: idOutputSchema,
          tag_names: { type: "array", maxItems: 20, items: { type: "string", minLength: 1, maxLength: 100 } },
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

const draftInstructions = [
  "只返回满足 output_schema 的 JSON 对象，不要 Markdown 或额外说明。",
  "事项的 priority 必须是 JSON 整数 1、2 或 3，分别表示低、中、高。禁止数字字符串、英文或中文等级名称。",
  "estimated_minutes 必须是 30 到 100000 之间的整数分钟，不能是字符串或小时数。assumptions 和 warnings 必须是字符串数组，没有内容时返回 []。",
  "直接生成可执行、可计时的事项，每项使用唯一的字符串 id。tag_names 是可选标签名称数组，不是必填，也不要生成任何数据库 ID。",
  "使用 YYYY-MM-DD 日期字符串，earliest_date 可以省略但不能为 null。满足 current_date <= earliest_date <= deadline。deadline_kind 为 deadline 表示真实截止日期，为 plan_end 表示本期安排边界（使用 profile.plan_end_date）。目标日期 profile.target_date 可以为空，不能把规划结束日期当作目标日期。",
  "依据 profile 和 constraints_text 生成事项数量、内容和时长；标签仅在确有分类价值时建议，example 仅展示结构与类型，不代表实际学习计划。",
].join("\n");

function addDays(date: string, amount: number) {
  const value = new Date(`${date}T00:00:00Z`);
  value.setUTCDate(value.getUTCDate() + amount);
  return value.toISOString().slice(0, 10);
}

function fallback(profile: ProfileInput): PlanDraft {
  const topic = profile.goal_subtype || profile.goal_text.trim().slice(0, 40) || "学习内容";
  const start = addDays(new Date().toISOString().slice(0, 10), 0);
  const boundary = profile.plan_end_date ?? profile.target_date ?? addDays(start, 27);
  const titles = profile.goal_type === "self_study" ? ["阅读与记录", "专题整理"]
    : profile.goal_type === "skill" ? ["基础练习", "动手实践"]
      : profile.goal_type === "course" ? ["内容梳理", "练习与复习"]
        : ["基础学习", "专项练习与复盘"];
  const items = titles.map((title, index) => (
    {
      id: `item-${index + 1}`, title,
      tag_names: index === 0 ? [] : [topic],
      description: `${topic}：${title}。当前进度：${profile.current_progress || "尚未填写"}`,
      completion_criteria: "完成一个可验证的小目标并记录卡点", estimated_minutes: 120 * 60,
      earliest_date: start, deadline: boundary, deadline_kind: "plan_end" as const, priority: index < 2 ? 3 : 2,
    }
  ));
  return PlanDraftSchema.parse({ items,
    analysis_summary: `根据学习目标「${profile.goal_text || profile.goal_subtype || "未填写"}」和当前进度生成初始学习框架。确认后还可以逐项修改。`,
    assumptions: ["每日计划会按照每周可用时间分配", "事项按本期安排边界推进，可在确认后修改"], warnings: [] });
}

async function callModel(profile: ProfileInput): Promise<PlanDraft> {
  const currentDate = new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Shanghai" }).format(new Date());
  const example: PlanDraft = {
    items: [{
      id: "item-1", title: "示例事项", tag_names: [], description: "具体学习内容",
      completion_criteria: "可以验证的完成标准", estimated_minutes: 60,
      earliest_date: currentDate, deadline: profile.plan_end_date ?? profile.target_date ?? addDays(currentDate, 27), deadline_kind: "plan_end" as const, priority: 2,
    }],
    analysis_summary: "根据备考资料说明规划依据",
    assumptions: [],
    warnings: [],
  };
  return requestStructuredAI(PlanDraftSchema, draftInstructions,
    { profile, current_date: currentDate, output_schema: draftOutputSchema, example },
    { label: "plan-draft" });
}

export async function createPlanDraft(profile: ProfileInput) {
  if (!config.aiApiKey) return fallback(profile);
  return callModel(profile);
}

const adviceSchema = z.object({ advice_text: z.string(), advice_topics: z.array(z.string()) });

export async function adviceFor(item: { title: string; description: string }, date: string, feedback = "") {
  const fallbackAdvice = () => ({ advice_text: `${item.title}：${item.description || "完成本事项的一个小段落并记录卡点。"}`, advice_topics: feedback ? ["根据昨日反馈复习", date] : [date] });
  if (!config.aiApiKey) return fallbackAdvice();
  try {
    const parsed = await requestStructuredAI(adviceSchema, "只返回 JSON：{advice_text:string,advice_topics:string[]}",
      { item, date, feedback }, { label: "advice" });
    if (typeof parsed.advice_text !== "string" || !Array.isArray(parsed.advice_topics)) throw new Error("invalid advice");
    return { advice_text: parsed.advice_text.slice(0, 4000), advice_topics: parsed.advice_topics.slice(0, 10).map(String) };
  } catch { return fallbackAdvice(); }
}
