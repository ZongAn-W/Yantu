import { type GoalType, type ProfileInput } from "./contracts.js";
import { FIRST_QUESTION, FIRST_QUESTION_OPTIONS, normalizeQuestionOptions, type OnboardingSession } from "./onboarding-contracts.js";
import { buildLearningContext, knownStudySubjects, missingLearnerFields, normalizeStudySubject, type LearnerField } from "./learning-context.js";

/** 未确认具体考试时，统一使用的澄清问题和选项；客户端会再补充唯一的“其他”入口。 */
export const EXAM_CLARIFICATION_QUESTION = "你准备参加哪一类考试？";
export const EXAM_CLARIFICATION_OPTIONS = ["硕士研究生招生考试（考研）", "公务员/事业单位", "语言考试", "职业资格", "升学/课程考试", "暂未确定"];
/** 用户选择考试类别后，继续确认具体考试名称。 */
export const EXAM_DETAIL_QUESTION = "你准备参加的具体考试是什么？";

const EXAM_CATEGORY_LABELS = ["研究生招生", "公务员/事业单位", "语言考试", "职业资格", "升学/课程考试"];
const FIRST_OPTION_GOAL_TYPES: Record<string, GoalType> = {
  考试备考: "exam",
  课程学习: "course",
  技能提升: "skill",
  自主学习: "self_study",
};
const GENERIC_EXAM_ANSWERS = new Set([
  ...FIRST_QUESTION_OPTIONS, ...EXAM_CATEGORY_LABELS,
  "考试", "备考", "考试备考", "其他", "其它", "不确定", "暂未确定", "还没确定", "暂时不确定",
]);
const ABANDON_GOAL = /不(?:再)?考(?:试|研|公|证)?了|放弃(?:考试|备考|考研|考公|考证)|不(?:想|打算)?考了|不再备考/;
const CARRY_OVER = /(?:沿用|继续|保持|还是|按照|照)(?:原来|之前|原有|现有|当前)|(?:原来|之前|原有)的?(?:目标|计划|考试|方向)/;
const REDEFINE_GOAL = /重新(?:确定|选择|开始)|换个目标|不沿用|重新规划/;
const EXAM_UNSURE = /暂未确定|不确定|还没(?:想好|确定)|没(?:想好|确定)|不知道|都可以|随便|都行|无所谓/;
const UNDECIDED = /未确定|还在|暂未|不确定|尚未|已经确定|已确定|再考虑|需要建议|之后补充|没有/;
const BARE_AFFIRMATION = /^(?:是|对|嗯|好|可以|行|没错|继续|沿用|保持|没有|不|否|暂时|暂不)[。.!！]?$/;
const NEGATIVE_ANSWER = /^(?:不是|不考|不报|不想|不再|不考虑|没有|并非|不打算|放弃|换)/;
const NEGATION_BEFORE = /(?:不是|不考|不再|不准备|不打算|不想|放弃|并非|没有|没|未|不参加|不报|不学|非)[^，,。；;！!？?]{0,6}$/;

const SUBTYPE_RULES: Array<[RegExp, string]> = [
  [/考研|研究生考试|硕士研究生|研究生招生/, "考研"],
  [/(?:报考|备考|想考|准备考|计划考).{0,40}(?:学硕|专硕)|(?:学硕|专硕).{0,20}(?:备考|考试)/, "考研"],
  [/考公|公务员|国考|省考/, "考公"],
  [/雅思|IELTS/i, "雅思"],
  [/托福|TOEFL/i, "托福"],
  [/四六级|四级|六级|CET/i, "四六级"],
  [/教资|教师资格/, "教师资格"],
  [/注会|注册会计师|CPA/i, "注册会计师"],
  [/法考|司法考试/, "法律职业资格"],
];

/** 具体到考试科目的通用词汇；只有用户本轮明确提过才允许出现在题目与选项里。 */
const EXAM_SUBJECT_TERMS = [
  "数学一", "数学二", "数学三", "英语一", "英语二", "英语三", "政治", "408",
  "199管理类联考", "396经济类联考", "法硕", "西医综合", "中医综合",
  "行测", "申论", "公共基础知识", "综合素质", "教育知识与能力", "学科知识与教学能力",
  "计算机学科专业基础", "管理类联考", "经济类联考", "高等数学", "线性代数", "概率论", "概率统计",
];

