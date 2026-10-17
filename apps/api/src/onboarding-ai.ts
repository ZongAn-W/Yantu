import { z } from "zod";
import { requestStructuredAI as model } from "./ai-json.js";
import { attachExamResearch } from "./exam-research.js";
import { buildLearningContext, knownStudySubjects, LEARNER_FIELDS, LearnerUpdateSchema, SubjectUpdateSchema, missingLearnerFields, questionFields } from "./learning-context.js";
import { config } from "./config.js";
import { ProfileSchema, type GoalType } from "./contracts.js";
import { CoursesSchema, FIRST_QUESTION, ItemsSchema, QuestionOptionsSchema, RecommendationsSchema, normalizeQuestionOptions, type OnboardingRecommendations, type OnboardingSession, validateReferences } from "./onboarding-contracts.js";
import {
  analyzeInterview, buildSafeInterview, deriveInterviewProfile, findUngroundedMentions,
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

const week = (weekday: number, weekend = weekday) => Object.fromEntries(Array.from({ length: 7 }, (_, i) => [String(i), i === 0 || i === 6 ? weekend : weekday]));

const SUBJECT_VOCAB = [
  "数据结构", "计算机网络", "操作系统", "计算机组成", "组成原理", "高等数学", "高数", "线性代数", "线代", "概率统计", "概率论",
  "数学", "英语", "政治", "物理", "化学", "生物", "历史", "地理", "语文", "管理学", "经济学", "会计", "法学", "教育学", "心理学",
  "听力", "口语", "阅读", "写作", "词汇", "语法", "翻译", "编程", "算法", "数据分析", "统计学", "设计", "产品", "运营",
];

/** 无 AI 时使用的推荐值：目标日期未知就保持未知，规划周期始终是有限区间。 */
function fallbackRecommendations(session: OnboardingSession): OnboardingRecommendations {
  const today = shanghaiDate();
  const text = interviewText(session);
  // 只认最新一次明确的日期意图：先给日期、后来取消，就不再恢复旧日期。
  const intent = latestDateIntent(session);
  const profileDate = session.profile.target_date ?? "";
  let targetDate = "";
  let targetReason = "";
  let estimated = true;
  if (intent && "cleared" in intent) {
    targetDate = "";
    targetReason = "你选择了暂不设置目标日期，本次只安排有限规划周期。";
  } else if (intent && "date" in intent) {
    targetDate = intent.date;
    targetReason = "使用你在访谈中提供的日期；这是你的目标日期，正式通知以考试或课程公告为准。";
    estimated = !/已确认|已确定|准确/.test(text);
  } else if (profileDate && profileDate >= today) {
    targetDate = profileDate;
    targetReason = session.profile.target_date_confirmed ? "使用你已确认的目标日期。" : "使用你已明确的目标日期；以正式通知为准。";
    estimated = !session.profile.target_date_confirmed;
  } else {
    targetDate = "";
    targetReason = "尚未确定目标日期，先安排一段有限规划周期；你也可以稍后在设置中补充。";
  }
  const horizon = addDays(today, 27);
  const planEnd = targetDate && targetDate > today && targetDate < horizon ? targetDate : horizon;
  const planReason = targetDate && planEnd === targetDate
    ? "目标日期在四周内，本次直接安排到目标日期。"
    : "本次规划周期默认为从今天开始的未来28个自然日，首尾均计入，可以随时调整。";

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
    plan_end_date: planEnd, plan_end_date_reason: planReason,
    weekly_minutes: explicitTime
      ? { ...week(0), ...Object.fromEntries(Object.entries(session.profile.weekly_minutes).map(([day, minutes]) => [day, Math.min(480, minutes)])) }
      : week(weekday, weekend),
    weekly_minutes_reason: explicitTime ? "沿用你已提供的每日可用时间；0分钟表示休息。" : timeReason,
  });
}

const recommendationInstructions = [
  'recommendations 对象包含 target_date(用户目标日期 YYYY-MM-DD，没有就是空字符串)、target_date_reason(中文理由)、target_date_estimated(布尔，预计为 true)、plan_end_date(本次规划周期结束日期)、plan_end_date_reason(中文理由)、weekly_minutes(完整0到6数字典，每天0到480整数分钟，0表示休息)、weekly_minutes_reason(中文理由)。',
  '目标日期是用户希望达成结果的日期，可以为空；plan_end_date 是本次排程的有限区间边界，必须填写且不早于今天。用户选择“没有截止日期”时 target_date 必须为空，不能替其编造日期。',
  '不要凭空给考试指定准确日期，也不得声称日期来自官方通知；只有用户明确提供的日期才可直接采用，其余情况保持为空并说明。',
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
  if (!result.plan_end_date || result.plan_end_date < today) {
    result.plan_end_date = fallback.plan_end_date;
    result.plan_end_date_reason = fallback.plan_end_date_reason;
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
  { current_date: shanghaiDate(), answers: prepared.answers, profile: prepared.profile, learning_context: buildLearningContext(session), research: session.research, recommendations: prepared.recommendations, current_plan: session.current_plan });
  return normalizeRecommendations(prepared, result.recommendations);
}

