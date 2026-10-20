import { z } from "zod";
import { AI_REQUEST_TIMEOUT_MS, AIResponseFormatError, requestStructuredAI as model } from "./ai-json.js";
import { compactPlanContext } from "./onboarding-plan-context.js";
import { attachExamResearch } from "./exam-research.js";
import { buildLearningContext, isNonAnswer, knownStudySubjects, LEARNER_FIELDS, LearnerUpdateSchema, SubjectUpdateSchema, missingLearnerFields, questionFields } from "./learning-context.js";
import { config } from "./config.js";
import { estimatedExamDate } from "./exam-dates.js";
import { ProfileSchema, type GoalType } from "./contracts.js";
import { PlanPlanningSchema } from "./planning-contracts.js";
import { newPlanning, PLANNING_PROMPT_VERSION, PLANNING_RULES_VERSION, effectivePlanMode, inclusiveDaySpan, summarizePlanCapacity } from "./planning-service.js";
import { ItemsSchema, QuestionOptionsSchema, QuestionTypeSchema, RecommendationsSchema, normalizeQuestionOptions, normalizeQuestionPresentation, type OnboardingRecommendations, type OnboardingSession, validateReferences } from "./onboarding-contracts.js";
import {
  analyzeInterview, asksForExamIdentity, buildSafeInterview, deriveInterviewProfile, findUngroundedMentions,
  hasExplicitTime, interviewText, latestDateIntent,
} from "./onboarding-evidence.js";

export { explicitDate, explicitNoDeadline, inferGoalSubtype, inferGoalType, interviewText, latestDateIntent } from "./onboarding-evidence.js";

export function shanghaiDate() {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Shanghai" }).format(new Date());
}

function addDays(date: string, days: number) {
  const value = new Date(`${date}T00:00:00Z`);
  value.setUTCDate(value.getUTCDate() + days);
  return value.toISOString().slice(0, 10);
}

/** 规划周期默认跨度：从今天起 28 个自然日（首尾均计入），只在没有目标日期和初试年份时使用。 */
const DEFAULT_PLAN_DAYS = 28;
/** 单次规划周期硬上限：从今天起 1095 个自然日（首尾均计入），与 prepareSchedule 的三年校验一致。 */
const MAX_PLAN_DAYS = 1095;
const DEFAULT_PLAN_REASON = "本次规划周期默认为从今天开始的未来28个自然日，首尾均计入，可以随时调整。";

interface PlanHorizon {
  planEndDate: string;
  reason: string;
  /** true 表示结束日期来自目标日期或预计初试日；此时必须覆盖 AI 给出的“默认四周”。 */
  preferred: boolean;
}

/**
 * 规划结束日期的优先级：
 * 1) 未来目标日期的前一天；
 * 2) 没有目标日期但已知初试年份（考研）时，12 月倒数第二个周六估算的初试日前一天；
 * 3) 以上都没有时保持从今天起 28 个自然日的默认周期。
 * 目标日期不在未来时退回默认周期；任何情况下跨度不超过 1095 天，超出则截到上限并说明。
 */
function planHorizon(today: string, targetDate: string, examYear: number | null): PlanHorizon {
  const fallback: PlanHorizon = { planEndDate: addDays(today, DEFAULT_PLAN_DAYS - 1), reason: DEFAULT_PLAN_REASON, preferred: false };
  const cap = addDays(today, MAX_PLAN_DAYS - 1);
  if (targetDate && targetDate > today) {
    const desired = addDays(targetDate, -1);
    if (desired > cap) {
      return { planEndDate: cap, preferred: true,
        reason: `目标日期 ${targetDate} 超过三年上限，先排到上限（${cap}），到期后再续排。` };
    }
    return { planEndDate: desired, reason: `本次排程到目标日期前一天（${desired}）。`, preferred: true };
  }
  // 目标日期为空或已过去时，只有初试年份可供估算；估算日前一天同样不能超过上限。
  if (!targetDate && examYear) {
    const examDate = estimatedExamDate(examYear);
    if (examDate > today) {
      const desired = addDays(examDate, -1);
      if (desired > cap) {
        return { planEndDate: cap, preferred: true,
          reason: `按往年规律估算的 ${examYear} 年初试日 ${examDate}（12月倒数第二个周六）超过三年上限，先排到上限（${cap}），到期后再续排；这是估算，请以官方通知为准，可随时调整。` };
      }
      return { planEndDate: desired, preferred: true,
        reason: `暂未设置准确考试日期；按往年规律估算 ${examYear} 年初试日为 ${examDate}（12月倒数第二个周六），本次排程到其前一天（${desired}）。这是按往年规律的估算，请以官方通知为准，可随时调整。` };
    }
  }
  return fallback;
}

