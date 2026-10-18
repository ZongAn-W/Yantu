import { z } from "zod";
import type { OnboardingSession } from "./onboarding-contracts.js";

export const LEARNER_FIELDS = ["identity", "school", "college", "program", "degree", "exam_year", "baseline", "weakness", "diagnostic", "outcome", "availability", "materials", "constraints"] as const;
export type LearnerField = typeof LEARNER_FIELDS[number];
/**
 * 模型经常把年份、分数、分钟数直接输出成 JSON 数字（例如把 exam_year 的
 * value 写成 2027）。这些字段的语义是文本，先转成字符串再校验，避免整条
 * 结构化响应因为 JSON 类型写法不同被判定为“格式有误”而中断访谈。
 */
const textualValue = z.preprocess(
  value => (typeof value === "number" || typeof value === "boolean" ? String(value) : value),
  z.string().trim().min(1).max(1000),
);
export const LearnerUpdateSchema = z.object({
  field: z.enum(LEARNER_FIELDS), value: textualValue,
  answer_index: z.number().int().nonnegative(), quote: z.string().min(1).max(4000),
});
export const SubjectUpdateSchema = z.object({ name: z.string().trim().min(1).max(100), progress: z.string().max(1000).default(""), weakness: z.string().max(1000).default(""), answer_index: z.number().int().nonnegative(), quote: z.string().min(1).max(4000) });
export const LearningContextSchema = z.object({
  facts: z.record(z.object({ value: z.string(), answer_index: z.number().int(), quote: z.string() })).default({}),
  subjects: z.array(z.object({ name: z.string(), progress: z.string().default(""), weakness: z.string().default(""), answer_index: z.number().int() })).default([]),
  deferred: z.array(z.enum(LEARNER_FIELDS)).default([]),
  timing: z.object({ exam_year: z.number().int().nullable().default(null), admission_year: z.number().int().nullable().default(null), estimated: z.boolean().default(true), reason: z.string().default("") }).default({}),
}).default({});
export type LearningContext = z.infer<typeof LearningContextSchema>;

export const ResearchSchema = z.object({
  key: z.string().default(""), status: z.enum(["idle", "pending", "verified", "reference", "not_found", "error"]).default("idle"),
  message: z.string().default(""), checked_at: z.string().default(""),
  facts: z.array(z.object({ statement: z.string(), subjects: z.array(z.string()).default([]), source_url: z.string().url(), quote: z.string(), applicable_year: z.number().int().nullable(), reference_only: z.boolean().default(false) })).default([]),
  sources: z.array(z.object({ url: z.string().url(), title: z.string(), fetched_at: z.string() })).default([]),
}).default({});
export type ExamResearch = z.infer<typeof ResearchSchema>;

const SUBJECTS = ["数据结构", "计算机组成原理", "计算机组成", "操作系统", "计算机网络", "数学一", "数学二", "数学三", "英语一", "英语二", "高等数学", "高数", "线性代数", "线代", "概率论", "408", "政治", "英语", "数学", "听力", "口语", "阅读", "写作", "行测", "申论", "Python"];
const UNSURE = /暂未|尚未确定|未确定|暂不|没(?:想好|确定)|不确定|不知道|之后补充|还在比较|需要建议/;
const PROGRESS = /零基础|从零|没(?:有)?(?:学|开始)|尚未开始|学(?:完|过|了)|背完|刚开始|刷完|复习|一轮|二轮|基础|进度|刷题|做题|正确率|模考|测验|掌握|薄弱|弱|差|吃力|不会|困难|卡在|看不懂|做不出/;

export function questionFields(question: string): LearnerField[] {
  const fields: LearnerField[] = [];
  if (/年级|大几|身份|在校|毕业|在职/.test(question)) fields.push("identity");
  if (/院校|学校|单位/.test(question)) fields.push("school");
  if (/专业|方向|岗位/.test(question)) fields.push("program");
  if (/学硕|专硕|学位类型/.test(question)) fields.push("degree");
  if (/哪年|哪一年|哪一届|什么时候|目标日期|初试年份/.test(question)) fields.push("exam_year");
  if (/基础|进度|学到|水平/.test(question)) fields.push("baseline");
  if (/薄弱|最弱|吃力|卡在|困难/.test(question)) fields.push("weakness");
  if (/具体表现|最近.*做题|做题具体|正确率|模考|测验|卡在哪一步/.test(question)) fields.push("diagnostic");
  if (/目标分数|达到什么|学习成果|什么结果/.test(question)) fields.push("outcome");
  if (/多久|可用时间|哪些天|投入/.test(question)) fields.push("availability");
  if (/资料|教材/.test(question)) fields.push("materials");
  if (/限制|固定安排|偏好/.test(question)) fields.push("constraints");
  return fields;
}