const GOAL_TYPE_LABELS: Record<GoalType, string> = {
  exam: "考试备考", course: "课程学习", skill: "技能提升", self_study: "自主学习", other: "其他",
};

export async function nextInterview(session: OnboardingSession) {
  session = { ...session, learning_context: buildLearningContext(session) };
  const evidence = analyzeInterview(session);
  const fallbackProfile = deriveInterviewProfile(session, evidence);
  session = await attachExamResearch({ ...session, profile: fallbackProfile });
  const fallback = buildSafeInterview(session, evidence);
  const contextResult = { learning_context: session.learning_context, research: session.research };
  // 没有本轮回答时（例如从已有计划恢复访谈），先确认是否沿用原目标，不调用 AI。
  if (!session.answers.length) {
    return { ...fallback, ...contextResult, profile: fallbackProfile, recommendations: fallbackRecommendations({ ...session, profile: fallbackProfile }) };
  }
  if (evidence.goalType === "exam" && !evidence.subtype && !evidence.examTypeUnsure) {
    return { ...fallback, ...contextResult, profile: fallbackProfile, recommendations: fallbackRecommendations({ ...session, profile: fallbackProfile }) };
  }
  if (config.aiApiKey) {
    const schema = z.object({
      question: z.string().trim().min(1).max(1000), profile: ProfileSchema,
      question_options: QuestionOptionsSchema.default([]), question_multiple: z.boolean().default(false),
      recommendations: RecommendationsSchema.optional(),
      question_fields: z.array(z.enum(LEARNER_FIELDS)).max(4).default([]),
      learner_updates: z.array(LearnerUpdateSchema).max(30).default([]),
      subject_updates: z.array(SubjectUpdateSchema).max(30).default([]),
    });
    const result = await model(schema, [
      '返回 {"question":"下一道问题","question_options":["选项"],"question_multiple":false,"profile":完整资料对象,"recommendations":完整推荐对象}。一次只提一道问题。读取全部历史，根据学习目标和最新回答选择最值得补充的信息，不重复已明确的信息。',
      'answers 是本轮用户唯一明确提供的信息；current_plan 只是历史计划背景、进度和已有事项，不能把其中的旧目标、考试类型、院校、专业或科目当作本轮已确认信息。',
      '先更新学习者情况，再决定最值得问的问题。返回learner_updates:[{field,value,answer_index,quote}]，answer_index从0计，quote必须逐字引用对应用户回答；一段回答可补全多个field。field仅限identity,school,college,program,degree,exam_year,baseline,weakness,diagnostic,outcome,availability,materials,constraints。diagnostic是薄弱项的实际做题表现或测评依据。模型记忆、旧计划或网页内容不能放入learner_updates。',
      '同时返回subject_updates:[{name,progress,weakness,answer_index,quote}]记录每门学科的情况，支持任意学科名称。name、progress、weakness、quote都必须来自同一用户回答的原文，没有的信息用空字符串。不要把目标分数当作当前水平，不要把官方考试要求当作用户自述。',
      'question_fields标记这一问获取的字段。从missing_fields选择对课程或安排最有影响的一项；已知、已推算、已暂缓的信息跳过，避免同义重复提问。研究生招生/研究生考试/考研归一理解，不层层重复确认名称。',
      '公开事实交给research查询，用户只提供定位目标所需的院校/专业/学位。不要让用户解释408包含什么、官网考试要求或自行查英语几。research中reference_only=false的事实经后台核对原文，可以用于提问和课程依据；往年或待核实资料不能作为当年定论。',
      '重点了解年级或在职情况、各科实际进度、薄弱项及具体表现、目标、时间约束。年级已推算年份后不重复问考试时间。“学了一部分”应结合具体科目与做题表现追问，不逐字段盘问。408是科目代码，不是报考专业。',
      '如果用户只说“考试备考”而没有说出具体考试，profile.goal_type 填 exam，goal_subtype 必须留空；下一题必须先问“你准备参加哪一类考试？”，选项用研究生招生、公务员/事业单位、语言考试、职业资格、升学/课程考试、暂未确定，不要询问科目、分数、院校或日期。',
      '只有用户本轮明确说出具体考试名称时才填写 goal_subtype；用户明确说“沿用原目标”并确认后，才可以沿用 current_plan 里的目标。用户最新表达优先，如“不是考研，我准备雅思”应更新为雅思，中途改变目标时清空不再有效的旧信息。',
      '已确认考研时不能编造数学一、英语一、408、政治或固定分数。科目可使用用户提供或research已核实的依据。询问待选可能与断言已确定事实要区分。用户目标来自用户，公开考试要求来自有出处的资料。',
      '第一问之后的重点顺序：具体考试与考试目标/范围 → 当前基础与进度 → 目标日期是否存在及其明确程度 → 一周可用时间与不能学习的日期 → 必学内容、资料、练习方式和其它约束。',
      '尽可能给3到6个有意义的简短选项，最多8项，每项不超过200字。适合多选时才设置question_multiple=true。界面自动提供“其他”文字输入，不要在选项里重复添加“其他”。',
      '资料字段：goal_text 是用户实际描述的学习目标；goal_type 只能是 exam(考试备考)、course(课程学习)、skill(技能提升)、self_study(自主学习)、other 之一；goal_subtype 是具体考试或领域名称，可为空；target_date 只能填用户明确提供的完整日期 YYYY-MM-DD，未知或主动不设为 null，禁止把推荐日期写入资料；target_date_confirmed 表示用户是否明确确认该日期；target_school、target_program、current_progress、constraints_text 为字符串；weekly_minutes 为0(周日)到6(周六)的每日分钟数字典，只保存用户明确的可用时间。推荐内容只能作为建议，target_date_estimated=true，不能写成用户已确认的信息。',
      '院校、专业、考试科目、目标分数只在考试场景且相关时询问；课程学习、技能提升和自主学习不得要求院校或初试安排。没有目标日期是合法回答，后续问题不能反复要求考试时间。',
      '如果用户只说“提升英语”，继续了解具体学习目的，不要直接推断成雅思或托福。',
      '保留已有信息，仅依据用户回答更新。不要生成课程或计划。',
      '如果有current_plan，只结合现有课程、事项、完成进度和固定安排了解历史背景，询问变化或尚未明确的信息；不要复述旧目标为已确认信息。',
      recommendationInstructions,
    ].join("\n"), { current_date: shanghaiDate(), answers: session.answers, profile: session.profile, learning_context: session.learning_context, missing_fields: missingLearnerFields(session), research: session.research, recommendations: session.recommendations, current_plan: session.current_plan });
    const options = normalizeQuestionOptions(result.question_options);
    session = { ...session, learning_context: buildLearningContext(session, result.learner_updates, new Date(), result.subject_updates) };
    const profile = deriveInterviewProfile(session, analyzeInterview(session), result.profile);
    session = await attachExamResearch({ ...session, profile });
    if (!hasExplicitTime(session)) profile.weekly_minutes = session.profile.weekly_minutes;
    else if (/每天|每日|工作日|周末|(?:周|星期)[一二三四五六日天]/.test(session.answers.at(-1)?.answer ?? "")) profile.weekly_minutes = fallbackProfile.weekly_minutes;
    const recommendations = normalizeRecommendations({ ...session, profile }, result.recommendations);
    const needsExamClarification = evidence.goalType === "exam" && !evidence.subtype && !evidence.examTypeUnsure;
    if (needsExamClarification || evidence.needsExamDetail) {
      return { ...buildSafeInterview(session, analyzeInterview(session)), learning_context: session.learning_context, research: session.research, profile, recommendations };
    }
    // 无依据的考试类型、科目、分数、日期或旧计划信息不能直接落库，退回安全模板继续澄清。
    if (findUngroundedMentions([result.question, ...options], session, evidence).length) {
      return { ...buildSafeInterview(session, analyzeInterview(session)), learning_context: session.learning_context, research: session.research, profile, recommendations };
    }
    const fields = result.question_fields.length ? result.question_fields : questionFields(result.question);
    const available = missingLearnerFields(session);
    const repeatsExam = Boolean(evidence.subtype) && /哪(?:一)?类.*考试|具体.*考试(?:是|叫)|考试(?:名称|类型|类别)|参加什么考试/.test(result.question);
    if (repeatsExam || fields.length && !fields.some(field => available.includes(field)) || /408.*(?:包含|包括|组成|有什么)|你.*(?:查阅|查询|查一下).*(?:官网|招生|科目)/.test(result.question)) {
      return { ...buildSafeInterview(session, analyzeInterview(session)), learning_context: session.learning_context, research: session.research, profile, recommendations };
    }
    const { learner_updates: _updates, subject_updates: _subjects, ...response } = result;
    return { ...response, learning_context: session.learning_context, research: session.research, question_fields: fields, question_options: options, profile, recommendations };
  }
  return { ...fallback, ...contextResult, profile: fallbackProfile, recommendations: fallbackRecommendations({ ...session, profile: fallbackProfile }) };
}