const week = (weekday: number, weekend = weekday) => Object.fromEntries(Array.from({ length: 7 }, (_, i) => [String(i), i === 0 || i === 6 ? weekend : weekday]));

/** 无 AI 时使用的推荐值：目标日期未知就保持未知，规划周期始终是有限区间。 */
function fallbackRecommendations(session: OnboardingSession): OnboardingRecommendations {
  const today = shanghaiDate();
  const text = interviewText(session);
  // 只认最新一次明确的日期意图：先给日期、后来取消，就不再恢复旧日期。
  const intent = latestDateIntent(session);
  const profileDate = session.profile.target_date ?? "";
  let targetDate = "";
  // 已明确但可能已过去的目标日期：只用于判断能否按初试年份估算，不写回推荐值。
  let knownTargetDate = "";
  let targetReason = "";
  let estimated = true;
  if (intent && "cleared" in intent) {
    targetDate = "";
    targetReason = "你选择了暂不设置目标日期，本次只安排有限规划周期。";
  } else if (intent && "date" in intent) {
    targetDate = knownTargetDate = intent.date;
    targetReason = "使用你在访谈中提供的日期；这是你的目标日期，正式通知以考试或课程公告为准。";
    estimated = !/已确认|已确定|准确/.test(text);
  } else if (profileDate && profileDate >= today) {
    targetDate = knownTargetDate = profileDate;
    targetReason = session.profile.target_date_confirmed ? "使用你已确认的目标日期。" : "使用你已明确的目标日期；以正式通知为准。";
    estimated = !session.profile.target_date_confirmed;
  } else {
    targetDate = "";
    knownTargetDate = profileDate;
    targetReason = "尚未确定目标日期，先安排一段有限规划周期；你也可以稍后在设置中补充。";
  }
  const examYear = session.profile.goal_type === "exam" ? session.learning_context?.timing?.exam_year ?? null : null;
  const horizon = planHorizon(today, knownTargetDate, examYear);

  let weekday = 120, weekend = 180;
  let timeReason = "根据当前目标，先以工作日2小时、周末3小时作为可调整的学习预算。";
  if (/在职|上班|全职工作/.test(text)) {
    weekday = 60; weekend = 180; timeReason = "考虑在职安排，建议工作日1小时、周末3小时。";
  } else if (/脱产|全职备考|毕业待业/.test(text)) {
    weekday = 300; weekend = 300; timeReason = "考虑全职学习，建议每天5小时，并按精力调整休息日。";
  } else if (/在校|大学生|大[一二三四]|学生/.test(text)) {
    weekday = 180; weekend = 240; timeReason = "考虑在校课程，建议工作日3小时、周末4小时。";
  }
  if (/零基础|刚开始|尚未开始|没开始/.test(text) && weekday < 300) {
    weekday = Math.max(60, weekday - 30); timeReason += "目前刚起步，工作日先降低半小时，建立稳定节奏。";
  }
  const explicitTime = hasExplicitTime(session);
  return RecommendationsSchema.parse({
    target_date: targetDate, target_date_reason: targetReason, target_date_estimated: estimated,
    plan_end_date: horizon.planEndDate, plan_end_date_reason: horizon.reason,
    weekly_minutes: explicitTime
      ? { ...week(0), ...Object.fromEntries(Object.entries(session.profile.weekly_minutes).map(([day, minutes]) => [day, Math.min(480, minutes)])) }
      : week(weekday, weekend),
    weekly_minutes_reason: explicitTime ? "沿用你已提供的每日可用时间；0分钟表示休息。" : timeReason,
  });
}

const recommendationInstructions = [
  'recommendations 对象包含 target_date(用户目标日期 YYYY-MM-DD，没有就是空字符串)、target_date_reason(中文理由)、target_date_estimated(布尔，预计为 true)、plan_end_date(本次规划周期结束日期)、plan_end_date_reason(中文理由)、weekly_minutes(完整0到6数字典，每天0到480整数分钟，0表示休息)、weekly_minutes_reason(中文理由)。',
  '目标日期是用户希望达成结果的日期，可以为空；plan_end_date 是本次排程的有限区间边界，必须填写且不早于今天。用户选择“没有截止日期”时 target_date 必须为空，不能替其编造日期。',
  '日期规则：plan_end_date 优先取用户目标日期的前一天；用户没有目标日期但初试年份已知（learning_context.timing.exam_year，仅考研）时，取该年12月倒数第二个周六作为预计初试日，plan_end_date 取其前一天，并在理由中说明这是按往年规律估算、以官方通知为准、可调整；两者都没有时才使用从今天起的28个自然日。任何情况下 plan_end_date 不得超过今天起1094天，超出时先排到上限并说明到期后再续排。',
  '不要凭空给考试指定准确日期，也不得声称日期来自官方通知；target_date 只有用户明确提供的日期才可直接采用，其余情况保持为空并说明。plan_end_date 可以按上面的日期规则估算初试日，但理由必须说明这是估算。',
  '每周可用时间要覆盖完整一周，尊重休息日。用户只说每天几小时时可平均分配，但必须保留用户明确填写的值。',
].join("\n");