export function buildLearningContext(session: OnboardingSession, updates: z.infer<typeof LearnerUpdateSchema>[] = [], today = new Date(), subjectUpdates: z.infer<typeof SubjectUpdateSchema>[] = []): LearningContext {
  // Rebuild from the answer log: old goals and previously inferred fields are never evidence.
  const context = LearningContextSchema.parse({});
  const carried = Object.entries(session.learning_context?.facts ?? {}).flatMap(([field, fact]) => LEARNER_FIELDS.includes(field as LearnerField) ? [{ field: field as LearnerField, ...fact }] : []);
  let targetReset = -1;
  const set = (field: LearnerField, value: string, index: number, quote: string) => {
    context.facts[field] = { value: value.slice(0, 1000), answer_index: index, quote };
    context.deferred = context.deferred.filter(item => item !== field);
  };
  for (const [index, { question, answer, fields: recordedFields }] of session.answers.entries()) {
    if (/不(?:再)?考研|换个目标|改(?:为|成)|重新确定目标|放弃(?:考试|考研|目标)/.test(answer)) {
      targetReset = index;
      for (const field of ["school", "college", "program", "degree", "baseline", "weakness", "diagnostic", "outcome"] as const) delete context.facts[field];
      context.subjects = [];
      context.deferred = [];
    }
    const fields = recordedFields ?? questionFields(question);
    if (UNSURE.test(answer)) context.deferred.push(...fields.filter(field => !context.deferred.includes(field)));
    const identity = answer.match(/(?:本科)?大[一二三四五六]|[一二三四五六]年级|研究生在读|硕士在读|博士在读|已毕业|毕业\d*年|在职|上班|全职工作|二战|三战/);
    if (identity) {
      const modifiers = answer.match(/四年制|五年制|应届|二战|三战|延毕|延期|提前/g) ?? [];
      set("identity", [identity[0], ...modifiers.filter(item => item !== identity[0])].join("，"), index, answer);
    }
    const school = answer.match(/(?:上海交通大学|西安交通大学|北京大学|清华大学|[\p{Script=Han}]{2,12}(?:大学|学院))/u)?.[0]?.replace(/^(?:我想考|我想报考|准备报考|想考|报考|目标是|我想去|考上)/, "");
    if (school) set("school", school, index, school);
    if (/(?:上交|上海交大)/.test(answer)) set("school", "上海交通大学", index, answer);
    const degree = answer.match(/学硕|专硕|学术(?:型|学位)|专业(?:型|学位)/)?.[0];
    const college = answer.match(/(?:计算机|电子信息|软件|人工智能|医|法|商|经济管理|机械)[\p{Script=Han}]{0,8}学院/u)?.[0];
    if (college) set("college", college, index, college);
    if (degree) set("degree", /学硕|学术/.test(degree) ? "学硕" : "专硕", index, degree);
    const program = answer.match(/计算机科学与技术|计算机技术|软件工程|人工智能|电子信息|法律硕士|金融学|工商管理|临床医学/)?.[0];
    if (program) set("program", program, index, program);
    else if (fields.includes("program") && !UNSURE.test(answer) && !/^(?:考)?\s*408\s*$/.test(answer) && !school && !identity && !PROGRESS.test(answer) && !/^已确定/.test(answer)) set("program", answer, index, answer);
    if (fields.includes("baseline") || PROGRESS.test(answer)) set("baseline", answer, index, answer);
    if (fields.includes("weakness") || /薄弱|最弱|吃力|比较差|较差|[英语数学].*差|不会|卡在|做不出/.test(answer)) set("weakness", answer, index, answer);
    if (fields.includes("diagnostic") || /模考|测验|正确率|错\s*\d+|做不出题|做题慢|做得慢|读不懂|看不懂|不会应用|来不及/.test(answer)) set("diagnostic", answer, index, answer);
    if (fields.includes("outcome") && !UNSURE.test(answer)) set("outcome", answer, index, answer);
    if (fields.includes("materials") && !UNSURE.test(answer)) set("materials", answer, index, answer);
    if (fields.includes("constraints") && !UNSURE.test(answer)) set("constraints", answer, index, answer);
    if (/(?:每天|每日|工作日|周末|每周|周[一二三四五六日天]).*(?:小时|分钟|休息|不学习)/.test(answer)) set("availability", answer, index, answer);
    for (const rawName of SUBJECTS.filter(name => answer.includes(name))) {
      const name = rawName === "高数" ? "高等数学" : rawName === "线代" ? "线性代数" : rawName;
      if (name === "数学" && /数学[一二三]/.test(answer) || name === "英语" && /英语[一二]/.test(answer) || name === "计算机组成" && answer.includes("计算机组成原理")) continue;
      const clause = answer.split(/[，,；;。\n]/).find(item => item.includes(rawName)) ?? answer;
      if (/不考|不学|放弃/.test(clause)) continue;
      const existing = context.subjects.find(subject => subject.name === name);
      const subject = { name, progress: PROGRESS.test(clause) ? clause : "", weakness: /薄弱|弱|差|吃力|不会|卡在|困难/.test(clause) ? clause : "", answer_index: index };
      if (existing && (subject.progress || subject.weakness)) Object.assign(existing, subject, { progress: subject.progress || existing.progress, weakness: subject.weakness || existing.weakness });
      else if (existing) continue;
      else context.subjects.push(subject);
    }
  }
  // Model extraction carries literal answer quotes, not model-created public facts.
  for (const update of [...carried, ...updates]) {
    if (update.answer_index < targetReset && !["identity", "availability", "constraints"].includes(update.field)) continue;
    const answer = session.answers[update.answer_index]?.answer;
    if (!answer?.includes(update.quote) || update.answer_index < (context.facts[update.field]?.answer_index ?? -1)) continue;
    if (!update.quote.includes(update.value)) {
      const identityText = (text: string) => text.replace(/([一二三四五六])年级/g, "大$1").replace(/全职工作|已工作|上班/g, "在职").replace(/[\s，,（）()]/g, "");
      const degreeText = (text: string) => text.replace(/学术(?:型|学位)/g, "学硕").replace(/专业(?:型|学位)/g, "专硕");
      const equivalentIdentity = update.field === "identity" && identityText(update.quote).includes(identityText(update.value));
      const equivalentDegree = update.field === "degree" && degreeText(update.quote).includes(degreeText(update.value));
      if (!equivalentIdentity && !equivalentDegree) continue;
    }
    if (update.field === "program" && /^\s*(?:考)?408\s*$/.test(update.value)) continue;
    set(update.field, update.value, update.answer_index, update.quote);
  }
  for (const subject of [...(session.learning_context?.subjects ?? []), ...subjectUpdates]) {
    const answer = session.answers[subject.answer_index]?.answer;
    if (!answer || subject.answer_index < targetReset || !answer.includes(subject.name)) continue;
    if ("quote" in subject && (typeof subject.quote !== "string" || !answer.includes(subject.quote))) continue;
    if (subject.progress && !answer.includes(subject.progress) || subject.weakness && !answer.includes(subject.weakness)) continue;
    const existing = context.subjects.find(item => item.name === subject.name);
    if (existing && existing.answer_index > subject.answer_index) continue;
    const value = { name: subject.name, progress: subject.progress, weakness: subject.weakness, answer_index: subject.answer_index };
    if (existing) Object.assign(existing, value);
    else context.subjects.push(value);
  }
  const year = Number(new Intl.DateTimeFormat("en", { timeZone: "Asia/Shanghai", year: "numeric" }).format(today));
  const month = Number(new Intl.DateTimeFormat("en", { timeZone: "Asia/Shanghai", month: "numeric" }).format(today));
  const graduateGoal = /考研|研究生招生|研究生考试|硕士研究生/.test(session.profile.goal_subtype || session.answers.map(item => item.answer).join(" "));
  if (!graduateGoal) return context;
  let explicitYear: number | null = null;
  for (const { question, answer } of session.answers) {
    if (!/考研|研究生|哪年|哪一届|什么时候|日期|考试|20\d{2}\s*年?(?:入学|级)/.test(question + answer)) continue;
    const admission = answer.match(/(20\d{2})\s*(?:年)?(?:入学|级)/);
    if (admission) { explicitYear = Number(admission[1]) - 1; continue; }
    const match = answer.match(/(20\d{2})\s*(?:年)?(?:的)?(?:考研|考试|初试)/) ?? (/哪年|哪一年|初试年份|考试日期/.test(question) ? answer.match(/(20\d{2})/) : null);
    if (match) explicitYear = Number(match[1]);
    else if (/明年.*(?:考研|考试)|(?:考研|考试).*明年/.test(answer)) explicitYear = year + 1;
    else if (/今年.*(?:考研|考试)|(?:考研|考试).*今年/.test(answer)) explicitYear = year;
  }
  if (explicitYear) context.timing = { exam_year: explicitYear, admission_year: explicitYear + 1, estimated: false, reason: "根据你明确提供的考试年份；具体考试日以官方公告为准。" };
  else if (/考研|研究生招生/.test(session.profile.goal_subtype || session.answers.map(item => item.answer).join(" "))) {
    const identity = context.facts.identity?.value ?? "";
    const grade = identity.match(/大([一二三四五六])/);
    const length = session.answers.some(item => /五年制/.test(item.answer)) ? 5 : 4;
    if (grade && !/二战|三战|延期|延毕|提前|不应届/.test(identity)) {
      const currentGrade = "一二三四五六".indexOf(grade[1]) + 1;
      const admissionYear = year + (month >= 8 ? 1 : 0) + length - currentGrade;
      context.timing = { exam_year: admissionYear - 1, admission_year: admissionYear, estimated: true, reason: `按${length}年制本科、当前年级及应届升学推算，可修改；不是官方考试日期。` };
    }
  }
  if (session.exam_year_override) context.timing = { exam_year: session.exam_year_override, admission_year: session.exam_year_override + 1, estimated: false, reason: "使用你手动指定的初试年份；具体考试日以官方公告为准。" };
  return context;
}