export interface InterviewEvidence {
  goalText: string;
  goalType: GoalType;
  subtype: string;
  school: string;
  program: string;
  targetDate: string | null;
  targetDateConfirmed: boolean;
  currentProgress: string;
  needsExamDetail: boolean;
  examTypeUnsure: boolean;
  redefinesGoal: boolean;
  carriesOverOldGoal: boolean;
}

export interface InterviewPrompt {
  question: string;
  question_options: string[];
  question_multiple: boolean;
  question_fields?: LearnerField[];
}

const week = (weekday: number, weekend = weekday) => Object.fromEntries(Array.from({ length: 7 }, (_, i) => [String(i), i === 0 || i === 6 ? weekend : weekday]));

export const interviewText = (session: OnboardingSession) => session.answers.map(answer => answer.answer).join("\n");

function normalizeForMatch(value: string) {
  return value.toLowerCase().replace(/[\s，,。；;：:！!？?、（）()【】\[\]“”"'‘’·\-_/]/g, "");
}

function splitClauses(text: string) {
  return text.split(/[，,。；;！!？?\n\r]+/).map(clause => clause.trim()).filter(Boolean);
}

function subtypeHit(clause: string): { label: string; index: number } | null {
  let best: { label: string; index: number } | null = null;
  for (const [pattern, label] of SUBTYPE_RULES) {
    const match = clause.match(pattern);
    if (!match || match.index === undefined) continue;
    if (!best || match.index < best.index) best = { label, index: match.index };
  }
  return best;
}

function isNegatedSubtype(clause: string, index: number) {
  return NEGATION_BEFORE.test(clause.slice(0, index));
}

/** 本轮较晚出现的明确表达优先；否定会撤销此前的同类型判断。 */
function subtypeFromAnswers(answers: OnboardingSession["answers"]) {
  let subtype = "";
  for (const { answer } of answers) {
    for (const clause of splitClauses(answer)) {
      if (REDEFINE_GOAL.test(clause) || ABANDON_GOAL.test(clause)) {
        subtype = "";
        continue;
      }
      const hit = subtypeHit(clause);
      if (!hit) continue;
      if (isNegatedSubtype(clause, hit.index)) {
        if (subtype === hit.label) subtype = "";
      } else {
        subtype = hit.label;
      }
    }
  }
  return subtype;
}

export function inferGoalSubtype(text: string) {
  for (const [pattern, label] of SUBTYPE_RULES) if (pattern.test(text)) return label;
  return "";
}

export function inferGoalType(text: string, subtype = ""): GoalType {
  if (subtype) return "exam";
  const trimmed = text.trim();
  if (FIRST_OPTION_GOAL_TYPES[trimmed]) return FIRST_OPTION_GOAL_TYPES[trimmed];
  if (/考试|备考|证书|资格|分数线|复试|真题|模拟卷|报名|雅思|托福|CATTI|GRE|GMAT|考(?:研|公|证|试)|考\s*[A-Za-z]|准备考|打算考|报考|考取/i.test(text)) return "exam";
  if (/学期|选修|必修|期末|课程|上课|学分|课件|老师讲/.test(text)) return "course";
  if (/学习|学会|掌握|入门|零基础|练习|实操|项目|编程|数据分析|设计|写作|口语|提升|提高/.test(text)) return "skill";
  if (/阅读|读书|看书|专题|兴趣|长期|每天读|没有(?:固定)?(?:截止|结束)日期/.test(text)) return "self_study";
  return "other";
}

function goalTypeForAnswer(answer: string): GoalType {
  const text = answer.trim();
  if (!text) return "other";
  if (FIRST_OPTION_GOAL_TYPES[text]) return FIRST_OPTION_GOAL_TYPES[text];
  if (isExamCategoryAnswer(text)) return "exam";
  if (SUBTYPE_RULES.some(([pattern]) => pattern.test(text))) return "exam";
  return inferGoalType(text);
}

/** 明确的完整日期；只有年份或月份时保持未知。 */
export function explicitDate(text: string) {
  const matches = [...text.matchAll(/(20\d{2})[-年/.](\d{1,2})[-月/.](\d{1,2})(?:日|号)?/g)];
  const match = matches.at(-1);
  if (!match) return "";
  const date = `${match[1]}-${match[2].padStart(2, "0")}-${match[3].padStart(2, "0")}`;
  return CalendarDateSchemaLike(date) ? date : "";
}

function CalendarDateSchemaLike(date: string) {
  const value = new Date(`${date}T00:00:00Z`);
  return Number.isFinite(value.getTime()) && value.toISOString().slice(0, 10) === date;
}

export function explicitNoDeadline(text: string) {
  return /没有(?:固定|明确)?的?(?:截止|结束|目标)日期|不设(?:截止|目标)日期|暂不(?:设置|确定)(?:目标|截止)|取消(?:目标)?日期|不再设置日期|没有deadline|长期学习/.test(text);
}

export function latestDateIntent(session: OnboardingSession):
  | { date: string }
  | { cleared: true }
  | null {
  for (let index = session.answers.length - 1; index >= 0; index--) {
    const text = session.answers[index].answer;
    if (explicitNoDeadline(text)) return { cleared: true };
    const date = explicitDate(text);
    if (date) return { date };
  }
  return null;
}

export function hasExplicitTime(session: OnboardingSession) {
  return session.answers.some(({ question, answer }) => /(?:每天|每日|工作日|周末|周[一二三四五六日天]|每周).*(?:\d+(?:\.\d+)?\s*(?:小时|分钟)|休息|不学习)/.test(answer)
    || /学习.*时间|投入多久|可用时间|哪些天/.test(question) && /\d+(?:\.\d+)?\s*(?:小时|分钟)/.test(answer));
}

function duration(text: string) {
  const match = text.match(/(\d+(?:\.\d+)?)\s*(小时|分钟)/);
  return match ? Math.max(0, Math.min(480, Math.round(Number(match[1]) * (match[2] === "小时" ? 60 : 1)))) : undefined;
}

function weeklyFromLastAnswer(session: OnboardingSession) {
  const last = session.answers.at(-1);
  const weekly: Record<string, number> = {};
  if (!last) return weekly;
  const minutes = duration(last.answer);
  if (minutes !== undefined && /每天|每日/.test(last.answer)) Object.assign(weekly, week(minutes));
  else if (minutes !== undefined && /时间|多久|哪些天/.test(last.question) && !/工作日|周末/.test(last.answer)) Object.assign(weekly, week(minutes));
  const weekdays = last.answer.match(/工作日[^，,；;\n]*?(\d+(?:\.\d+)?\s*(?:小时|分钟))/)?.[1];
  const weekends = last.answer.match(/周末[^，,；;\n]*?(\d+(?:\.\d+)?\s*(?:小时|分钟))/)?.[1];
  if (weekdays) for (let i = 1; i <= 5; i++) weekly[String(i)] = duration(weekdays)!;
  if (weekends) for (const i of [0, 6]) weekly[String(i)] = duration(weekends)!;
  if (/周末(?:休息|不学习)/.test(last.answer)) for (const i of [0, 6]) weekly[String(i)] = 0;
  const days: Record<string, number> = { 日: 0, 天: 0, 一: 1, 二: 2, 三: 3, 四: 4, 五: 5, 六: 6 };
  for (const clause of last.answer.split(/[，,；;\n]/)) {
    const value = /休息|不学习/.test(clause) ? 0 : duration(clause);
    if (value === undefined) continue;
    const range = clause.match(/(?:周|星期)([一二三四五六日天])(?:到|至|-)(?:周|星期)?([一二三四五六日天])/);
    const selected = range ? Array.from({ length: ((days[range[2]] - days[range[1]] + 7) % 7) + 1 }, (_, i) => (days[range[1]] + i) % 7)
      : [...clause.matchAll(/(?:周|星期)([一二三四五六日天])/g)].map(match => days[match[1]]);
    for (const day of selected) weekly[String(day)] = value;
  }
  return weekly;
}

function isExamCategoryAnswer(answer: string) {
  return EXAM_CATEGORY_LABELS.some(label => normalizeForMatch(label) === normalizeForMatch(answer));
}

function isGenericExamAnswer(answer: string) {
  const text = answer.trim();
  return !text || GENERIC_EXAM_ANSWERS.has(text) || EXAM_UNSURE.test(text) || /^(?:考试|科目|方向|专业)$/.test(text);
}

function isSpecificExamName(text: string) {
  const value = text.trim();
  if (value.length < 2 || value.length > 50) return false;
  if (isGenericExamAnswer(value)) return false;
  if (/大学|学院|中学|小学/.test(value)) return false;
  if (/学习|复习|每天|小时|分钟|基础|进度|目标分数|考试日期/.test(value)) return false;
  return /[\p{Script=Han}A-Za-z]/u.test(value);
}

function cleanExamName(text: string) {
  let name = text.trim()
    .replace(/[。.!！?？]+$/g, "")
    .trim();
  const verb = name.match(/(?:准备|打算|计划|想要|想|要|报名参加|报名|参加|报考|考取|考)\s*([\p{Script=Han}A-Za-z0-9][^，,。；;！!？?\n]{1,40})$/u);
  if (verb) name = verb[1];
  name = name.replace(/^(?:参加|报考|考取|考)\s*/u, "").trim();
  if (!name || isGenericExamAnswer(name) || !isSpecificExamName(name)) return "";
  return name.slice(0, 200);
}

/** 从本轮用户回答里提取用户自己填写的考试名称（支持预设枚举之外的任意名称）。 */
function selfReportedExamName(session: OnboardingSession) {
  const last = session.answers.at(-1);
  if (!last) return "";
  const answer = last.answer.trim();
  const context = /哪一类考试|具体.*考试|什么考试|哪一项考试|考试名称/.test(last.question)
    || session.answers.length === 1 && last.question === FIRST_QUESTION;
  if (!context || !isSpecificExamName(answer)) return "";
  const clause = [...splitClauses(answer)].reverse()
    .find(item => !/^(?:不是|不考|不再|不准备|不打算|不想|放弃|并非|没有)/.test(item) && isSpecificExamName(item))
    ?? answer;
  return cleanExamName(clause);
}

function oldPlanProfile(session: OnboardingSession): Partial<ProfileInput> {
  const plan = session.current_plan;
  if (!plan || typeof plan !== "object") return {};
  const profile = (plan as { profile?: unknown }).profile;
  if (!profile || typeof profile !== "object") return {};
  const row = profile as Record<string, unknown>;
  const result: Partial<ProfileInput> = {};
  if (typeof row.goal_type === "string" && ["exam", "course", "skill", "self_study", "other"].includes(row.goal_type)) {
    result.goal_type = row.goal_type as GoalType;
  }
  for (const field of ["goal_text", "goal_subtype", "target_school", "target_program"] as const) {
    if (typeof row[field] === "string") result[field] = row[field] as string;
  }
  return result;
}

/** 用户是否在本轮明确确认沿用原计划目标；之后新的目标表达会撤销沿用。 */
function carriesOverOldPlan(answers: OnboardingSession["answers"]) {
  for (let index = answers.length - 1; index >= 0; index--) {
    const text = answers[index].answer;
    if (REDEFINE_GOAL.test(text) || ABANDON_GOAL.test(text)) return false;
    if (CARRY_OVER.test(text)) return true;
    if (subtypeHit(text)) return false;
    const type = goalTypeForAnswer(text);
    if (type !== "other" && !BARE_AFFIRMATION.test(text.trim())) return false;
  }
  return false;
}

/** 把访谈历史归纳成“本轮有依据的信息”，而不是信任 AI 或旧计划写下的字段。 */
export function analyzeInterview(session: OnboardingSession): InterviewEvidence {
  const answers = session.answers;
  const answerText = interviewText(session);
  const goalAnswers = answers.filter(answer => answer.question === FIRST_QUESTION);
  let goalText = (goalAnswers.at(-1)?.answer ?? "").trim();
  let goalType: GoalType = "other";
  for (const { question, answer } of answers) {
    const type = goalTypeForAnswer(answer);
    // 只有目标语境下的回答才改判目标类型；“零基础”这类基础题回答不能把考试目标改成技能提升。
    const goalContext = question === FIRST_QUESTION
      || /哪一类考试|具体.*考试|学习什么|重新确定.*目标/.test(question)
      || /改为|改成|转(?:为|向|考)|换成|不是|不考|放弃|重新/.test(answer);
    if (type !== "other" && goalContext) goalType = type;
    else if (ABANDON_GOAL.test(answer) || REDEFINE_GOAL.test(answer)) goalType = "other";
  }
  let subtype = subtypeFromAnswers(answers);
  const last = answers.at(-1);
  const lastAnswer = last?.answer.trim() ?? "";
  const examTypeUnsure = goalType === "exam" && !subtype && EXAM_UNSURE.test(lastAnswer);
  const categoryAnswer = isExamCategoryAnswer(lastAnswer);
  let needsExamDetail = false;
  if (goalType === "exam" && !subtype) {
    if (categoryAnswer) {
      // 类别（如“研究生招生”）仍不是具体考试：goal_subtype 保持为空，继续确认具体考试。
      needsExamDetail = true;
    } else if (!examTypeUnsure) {
      subtype = selfReportedExamName(session);
    }
  }
  const positiveClauses = answers.flatMap(answer => splitClauses(answer.answer)).filter(clause => !NEGATIVE_ANSWER.test(clause));
  const schoolMatches = [...positiveClauses.join("\n").matchAll(/[\p{Script=Han}]{2,12}(?:大学|学院)/gu)];
  let school = schoolMatches.at(-1)?.[0] ?? "";
  let program = "";
  let currentProgress = "";
  for (const { question, answer } of answers) {
    const value = answer.trim();
    if (!value || NEGATIVE_ANSWER.test(value) || UNDECIDED.test(value) || BARE_AFFIRMATION.test(value)) continue;
    if (/院校|学校|单位/.test(question)) school = value.slice(0, 200);
    if (/专业|方向|岗位/.test(question) && !/^(?:考)?\s*408\s*$/.test(value) && !/大[一二三四]|小时|分钟|基础|学完/.test(value)) program = value.slice(0, 200);
    if (/基础|进度|准备情况|水平/.test(question)) currentProgress = value;
  }
  const intent = latestDateIntent(session);
  const learning = buildLearningContext(session);
  school = learning.facts.school?.value || "";
  program = learning.facts.program?.value || "";
  currentProgress = learning.facts.baseline?.value || currentProgress;
  const targetDate = intent && "date" in intent ? intent.date : null;
  const targetDateConfirmed = Boolean(targetDate) && /已确认|已确定|准确|确定是/.test(answerText);
  const carriesOverOldGoal = carriesOverOldPlan(answers);
  if (carriesOverOldGoal) {
    const old = oldPlanProfile(session);
    if (goalType === "other" && old.goal_type) goalType = old.goal_type;
    if (!subtype && old.goal_subtype) subtype = old.goal_subtype;
    if (!school && old.target_school) school = old.target_school;
    if (!program && old.target_program) program = old.target_program;
    if (!goalText && old.goal_text) goalText = old.goal_text.trim().slice(0, 2000);
    if (subtype) needsExamDetail = false;
  }
  // 非考试目标不保留考试名称，避免技能/课程目标带上无依据的考试属性。
  if (goalType !== "exam") {
    subtype = "";
    needsExamDetail = false;
  }
  return {
    goalText, goalType, subtype, school, program, targetDate, targetDateConfirmed, currentProgress,
    needsExamDetail, examTypeUnsure, redefinesGoal: REDEFINE_GOAL.test(lastAnswer), carriesOverOldGoal,
  };
}

function isGrounded(value: string, session: OnboardingSession) {
  const normalized = normalizeForMatch(value);
  return Boolean(normalized) && session.answers.some(answer => normalizeForMatch(answer.answer).includes(normalized));
}

function mentionNegated(value: string, session: OnboardingSession) {
  const normalized = normalizeForMatch(value);
  for (let index = session.answers.length - 1; index >= 0; index--) {
    const clauses = splitClauses(session.answers[index].answer);
    for (let clauseIndex = clauses.length - 1; clauseIndex >= 0; clauseIndex--) {
      const clause = clauses[clauseIndex];
      if (!normalizeForMatch(clause).includes(normalized)) continue;
      const hit = subtypeHit(clause);
      if (hit && hit.label === value) return isNegatedSubtype(clause, hit.index);
      const at = clause.indexOf(value);
      return at >= 0 ? NEGATION_BEFORE.test(clause.slice(0, at)) : false;
    }
  }
  return false;
}

function isGroundedMention(value: string, session: OnboardingSession) {
  return isGrounded(value, session) && !mentionNegated(value, session);
}

/** 由本轮回答推导资料；candidate 只会补充有依据的字段，不能覆盖用户明确表达。 */
export function deriveInterviewProfile(
  session: OnboardingSession,
  evidence: InterviewEvidence = analyzeInterview(session),
  candidate?: ProfileInput,
): ProfileInput {
  if (!session.answers.length) return structuredClone(session.profile);
  const profile = structuredClone(session.profile);
  profile.goal_text = evidence.goalText.slice(0, 2000);
  profile.goal_type = evidence.goalType;
  profile.goal_subtype = evidence.subtype;
  profile.target_school = evidence.school;
  profile.target_program = evidence.program;
  profile.target_date = evidence.targetDate;
  profile.target_date_confirmed = evidence.targetDateConfirmed;
  profile.current_progress = evidence.currentProgress;
  // 旧资料里的补充说明同样不能夹带无依据的考试类型、科目、分数或日期。
  if (profile.constraints_text && findUngroundedMentions([profile.constraints_text], session, evidence).length) {
    profile.constraints_text = "";
  }
  if (hasExplicitTime(session)) profile.weekly_minutes = { ...profile.weekly_minutes, ...weeklyFromLastAnswer(session) };
  if (candidate) {
    if (!profile.goal_subtype && profile.goal_type === "exam" && candidate.goal_subtype && isGroundedMention(candidate.goal_subtype, session)) {
      profile.goal_subtype = candidate.goal_subtype;
    }
    if (!profile.target_school && candidate.target_school && isGroundedMention(candidate.target_school, session)) {
      profile.target_school = candidate.target_school;
    }
    if (!profile.target_program && candidate.target_program && isGroundedMention(candidate.target_program, session)) {
      profile.target_program = candidate.target_program;
    }
    for (const field of ["current_progress", "constraints_text"] as const) {
      const value = candidate[field];
      if (value && findUngroundedMentions([value], session, evidence).length === 0) profile[field] = value;
    }
  }
  return profile;
}

function scoreNumbers(text: string) {
  return [...new Set([...text.matchAll(/(\d{1,4})\s*分/g)].map(match => match[1]))];
}

function dateMentions(text: string) {
  return [...new Set([...text.matchAll(/20\d{2}(?:[-/年.]\d{1,2})?(?:[-/月.]\d{1,2}日?)?/g)].map(match => match[0]))];
}

/** 找出题目/选项/资料字段里没有本轮用户依据的考试类型、科目、分数、日期和旧计划信息。 */
export function findUngroundedMentions(
  texts: readonly string[],
  session: OnboardingSession,
  evidence: InterviewEvidence = analyzeInterview(session),
): string[] {
  const joined = texts.join("\n");
  if (!joined.trim()) return [];
  const issues = new Set<string>();
  for (const [pattern, label] of SUBTYPE_RULES) {
    if (pattern.test(joined) && evidence.subtype !== label) issues.add(`考试类型「${label}」`);
  }
  for (const term of EXAM_SUBJECT_TERMS) {
    if (!joined.includes(term)) continue;
    const verified = knownStudySubjects(session).some(subject => normalizeForMatch(subject) === normalizeForMatch(normalizeStudySubject(term)));
    const askingChoice = /是否|还是|哪些|哪一|选择/.test(texts[0] ?? "") && /科目|英语|数学/.test(texts[0] ?? "");
    if (verified || askingChoice || isGroundedMention(term, session) || normalizeForMatch(evidence.subtype).includes(normalizeForMatch(term))) continue;
    issues.add(`考试科目「${term}」`);
  }
  for (const number of scoreNumbers(joined)) {
    if (session.answers.some(answer => answer.answer.includes(`${number}分`))) continue;
    issues.add(`分数「${number}」`);
  }
  for (const date of dateMentions(joined)) {
    const digits = date.replace(/\D/g, "");
    const grounded = session.answers.some(answer => answer.answer.replace(/\D/g, "").includes(digits));
    if (!grounded) issues.add(`日期「${date}」`);
  }
  const old = oldPlanProfile(session);
  for (const token of [old.goal_subtype, old.target_school, old.target_program]) {
    if (typeof token !== "string" || token.trim().length < 2 || !joined.includes(token)) continue;
    if (isGroundedMention(token, session) || token === evidence.subtype || token === evidence.school || token === evidence.program) continue;
    issues.add(`旧计划信息「${token}」`);
  }
  return [...issues];
}

function firstQuestionPrompt(): InterviewPrompt {
  return { question: FIRST_QUESTION, question_options: normalizeQuestionOptions(FIRST_QUESTION_OPTIONS), question_multiple: false };
}

function carryOverPrompt(): InterviewPrompt {
  return { question: "你希望沿用原来的学习目标，还是重新确定本次目标？", question_options: ["沿用原来的目标", "重新确定目标"], question_multiple: false };
}

/** 无 AI 时使用的安全模板；AI 生成的题目缺少依据时也退回这里。 */
export function buildSafeInterview(session: OnboardingSession, evidence: InterviewEvidence = analyzeInterview(session)): InterviewPrompt {
  if (!session.answers.length) {
    return session.has_plan || session.current_plan ? carryOverPrompt() : firstQuestionPrompt();
  }
  if (evidence.redefinesGoal) return firstQuestionPrompt();
  const subtype = evidence.subtype;
  const isExam = evidence.goalType === "exam";
  const quoted = subtype && subtype.length <= 20 ? `「${subtype}」` : "这次考试";
  if (isExam && !subtype) {
    // 用户已给出考试类别时直接确认具体考试；否则先澄清考试类型。
    if (evidence.needsExamDetail) return { question: EXAM_DETAIL_QUESTION, question_options: [], question_multiple: false };
    if (!evidence.examTypeUnsure) {
      return session.answers.some(answer => answer.question === EXAM_CLARIFICATION_QUESTION)
        ? { question: EXAM_DETAIL_QUESTION, question_options: [], question_multiple: false }
        : { question: EXAM_CLARIFICATION_QUESTION, question_options: [...EXAM_CLARIFICATION_OPTIONS], question_multiple: false };
    }
  }
  const context = buildLearningContext(session);
  const subjects = knownStudySubjects(session);
  const missing = missingLearnerFields({ ...session, learning_context: context });
  const prompt = (field: LearnerField, question: string, options: string[] = [], multiple = false): InterviewPrompt => ({ question: `${isExam ? `关于${quoted}，` : ""}${question}`, question_options: options.slice(0, 8), question_multiple: multiple, question_fields: [field] });
  const field = missing[0];
  if (field === "identity") return prompt(field, "你目前是大几，还是已经毕业或在职？", ["本科大一", "本科大二", "本科大三", "本科大四", "研究生在读", "已毕业，正在备考", "在职学习"]);
  if (field === "exam_year") return prompt(field, "你准备哪一年参加初试？尚未确定的话，也可以先安排近期学习。");
  if (field === "school") return { ...prompt(field, "你想报考哪所院校、什么专业？也可以一起说明学硕或专硕，未确定的先留空。"), question_fields: ["school", "program", "degree"] };
  if (field === "program") return prompt(field, `${context.subjects.some(subject => subject.name === "408") ? "已记下专业课408。" : ""}目标专业或方向是什么？这将用于核对对应招生要求。`);
  if (field === "degree") return prompt(field, "你准备报考学硕还是专硕？", ["学硕", "专硕", "暂未确定"]);
  if (field === "college") return prompt(field, "官方目录中有不同科目要求，你打算报考哪个学院？尚未确定也可以先说明。");
  if (field === "baseline") return prompt(field, `${subjects.length ? `目前已知的学习内容是${subjects.join("、")}。` : ""}各科学到哪一步了？可以按“科目：已学内容、做题情况”简要填写。`);
  if (field === "weakness") return prompt(field, "目前哪一科最薄弱？主要是还没学、理解困难、做不出题，还是速度慢？", subjects.length ? [...subjects.slice(0, 6), "暂时没有明显薄弱项"] : []);
  if (field === "diagnostic") return prompt(field, `你提到${context.subjects.find(subject => subject.weakness)?.name ?? "有薄弱科目"}需要加强，最近做题具体是什么情况？没有测过也可以说明。`, ["知识点还没学", "看得懂但做不出题", "做题正确率低", "做得太慢", "还没做过测验"]);
  if (field === "outcome") return prompt(field, "你希望达到什么结果？可以描述目标分数、学习成果，或先完成的阶段目标。", ["先补齐薄弱基础", "完成一轮系统学习", "提高做题正确率和速度", "达到目标院校或考试要求", "已有具体目标，自己填写"]);
  if (field === "availability") return prompt(field, "你每周哪些天可以学习，每天大约能投入多久？", ["每天1小时", "每天2小时", "每天3小时", "工作日1小时，周末3小时", "工作日2小时，周末4小时"]);
  if (field === "materials") return prompt(field, "你正在用哪些资料？可以填写教材、网课或题库名称及已完成的部分。");
  if (field === "constraints") return prompt(field, "有什么固定安排或学习习惯会影响本期学习？", ["工作日较忙", "周末休息不学习", "有固定课程或工作", "需要定期复习", "暂时没有额外限制"], true);
  return prompt("baseline", `${subjects[0] ? `接下来细化${subjects[0]}：` : "接下来细化学习内容："}近期最想先完成哪一部分，或者有哪些题目还做不出来？`);
}

/**
 * 修正历史污染：只保留有依据的资料字段；旧草稿里带无依据考试信息的待答题会退回安全模板。
 * revision 与 answers 原样保留，客户端刷新后即可看到纠正后的问题。
 */
export function sanitizeInterviewSession(session: OnboardingSession): OnboardingSession {
  if (session.stage === "complete") return session;
  // 旧版本的“信息已记录”暂停阶段已经取消：恢复时直接回到访谈，继续显示下一题和生成入口。
  const stage: OnboardingSession["stage"] = session.stage === "checkpoint" ? "interview" : session.stage;
  const next: OnboardingSession = { ...session, stage, question_options: normalizeQuestionOptions(session.question_options), learning_context: buildLearningContext(session) };
  if (!session.answers.length) return next;
  const evidence = analyzeInterview(session);
  next.profile = deriveInterviewProfile(session, evidence);
  if (stage === "interview") {
    const needsClarification = evidence.goalType === "exam" && !evidence.subtype && !evidence.examTypeUnsure;
    const needsDetail = evidence.goalType === "exam" && evidence.needsExamDetail;
    const unsafe = needsClarification || needsDetail
      || findUngroundedMentions([session.question, ...next.question_options], session, evidence).length > 0;
    if (unsafe) {
      const safe = buildSafeInterview(session, evidence);
      next.question = safe.question;
      next.question_options = safe.question_options;
      next.question_multiple = safe.question_multiple;
      next.question_fields = safe.question_fields ?? [];
    }
  }
  return next;
}