const notes = { summary: z.string().max(4000), assumptions: z.array(z.string().max(500)).max(20), warnings: z.array(z.string().max(500)).max(20) };
const courseSchema = z.object({ courses: CoursesSchema, ...notes });
const itemSchema = z.object({ items: ItemsSchema, ...notes });

function recognizedSubjects(text: string) {
  return [...new Set(SUBJECT_VOCAB.filter(name => text.includes(name)))].slice(0, 8);
}

function fallbackCourseNames(session: OnboardingSession) {
  const subjects = knownStudySubjects(session);
  if (session.profile.goal_type === "exam" && subjects.length) return subjects;
  const text = interviewText(session) || session.profile.goal_text;
  // 优先按学习目标本身确定领域，避免被后续补充信息里的偶然名词带偏。
  const goalText =
    session.answers.filter(answer => answer.question === FIRST_QUESTION).at(-1)?.answer ?? session.profile.goal_text;
  const fromGoal = recognizedSubjects(goalText);
  const known = fromGoal.length ? fromGoal : recognizedSubjects(text);
  // 技能类目标保留基础、练习、实践的结构，不停留在单个名词上。
  if (known.length && session.profile.goal_type === "skill") {
    const domain = known[0];
    return [`${domain}基础`, `${domain}练习`, `${domain}实践`];
  }
  // 自主学习按主题组织，不使用空泛的“提高”类命名。
  if (known.length && session.profile.goal_type === "self_study") {
    const topic = known[0];
    return [`${topic}阅读与记录`, `${topic}专题整理`];
  }
  if (known.length) return known;
  const goal = session.profile.goal_text.trim();
  switch (session.profile.goal_type) {
    case "exam": return [session.profile.goal_subtype ? `${session.profile.goal_subtype}备考` : (goal.slice(0, 20) || "考试科目")];
    case "course": return [goal.slice(0, 40) || "课程内容"];
    case "skill": return ["基础入门", "动手练习", "综合实践"];
    case "self_study": return ["阅读材料", "专题整理"];
    default: return [goal.slice(0, 40) || "学习内容"];
  }
}