export function researchTarget(session: OnboardingSession) {
  const c = buildLearningContext(session);
  return { exam: session.profile.goal_subtype, school: c.facts.school?.value || session.profile.target_school, college: c.facts.college?.value || "", program: c.facts.program?.value || session.profile.target_program, degree: c.facts.degree?.value || "", admission_year: c.timing.admission_year, subject_codes: c.subjects.filter(subject => subject.name === "408").map(subject => subject.name) };
}

export function missingLearnerFields(session: OnboardingSession): LearnerField[] {
  const context = buildLearningContext(session);
  const attempted = session.answers.flatMap(item => item.fields ?? questionFields(item.question));
  const missing = (field: LearnerField) => !context.facts[field] && !context.deferred.includes(field) && attempted.filter(item => item === field).length < (["school", "program", "degree"].includes(field) ? 2 : 1);
  const fields: LearnerField[] = [];
  if (session.profile.goal_type === "exam" && missing("identity")) fields.push("identity");
  if (/考研/.test(session.profile.goal_subtype)) {
    if (!context.timing.exam_year && missing("exam_year")) fields.push("exam_year");
    for (const field of ["school", "program", "degree"] as const) if (missing(field)) fields.push(field);
    if (/冲突|不同科目要求/.test(session.research?.message ?? "") && missing("college")) fields.push("college");
  }
  for (const field of ["baseline", "weakness", "diagnostic", "outcome", "availability", "materials", "constraints"] as const) {
    if (field === "diagnostic") {
      const weakSubjects = context.subjects.filter(subject => subject.weakness);
      const notStarted = /零基础|尚未开始|还没开始/;
      if (!context.facts.weakness || (weakSubjects.length ? weakSubjects.every(subject => notStarted.test(subject.progress)) : notStarted.test(context.facts.baseline?.value ?? ""))) continue;
    }
    if (missing(field)) fields.push(field);
  }
  return fields;
}

export function knownStudySubjects(session: OnboardingSession): string[] {
  const context = buildLearningContext(session);
  const names = [...new Set([...context.subjects.map(subject => subject.name), ...(session.research?.facts ?? []).filter(fact => !fact.reference_only).flatMap(fact => fact.subjects)].map(normalizeStudySubject))];
  return names.filter(name => {
    if (name === "英语" && names.some(item => /^英语[一二]$/.test(item))) return false;
    if (name === "数学" && names.some(item => /^数学[一二三]$/.test(item))) return false;
    return name !== "408" || !["数据结构", "计算机组成原理", "操作系统", "计算机网络"].every(item => names.includes(item));
  });
}

export function normalizeStudySubject(name: string): string {
  return name.trim().replace(/^\d{3}\s*(?=[^\d\s])/, "").replace(/[（(]([一二三])[）)]/g, "$1").replace(/^思想政治理论$/, "政治").replace(/^计算机学科专业基础(?:综合)?$/, "408");
}