function normalizeRecommendations(session: OnboardingSession, value: OnboardingRecommendations | undefined) {
  const today = shanghaiDate();
  const fallback = fallbackRecommendations(session);
  if (!value) return fallback;
  const result = { ...fallback, ...value };
  // 用户明确取消目标日期后，推荐值也不能再带回早先的日期。
  const intent = latestDateIntent(session);
  if (intent && "cleared" in intent) {
    result.target_date = "";
    result.target_date_estimated = true;
    result.target_date_reason = "你选择了暂不设置目标日期，本次只安排有限规划周期。";
  } else if (session.profile.target_date) {
    // 用户明确填写或确认的日期优先于推荐值，AI 不能覆盖。
    result.target_date = session.profile.target_date;
    result.target_date_estimated = !session.profile.target_date_confirmed;
    result.target_date_reason = session.profile.target_date_confirmed
      ? "使用你已确认的目标日期。"
      : "使用你已明确的目标日期；以正式通知为准。";
  }
  if (!result.target_date) result.target_date_estimated = true;
  // 用户未提供或确认日期时，AI 给出的日期只能作为建议，不能标成已确认信息。
  else if (!session.profile.target_date) result.target_date_estimated = true;
  if (result.target_date && result.target_date < today) {
    // 目标日期已过去时保留实际状态，不用未来日期覆盖。
    result.target_date_reason = result.target_date_reason || "目标日期已经过去，请确认是否调整。";
  }
  // 目标日期或初试年份已知时，本期必须一次排到考试前，不能保留 AI 给出的“默认四周”。
  const examYear = session.profile.goal_type === "exam" ? session.learning_context?.timing?.exam_year ?? null : null;
  const horizon = planHorizon(today, result.target_date, examYear);
  const cap = addDays(today, MAX_PLAN_DAYS - 1);
  if (horizon.preferred) {
    result.plan_end_date = horizon.planEndDate;
    result.plan_end_date_reason = horizon.reason;
  } else if (!result.plan_end_date || result.plan_end_date < today) {
    result.plan_end_date = fallback.plan_end_date;
    result.plan_end_date_reason = fallback.plan_end_date_reason;
  } else if (result.plan_end_date > cap) {
    // AI 也可能给出超过三年的结束日期；推荐值同样受硬上限约束。
    result.plan_end_date = cap;
    result.plan_end_date_reason = `目标超过三年上限，先排到上限（${cap}），到期后再续排。${result.plan_end_date_reason}`.slice(0, 1000);
  }
  if (!Object.keys(result.weekly_minutes).length || hasExplicitTime(session)) {
    result.weekly_minutes = fallback.weekly_minutes;
    result.weekly_minutes_reason = fallback.weekly_minutes_reason;
  }
  return RecommendationsSchema.parse(result);
}

export async function recommendSchedule(session: OnboardingSession) {
  const prepared = { ...session, profile: deriveInterviewProfile(session) };
  if (!config.aiApiKey) return fallbackRecommendations(prepared);
  const result = await model(z.object({ recommendations: RecommendationsSchema }), recommendationInstructions
    + '\n只返回 {"recommendations":完整推荐对象}，不要继续提问。',
  { answers: prepared.answers, profile: prepared.profile, learning_context: buildLearningContext(session), research: session.research, recommendations: prepared.recommendations,
    current_plan: compactPlanContext(session, "recommendations"), current_date: shanghaiDate() },
  { reasoningEffort: config.aiSimpleReasoningEffort, label: "recommendations" });
  return normalizeRecommendations(prepared, result.recommendations);
}

/**
 * 模型偶尔会把可选提取数组写成对象，或塞进不合规的条目（线上实际样本：
 * learner_updates 里出现 goal_text/goal_type/goal_subtype 等资料字段名）。
 * 这些数组只是辅助抽取结果，丢掉单条仍可继续；不能因为一条坏数据让整轮访谈降级成模板。
 */