export async function generateCourses(session: OnboardingSession, instruction = "") {
  session = await attachExamResearch(session);
  if (config.aiApiKey) {
    const result = await model(courseSchema, [
      '只生成课程，不生成事项。返回 {"courses":[{"id":"course-1","name":"课程名","description":"说明","priority":2}],"summary":"依据","assumptions":[],"warnings":[]}。',
      "根据实际学习目标生成课程或学习领域：考试目标按实际考试科目生成，不能默认所有考试都有数学或政治；语言学习结合听说读写和薄弱项；编程学习可包含基础、数据处理、练习和实践；阅读学习按主题或书目组织；课程学习按用户提供的课程范围组织。",
      "priority 为整数1到3，id唯一；最多100门课程。name最长100字，description最长1000字。课程数量和优先级要与用户可用时间和实际目标相称。",
      "有修改要求时以当前手动编辑后的课程为基础，只做用户要求的修改，保留未修改课程的id。不要臆造考试科目，未明确的科目在assumptions中说明。",
      "有current_plan时参考现有课程和进度；继续同一内容应复用原id，保留固定事项所属课程。",
      '依据learning_context中的年级、各科学情、薄弱项和目标设置课程与优先级。research中reference_only=false的事实可确定公开课程范围；待核实或往年资料列入assumptions。408已核实为四门内容时可分别生成课程，仍保持课程→事项两层，不擅自确定尚未核实的英语一/二等要求。',
    ].join("\n"), { answers: session.answers, profile: session.profile, learning_context: session.learning_context, research: session.research, courses: session.courses, current_plan: session.current_plan, instruction });
    validateReferences(result.courses, []);
    if (session.profile.goal_type === "exam") {
      const unverified = findUngroundedMentions(result.courses.flatMap(course => [course.name, course.description]), session);
      if (unverified.length) {
        result.assumptions = [`科目要求待核实：${unverified.join("、")}`.slice(0, 500), ...result.assumptions].slice(0, 20);
        result.warnings = ["部分科目尚未取得当前报考目标的核实依据，请在确认课程前核对；这些课程仍是可修改的草案。", ...result.warnings].slice(0, 20);
      }
    }
    return result;
  }
  if (instruction) throw new Error("服务器尚未配置 AI，暂时无法对话修改，请手动编辑课程");
  const names = fallbackCourseNames(session);
  return {
    courses: names.map((name, i) => ({ id: `course-${i + 1}`, name, description: "", priority: session.learning_context.subjects.some(subject => subject.weakness && (name.includes(subject.name) || subject.name.includes(name))) ? 3 : 2 })),
    summary: `根据「${GOAL_TYPE_LABELS[session.profile.goal_type] ?? "其他"}」目标整理的基础课程草案，可手动修改`,
    assumptions: ["具体学习范围需要结合你的资料和进度核对"],
    warnings: ["服务器未配置 AI，当前为基础模板，请确认并修改课程"],
  };
}