function tolerantArray<T extends z.ZodTypeAny>(item: T, max: number, label: string) {
  return z.preprocess(value => {
    if (value === null || value === undefined) return [];
    if (!Array.isArray(value)) return [];
    const kept = value.filter(entry => item.safeParse(entry).success).slice(0, max);
    if (kept.length !== value.length) {
      const fields = value.filter(entry => !item.safeParse(entry).success).slice(0, 20)
        .map(entry => entry && typeof entry === "object" ? (entry as { field?: unknown }).field ?? (entry as { name?: unknown }).name ?? null : null);
      console.error(JSON.stringify({ event: "ai_updates_dropped", label, dropped: value.length - kept.length, fields }));
    }
    return kept;
  }, z.array(item).max(max));
}

export async function nextInterview(session: OnboardingSession) {
  session = { ...session, learning_context: buildLearningContext(session) };
  const evidence = analyzeInterview(session);
  const fallbackProfile = deriveInterviewProfile(session, evidence);
  session = await attachExamResearch({ ...session, profile: fallbackProfile });
  const safeFallback = buildSafeInterview(session, evidence);
  const fallback = { ...safeFallback, ...normalizeQuestionPresentation(safeFallback) };
  const contextResult = { learning_context: session.learning_context, research: session.research };
  // 没有本轮回答时（例如从已有计划恢复访谈），先确认是否沿用原目标，不调用 AI。
  if (!session.answers.length) {
    return { ...fallback, ...contextResult, profile: fallbackProfile, recommendations: fallbackRecommendations({ ...session, profile: fallbackProfile }) };
  }
  if (!config.aiApiKey && evidence.goalType === "exam" && !evidence.subtype && !evidence.examTypeUnsure) {
    return { ...fallback, ...contextResult, profile: fallbackProfile, recommendations: fallbackRecommendations({ ...session, profile: fallbackProfile }) };
  }
  if (config.aiApiKey) {
    // 模型偶尔会把可选字段写成 null；先归一化为缺省值，避免整条结构化响应被判格式错误。
    const optionalArray = <T extends z.ZodTypeAny>(inner: T) => z.preprocess(value => (value === null || value === undefined ? [] : value), inner);
    const schema = z.object({
      question: z.string().trim().min(1).max(1000), profile: ProfileSchema,
      question_type: z.preprocess(value => (value === null ? undefined : value), QuestionTypeSchema.optional()),
      question_options: optionalArray(QuestionOptionsSchema.default([])),
      question_multiple: z.preprocess(value => (value === null ? false : value), z.boolean().default(false)),
      recommendations: z.preprocess(value => (value === null ? undefined : value), RecommendationsSchema.optional()),
      question_fields: tolerantArray(z.enum(LEARNER_FIELDS), 4, "question_fields"),
      learner_updates: tolerantArray(LearnerUpdateSchema, 30, "learner_updates"),
      subject_updates: tolerantArray(SubjectUpdateSchema, 30, "subject_updates"),
    });
    let result: z.infer<typeof schema>;
    try {
      result = await model(schema, [
      '返回 {"question":"下一道问题","question_type":"text或single_choice或multiple_choice","question_options":[],"question_multiple":false,"profile":完整资料对象,"recommendations":完整推荐对象}。一次只提一道问题。读取全部历史，根据学习目标和最新回答选择最值得补充的信息，不重复已明确的信息。',
      '用户最新消息如果不是对当前问题的回答，而是提问、闲聊或质疑（例如问“你是什么 AI”），先用一句话礼貌回应，再把同一个问题重新问一次或提出更合适的一问；不要把这类消息当作学习资料写进 learner_updates/subject_updates。',
      'answers 是本轮用户唯一明确提供的信息；current_plan 只是历史计划背景、进度和已有事项，不能把其中的旧目标、考试类型、院校、专业或科目当作本轮已确认信息。',
      '先更新学习者情况，再决定最值得问的问题。返回learner_updates:[{field,value,answer_index,quote}]，answer_index从0计，quote必须逐字引用对应用户回答；一段回答可补全多个field。value 一律用字符串（年份、分数、分钟数也写成字符串，例如 "2027"），answer_index 用整数。field仅限identity,school,college,program,degree,exam_year,baseline,weakness,diagnostic,outcome,availability,materials,constraints；learner_updates 里不要出现 goal_text、goal_type、goal_subtype 等资料字段名，这些信息只写在 profile 里。diagnostic是薄弱项的实际做题表现或测评依据。模型记忆、旧计划或网页内容不能放入learner_updates。',
      '同时返回subject_updates:[{name,progress,weakness,answer_index,quote}]记录每门学科的情况，支持任意学科名称。name、progress、weakness、quote都必须来自同一用户回答的原文，没有的信息用空字符串。不要把目标分数当作当前水平，不要把官方考试要求当作用户自述。',
      'question_fields标记这一问获取的字段。从missing_fields选择对课程或安排最有影响的一项；已知、已推算、已暂缓的信息跳过，避免同义重复提问。研究生招生/研究生考试/考研归一理解，不层层重复确认名称。',
      '公开事实交给research查询，用户只提供定位目标所需的院校/专业/学位。不要让用户解释408包含什么、官网考试要求或自行查英语几。research中reference_only=false的事实经后台核对原文，可以用于提问和课程依据；往年或待核实资料不能作为当年定论。',
      '重点了解年级或在职情况、各科实际进度、薄弱项及具体表现、目标、时间约束。年级已推算年份后不重复问考试时间。“学了一部分”应结合具体科目与做题表现追问，不逐字段盘问。408是科目代码，不是报考专业。',
      '如果用户只说“考试备考”而没有说出具体考试，profile.goal_type 填 exam，goal_subtype 必须留空；下一题先询问考试名称或类别，可让用户直接填写具体考试，也可以用类别选项，不要提前询问科目、分数、院校或日期。',
      '只有用户本轮明确说出具体考试名称时才填写 goal_subtype；用户明确说“沿用原目标”并确认后，才可以沿用 current_plan 里的目标。用户最新表达优先，如“不是考研，我准备雅思”应更新为雅思，中途改变目标时清空不再有效的旧信息。',
      '已确认考研时不能编造数学一、英语一、408、政治或固定分数。科目可使用用户提供或research已核实的依据。询问待选可能与断言已确定事实要区分。用户目标来自用户，公开考试要求来自有出处的资料。',
      '第一问之后的重点顺序：具体考试与考试目标/范围 → 当前基础与进度 → 目标日期是否存在及其明确程度 → 一周可用时间与不能学习的日期 → 必学内容、资料、练习方式和其它约束。',
      '由你逐题决定最方便用户表达的回答方式，不默认把问题做成选择题，也不固定按字段决定形式。question_type=text时question_options必须为空且question_multiple=false，界面直接显示文本框；适合描述个人进度、具体卡点、材料名称、学习成果、院校专业、数字或不规则时间安排时优先文字填写，不让用户先点“其他”才能描述。',
      '答案是少量明确、易理解的互斥类别时可用single_choice；确实需要同时选择多项时用multiple_choice并设置question_multiple=true。有意义的选项通常2到6项，最多8项，每项不超过200字；信息不适合穷举或选项不能表达关键细节时选择text。界面自动提供“其他”文字输入，不要在选项里重复添加“其他”。不要为了提供选项而替用户概括、遗漏或猜测个人情况。',
      '资料字段：goal_text 是用户实际描述的学习目标；goal_type 只能是 exam(考试备考)、course(课程学习)、skill(技能提升)、self_study(自主学习)、other 之一；goal_subtype 是具体考试或领域名称，可为空；target_date 只能填用户明确提供的完整日期 YYYY-MM-DD，未知或主动不设为 null，禁止把推荐日期写入资料；target_date_confirmed 表示用户是否明确确认该日期；target_school、target_program、current_progress、constraints_text 为字符串；weekly_minutes 为0(周日)到6(周六)的每日分钟数字典，只保存用户明确的可用时间。推荐内容只能作为建议，target_date_estimated=true，不能写成用户已确认的信息。',
      '院校、专业、考试科目、目标分数只在考试场景且相关时询问；课程学习、技能提升和自主学习不得要求院校或初试安排。没有目标日期是合法回答，后续问题不能反复要求考试时间。',
      '如果用户只说“提升英语”，继续了解具体学习目的，不要直接推断成雅思或托福。',
      '保留已有信息，仅依据用户回答更新。不要生成课程或计划。',
      '如果有current_plan，只结合现有课程、事项、完成进度和固定安排了解历史背景，询问变化或尚未明确的信息；不要复述旧目标为已确认信息。',
      '推荐对象中的 plan_end_date 遵守统一日期规则：有未来目标日期时取其前一天；没有目标日期但考研初试年份已知时，按12月倒数第二个周六估算初试日并取其前一天（说明这是估算、以官方通知为准）；两者都没有才用28天默认；任何情况下不超过今天起1094天。',
      recommendationInstructions,
    ].join("\n"), { answers: session.answers, profile: session.profile, learning_context: session.learning_context, missing_fields: missingLearnerFields(session), research: session.research, recommendations: session.recommendations,
      current_plan: compactPlanContext(session, "interview"), current_date: shanghaiDate() },
    { reasoningEffort: config.aiSimpleReasoningEffort, label: "interview" });
    } catch (error) {
      if (!(error instanceof z.ZodError) && !(error instanceof AIResponseFormatError)) throw error;
      // 模型结构化输出仍有无法归一的偏差，或返回的 JSON 被截断时退回安全模板：访谈继续推进，
      // 而不是把整轮进度卡在错误提示上。ai-json.ts 已把 issues/原始输出写入服务端日志。
      return { ...fallback, ...contextResult, profile: fallbackProfile, recommendations: fallbackRecommendations({ ...session, profile: fallbackProfile }) };
    }
    const presentation = normalizeQuestionPresentation(result);
    const options = presentation.question_options;
    session = { ...session, learning_context: buildLearningContext(session, result.learner_updates, new Date(), result.subject_updates) };
    const profile = deriveInterviewProfile(session, analyzeInterview(session), result.profile);
    session = await attachExamResearch({ ...session, profile });
    if (!hasExplicitTime(session)) profile.weekly_minutes = session.profile.weekly_minutes;
    else if (/每天|每日|工作日|周末|(?:周|星期)[一二三四五六日天]/.test(session.answers.at(-1)?.answer ?? "")) profile.weekly_minutes = fallbackProfile.weekly_minutes;
    const recommendations = normalizeRecommendations({ ...session, profile }, result.recommendations);
    const needsExamClarification = evidence.goalType === "exam" && !evidence.subtype && !evidence.examTypeUnsure;
    const asksExam = asksForExamIdentity(result.question);
    if ((needsExamClarification || evidence.needsExamDetail) && !asksExam) {
      const safe = buildSafeInterview(session, analyzeInterview(session));
      return { ...safe, ...normalizeQuestionPresentation(safe), learning_context: session.learning_context, research: session.research, profile, recommendations };
    }
    // 无依据的考试类型、科目、分数、日期或旧计划信息不能直接落库，退回安全模板继续澄清。
    if (findUngroundedMentions([result.question, ...options], session, evidence).length) {
      const safe = buildSafeInterview(session, analyzeInterview(session));
      return { ...safe, ...normalizeQuestionPresentation(safe), learning_context: session.learning_context, research: session.research, profile, recommendations };
    }
    const fields = result.question_fields.length ? result.question_fields : questionFields(result.question);
    const available = missingLearnerFields(session);
    // 用户发来的是提问/闲聊时，AI 用一句话回应后重新追问上一题是合理的，不能按“字段已问过”退回模板。
    const reasksAfterNonAnswer = fields.length > 0 && isNonAnswer(session.answers.at(-1)?.answer ?? "");
    const repeatsExam = Boolean(evidence.subtype) && /哪(?:一)?类.*考试|具体.*考试(?:是|叫)|考试(?:名称|类型|类别)|参加什么考试/.test(result.question);
    if (repeatsExam || (!reasksAfterNonAnswer && fields.length && !fields.some(field => available.includes(field))) || /408.*(?:包含|包括|组成|有什么)|你.*(?:查阅|查询|查一下).*(?:官网|招生|科目)/.test(result.question)) {
      const safe = buildSafeInterview(session, analyzeInterview(session));
      return { ...safe, ...normalizeQuestionPresentation(safe), learning_context: session.learning_context, research: session.research, profile, recommendations };
    }
    const { learner_updates: _updates, subject_updates: _subjects, ...response } = result;
    return { ...response, ...presentation, learning_context: session.learning_context, research: session.research, question_fields: fields, profile, recommendations };
  }
  return { ...fallback, ...contextResult, profile: fallbackProfile, recommendations: fallbackRecommendations({ ...session, profile: fallbackProfile }) };
}

const notes = { summary: z.string().max(4000), assumptions: z.array(z.string().max(500)).max(20), warnings: z.array(z.string().max(500)).max(20) };
const itemSchema = z.object({ items: ItemsSchema, planning: PlanPlanningSchema.optional(), ...notes });

function fallbackItemTitles(goalType: GoalType) {
  switch (goalType) {
    case "exam": return ["基础学习", "专项练习与复盘"];
    case "course": return ["课程内容梳理", "练习与复习"];
    case "skill": return ["基础练习", "动手实践"];
    case "self_study": return ["阅读与记录", "专题整理"];
    default: return ["学习推进", "复习与整理"];
  }
}

export async function generateItems(session: OnboardingSession, instruction = "", timeout = AI_REQUEST_TIMEOUT_MS) {
  if (config.aiApiKey) {
    const planMode = effectivePlanMode(session.planning);
    const horizonDays = planMode === "full" && session.start_date && session.end_date
      ? inclusiveDaySpan(session.start_date, session.end_date)
      : Math.max(1, Math.min(1095, session.planning?.detail_days ?? 14));
    const capacity = session.start_date && session.end_date
      ? summarizePlanCapacity(session.profile, session.start_date, session.end_date) : null;
    const horizonInstruction = planMode === "full"
      ? `本次为全周期一次性生成：planning.mode="full"，rolling=false，detail_days=${horizonDays}，从 plan_start_date 到 plan_end_date 首尾完整覆盖，不按14天窗口分段，也不要求模型逐日输出时间块（程序会按结构化策略展开每日安排）。`
      : `本次为旧版滚动计划：planning.mode="rolling"，rolling=true，detail_days=${horizonDays}，仅细化近期窗口，其余周期用于预测。`;
    const capacityInstruction = capacity
      ? `容量假设：口径=${capacity.basis}；每周采用${capacity.adopted_weekly_minutes ?? "默认模板"}分钟${capacity.weekly_range_minutes ? `（用户给出范围${capacity.weekly_range_minutes.min}–${capacity.weekly_range_minutes.max}分钟，仅说明较高容量情景）` : ""}；共${capacity.weeks.length}个自然周（其中${capacity.estimated_weeks}周为程序建议分配）。时间不足时明确列出范围缺口与取舍，不得篡改真实截止日期或压缩单价。`
      : "";
    const result = await model(itemSchema, [
      '直接生成可执行事项，不要求先创建课程。返回 {"items":[{"id":"item-1","tag_names":["可选标签名"],"title":"可执行标题","description":"学习范围","completion_criteria":"可验证标准","estimated_minutes":600,"earliest_date":"YYYY-MM-DD","deadline":"YYYY-MM-DD","deadline_kind":"deadline","priority":2}],"summary":"依据","assumptions":[],"warnings":[]}。tag_names可以省略或为空；只写标签名称，不得编造数据库ID。',
      "id唯一，priority为整数1到3，estimated_minutes为30到100000的整数分钟；最多500项。title最长200字，description最长4000字，completion_criteria最长1000字。",
      "deadline_kind 为 deadline 表示真实截止日期：可以等于、早于或晚于本期结束日期，本次只安排与规划区间相交的部分；为 plan_end 表示本期安排边界，随规划周期延展。没有真实截止日期的事项使用 plan_end，禁止给所有事项设置遥远日期。",
      "事项标题要能落到具体学习行动，避免“全面掌握”“系统提升”等空泛表述；练习、复习和实践按场景决定，不给所有目标套同一种阶段。",
      "日期不得早于今天且开始不得晚于截止。本次规划周期为 plan_start_date 到 plan_end_date；目标日期是 target_date，可以为空，且不等于规划结束日期。真实截止日期可以晚于 plan_end_date，不要为了塞进本期而缩短它。",
      "全周期覆盖要求：每一项学习内容都必须有明确去向——正式安排、明确在本期范围外、用户确认的备选，或量化的容量缺口（写入 planning.uncovered / risks）。未知材料或速度用明确估算、可信度和少量诊断事项表达，仍一次生成完整计划，不要求先完成诊断才生成远期安排。",
      "有修改要求时以当前手动编辑后的事项为基础，只做用户要求的修改，保留未修改事项的id。",
      "有current_plan时，继续同一学习事项应复用原id，estimated_minutes为包含已完成用时的总预算；固定事项必须原样保留。不要恢复status为archived的事项，除非用户明确要求。",
      "current_plan 是精简的历史背景：archived_items 中的事项必须保持归档，除非用户明确要求恢复；recent_execution 是近期记录的汇总，不替代完整计时样本。",
      `规划版本为 ${PLANNING_PROMPT_VERSION} / ${PLANNING_RULES_VERSION}。必须返回 planning:{version:1,prompt_version:"${PLANNING_PROMPT_VERSION}",rules_version:"${PLANNING_RULES_VERSION}",mode:"${planMode}",detail_days:${horizonDays},rolling:${planMode === "rolling"},route:[{id,title,start_date?,end_date?,item_ids,outcome,check}],milestones:[],assumptions:[],risks:[],uncovered:[]}。阶段根据目标选择，技能围绕成果、学习内容围绕章节，自学允许低强度，不套用考研阶段。`,
      '每个事项返回 planning:{workload:{components:[{id,label,quantity,unit,minutes_per_unit,selected:true}],source,confidence:"low"|"medium"|"high",calibration},activity:{kind:"finite"|"recurring",starts_on,ends_on,sessions_per_week?,session_minutes?,state:"active"},dependencies:[{task_id,mode:"planned"|"confirmed"}]}。数量和单价不可只写在自然语言里。组成分量相加，未选择的备选 selected:false 不计入预算；复盘与作答分开，区间可加range_min/range_max，说明所采用值是估计。',
      '有限内容 estimated_minutes 必须等于选中组成项 quantity*minutes_per_unit 向上取整的和。例如15套真题+6套模拟每套180分钟，作答就3780分钟，复盘额外计算。持续活动 workload 描述单次组成且等于session_minutes，estimated_minutes由程序按本期需求计算；不能把全年预算再按周重复计入。',
      '持续练习使用有限有效窗口、每周次数1至7、单次时长，不能先排完全部预算后消失。无真实日期不编造准确官方日期。仅引用输入中实际存在的资料，未知材料安排少量校准并声明未知；source不能声称未提供的资料已核实。',
      'workload.evidence_refs 可引用 answer:0 等实际回答下标或 research.sources 中的原网址，缺少依据则保持空数组。milestones 每项包含 title、source_kind(user|verified|suggested|unknown)、date_precision(year|month|day|unknown)、date_value、source_ref；verified必须对应非参考原文，未公布日不使用day精度。',
      '标签仅作为可选分类，不能用标签代替事项状态、日期、工作量或进度。保留用户可用时间和所有真实日期，容量不足明确取舍与未覆盖内容，禁止为了填满日历编任务或压缩单价。修订必须保留全部已确认事项ID，范围变化写入risks。',
      'current_plan.feedback_signals 分别提供实际用时、用户确认内容进度和困难。有效计时少于3次不能推断稳定速度；遇到困难应调整练习方式、范围或复习，不只是移动分钟。达到预算不表示内容完成，后续依赖需要实际内容确认。',
    ].join("\n"), {
      answers: session.answers, profile: session.profile, learning_context: session.learning_context, research: session.research, recommendations: session.recommendations,
      plan_start_date: session.start_date || shanghaiDate(),
      plan_end_date: session.end_date || session.recommendations.plan_end_date || session.profile.plan_end_date || "",
      plan_mode: planMode, plan_horizon_days: horizonDays, capacity,
      target_date: session.profile.target_date ?? "",
      items: session.items, current_plan: compactPlanContext(session, "items"),
      // Per-session planning notes stay in the user payload: in the system prompt they would make
      // the cacheable prefix different for every session. `instruction` is only set for revisions.
      planning_instructions: { horizon: horizonInstruction, capacity: capacityInstruction },
      instruction, current_date: shanghaiDate(),
    }, { timeoutMs: timeout, reasoningEffort: config.aiPlanningReasoningEffort, label: instruction ? "items-revise" : "items" });
    validateReferences(result.items);
    return { ...result, planning: result.planning ?? newPlanning() };
  }
  if (instruction) throw new Error("服务器尚未配置 AI，暂时无法对话修改，请手动编辑事项");
  const today = shanghaiDate();
  const boundary = session.end_date || session.recommendations.plan_end_date || session.profile.plan_end_date || addDays(today, 27);
  const titles = fallbackItemTitles(session.profile.goal_type);
  const topics = knownStudySubjects(session);
  const scopes = topics.length ? topics : [session.profile.goal_subtype || session.profile.goal_text.trim().slice(0, 40) || "学习内容"];
  const items = scopes.flatMap((scope, i) => titles.map((title, index) => ({
      id: `item-${i + 1}-${index + 1}`, tag_names: [scope], title,
      description: `${scope}：${title}，记录具体范围与卡点`,
      completion_criteria: index === 0 ? "完成所选材料并整理要点" : "完成练习并记录错因或改进点",
      estimated_minutes: index === 0 ? 120 : 60,
      planning: {
        workload: { components: [{ id: "calibrate", label: index === 0 ? "少量材料诊断" : "练习与复盘", quantity: 1,
          unit: "次", minutes_per_unit: index === 0 ? 120 : 60, selected: true }],
          source: "材料和速度未知，采用可调整的初始估计", confidence: "low" as const, calibration: "完成一次后记录实际内容进度和困难，再评估范围" },
        activity: { kind: "finite" as const, starts_on: session.start_date || today, ends_on: boundary, state: "active" as const },
        dependencies: [] },
      earliest_date: today, deadline: boundary, deadline_kind: "plan_end" as const,
      priority: session.learning_context.subjects.some(subject => subject.name === scope && subject.weakness) ? 3 : 2,
    })));
  return {
    items,
    summary: "根据访谈内容整理的学习事项",
    assumptions: session.profile.target_date ? [] : ["暂未设置目标日期，事项按本期安排边界推进"],
    warnings: ["服务器未配置 AI，当前为基础模板，请核对学习预算和范围"],
    planning: { ...newPlanning(), route: scopes.map((scope, index) => ({ id: `route-${index + 1}`, title: scope,
      item_ids: titles.map((_, itemIndex) => `item-${index + 1}-${itemIndex + 1}`),
      outcome: "确认材料与当前基础，完成小范围学习", check: "记录内容进展后重新评估" })),
      assumptions: ["材料和学习速度尚待校准"], uncovered: ["基础模板仅安排小范围校准，尚未覆盖完整长期目标"] },
  };
}