function fallbackItemTitles(goalType: GoalType) {
  switch (goalType) {
    case "exam": return ["基础学习", "专项练习与复盘"];
    case "course": return ["课程内容梳理", "练习与复习"];
    case "skill": return ["基础练习", "动手实践"];
    case "self_study": return ["阅读与记录", "专题整理"];
    default: return ["学习推进", "复习与整理"];
  }
}

export async function generateItems(session: OnboardingSession, instruction = "") {
  if (config.aiApiKey) {
    const result = await model(itemSchema, [
      '只为已确认的课程生成事项，不得增加或改变课程。返回 {"items":[{"id":"item-1","course_id":"已确认课程id","title":"可执行标题","description":"学习范围","completion_criteria":"可验证标准","estimated_minutes":600,"earliest_date":"YYYY-MM-DD","deadline":"YYYY-MM-DD","deadline_kind":"deadline","priority":2}],"summary":"依据","assumptions":[],"warnings":[]}。',
      "id唯一，priority为整数1到3，estimated_minutes为30到100000的整数分钟；最多500项。title最长200字，description最长4000字，completion_criteria最长1000字。",
      "deadline_kind 为 deadline 表示真实截止日期：可以等于、早于或晚于本期结束日期，本次只安排与规划区间相交的部分；为 plan_end 表示本期安排边界，随规划周期延展。没有真实截止日期的事项使用 plan_end，禁止给所有事项设置遥远日期。",
      "事项标题要能落到具体学习行动，避免“全面掌握”“系统提升”等空泛表述；练习、复习和实践按场景决定，不给所有目标套同一种阶段。",
      "日期不得早于今天且开始不得晚于截止。本次规划周期为 plan_start_date 到 plan_end_date；目标日期是 target_date，可以为空，且不等于规划结束日期。真实截止日期可以晚于 plan_end_date，不要为了塞进本期而缩短它。",
      "有修改要求时以当前手动编辑后的事项为基础，只做用户要求的修改，保留未修改事项的id。",
      "有current_plan时，继续同一学习事项应复用原id，estimated_minutes为包含已完成用时的总预算；固定事项必须原样保留。不要恢复status为archived的事项，除非用户明确要求。",
    ].join("\n"), {
      current_date: shanghaiDate(), answers: session.answers, profile: session.profile, learning_context: session.learning_context, research: session.research, recommendations: session.recommendations,
      plan_start_date: session.start_date || shanghaiDate(),
      plan_end_date: session.end_date || session.recommendations.plan_end_date || session.profile.plan_end_date || "",
      target_date: session.profile.target_date ?? "",
      courses: session.courses, items: session.items, current_plan: session.current_plan, instruction,
    });
    validateReferences(session.courses, result.items);
    return result;
  }
  if (instruction) throw new Error("服务器尚未配置 AI，暂时无法对话修改，请手动编辑事项");
  const today = shanghaiDate();
  const boundary = session.end_date || session.recommendations.plan_end_date || session.profile.plan_end_date || addDays(today, 27);
  const titles = fallbackItemTitles(session.profile.goal_type);
  return {
    items: session.courses.flatMap((course, i) => titles.map((title, index) => ({
      id: `item-${i}-${index + 1}`, course_id: course.id, title,
      description: `${course.name}：${title}，记录具体范围与卡点`,
      completion_criteria: index === 0 ? "完成所选材料并整理要点" : "完成练习并记录错因或改进点",
      estimated_minutes: index === 0 ? 3600 : 2400,
      earliest_date: today, deadline: boundary, deadline_kind: "plan_end" as const,
      priority: course.priority,
    }))),
    summary: "按已确认课程整理的学习事项",
    assumptions: session.profile.target_date ? [] : ["暂未设置目标日期，事项按本期安排边界推进"],
    warnings: ["服务器未配置 AI，当前为基础模板，请核对学习预算和范围"],
  };
}
