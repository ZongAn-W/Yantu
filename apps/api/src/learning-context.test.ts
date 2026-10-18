import { describe, expect, it, vi } from "vitest";
import { buildLearningContext, knownStudySubjects, LearnerUpdateSchema, missingLearnerFields, ResearchSchema } from "./learning-context.js";
import { FIRST_QUESTION, newSession } from "./onboarding-contracts.js";
import { analyzeInterview, buildSafeInterview } from "./onboarding-evidence.js";
import { advanceOnboarding } from "./onboarding.js";

vi.mock("./config.js", () => ({ config: { aiApiKey: "", researchProvider: "disabled" } }));
const now = new Date("2026-10-17T04:00:00Z");

describe("learner context and useful follow-up questions", () => {
  it("extracts multiple personal facts and preserves per-subject evidence from one answer", () => {
    const session = newSession();
    session.answers = [{ question: FIRST_QUESTION, answer: "我本科大三，四年制，想考上海交通大学计算机技术专硕，408还没开始，英语比较差，工作日2小时，周末4小时" }];
    session.profile.goal_type = "exam";
    session.profile.goal_subtype = "考研";
    const context = buildLearningContext(session, [], now);
    expect(context.facts).toMatchObject({ identity: { answer_index: 0 }, school: { value: "上海交通大学" }, program: { value: "计算机技术" }, degree: { value: "专硕" }, weakness: { answer_index: 0 }, availability: { answer_index: 0 } });
    expect(context.subjects).toEqual(expect.arrayContaining([expect.objectContaining({ name: "408", progress: "408还没开始" }), expect.objectContaining({ name: "英语", weakness: "英语比较差" })]));
    expect(context.timing).toMatchObject({ exam_year: 2027, admission_year: 2028, estimated: true });
    session.learning_context = context;
    expect(missingLearnerFields(session)).not.toEqual(expect.arrayContaining(["identity", "school", "program", "degree", "weakness", "availability"]));
  });

  it("does not confuse a desired score with current ability", () => {
    const session = newSession();
    session.answers = [{ question: FIRST_QUESTION, answer: "准备雅思，目标7分" }];
    expect(buildLearningContext(session).facts.baseline).toBeUndefined();
  });

  it("stores 408 as a subject, not a major, and keeps other useful facts", () => {
    const session = newSession();
    session.answers = [{ question: FIRST_QUESTION, answer: "考研" }, { question: "你准备报考什么专业或方向？", answer: "408" }];
    expect(analyzeInterview(session).program).toBe("");
    expect(knownStudySubjects(session)).toContain("408");
  });

  it("supports quoted model extraction, rejects invented or mismatched evidence, and survives a reload", () => {
    const session = newSession();
    session.answers = [{ question: FIRST_QUESTION, answer: "希望准备应用心理硕士；我在职，英语阅读做不完" }];
    const updates = [
      { field: "program" as const, value: "应用心理硕士", answer_index: 0, quote: "准备应用心理硕士" },
      { field: "school" as const, value: "上海交通大学", answer_index: 0, quote: "我在职" },
    ];
    session.learning_context = buildLearningContext(session, updates, now);
    expect(session.learning_context.facts.program.value).toBe("应用心理硕士");
    expect(session.learning_context.facts.school).toBeUndefined();
    expect(buildLearningContext(session, [], now).facts.program.value).toBe("应用心理硕士");
  });

  it("does not let model normalization change a user's grade or invent an exam year", () => {
    const session = newSession();
    session.profile.goal_subtype = "考研";
    session.answers = [{ question: FIRST_QUESTION, answer: "本科大三，准备考上海交通大学计算机技术专硕" }];
    const context = buildLearningContext(session, [
      { field: "identity", value: "本科大四", answer_index: 0, quote: "本科大三" },
      { field: "exam_year", value: "2030", answer_index: 0, quote: "本科大三" },
    ], now);
    expect(context.facts.identity.value).toBe("本科大三");
    expect(context.timing.exam_year).toBe(2027);
    expect(analyzeInterview(session).subtype).toBe("考研");
  });

  it("accepts numeric JSON values for learner_updates and normalizes them to text", () => {
    // 真实模型会把 exam_year 的 value 写成数字 2027（线上 ZodError 的实际触发点）。
    expect(LearnerUpdateSchema.parse({ field: "exam_year", value: 2027, answer_index: 2, quote: "本科大三参加明年的考研初试" }).value).toBe("2027");
    expect(LearnerUpdateSchema.parse({ field: "baseline", value: "408 过了一遍基础", answer_index: 3, quote: "408 过了一遍基础" }).value).toBe("408 过了一遍基础");
    // 真正的类型错误仍然被拒绝，避免把任意对象塞进资料。
    expect(LearnerUpdateSchema.safeParse({ field: "exam_year", value: { year: 2027 }, answer_index: 2, quote: "x" }).success).toBe(false);
  });

  it("does not record or count a meta question as an interview answer", () => {
    const session = newSession();
    session.profile.goal_type = "exam";
    session.profile.goal_subtype = "四六级";
    session.answers = [{ question: "目前哪一科最薄弱？主要是还没学、理解困难、做不出题，还是速度慢？", answer: "你是什么 AI", fields: ["weakness"] }];
    // 提问不是对“薄弱科目”的回答：不能写成 weakness，也不能算作“已经问过”。
    expect(buildLearningContext(session).facts.weakness).toBeUndefined();
    expect(missingLearnerFields(session)).toContain("weakness");
    // 正常回答仍然会被记录。
    const answered = { ...session, answers: [{ question: "目前哪一科最薄弱？", answer: "听力最差，阅读还行", fields: ["weakness" as const] }] };
    expect(buildLearningContext(answered).facts.weakness?.value).toBe("听力最差，阅读还行");
  });

  it("persists the question purpose so paraphrased questions do not depend on keyword matching", async () => {
    const session = newSession();
    session.question = "说说这一块的情况。";
    session.question_fields = ["baseline"];
    const next = await advanceOnboarding(session, { type: "answer", answer: "只到第三小节" });
    expect(next.answers[0].fields).toEqual(["baseline"]);
    expect(next.learning_context.facts.baseline.value).toBe("只到第三小节");
    expect(missingLearnerFields(next)).not.toContain("baseline");
  });

  it("does not infer an exact exam day or assume a graduate's target year", () => {
    const session = newSession();
    session.profile.goal_subtype = "考研";
    session.answers = [{ question: FIRST_QUESTION, answer: "已毕业，二战考研" }];
    expect(buildLearningContext(session, [], now).timing.exam_year).toBeNull();
    expect(session.profile.target_date).toBeNull();
  });

  it("does not apply graduate-admission timing to a language test", () => {
    const session = newSession();
    session.profile.goal_subtype = "雅思";
    session.answers = [{ question: FIRST_QUESTION, answer: "本科大三，准备2027年考试，雅思目标7分" }];
    expect(buildLearningContext(session, [], now).timing.exam_year).toBeNull();
  });

  it("keeps an explicitly supplied admission year distinct from the initial-exam year", () => {
    const session = newSession();
    session.profile.goal_subtype = "考研";
    session.answers = [{ question: FIRST_QUESTION, answer: "准备考研，希望2029年入学" }];
    expect(buildLearningContext(session, [], now).timing).toMatchObject({ exam_year: 2028, admission_year: 2029, estimated: false });
  });

  it("lets a manual year override the grade estimate without changing answers or the target date", async () => {
    const session = newSession();
    session.answers = [{ question: FIRST_QUESTION, answer: "大三准备考研" }];
    const next = await advanceOnboarding(session, { type: "set_exam_year", year: 2029 });
    expect(next.learning_context.timing).toMatchObject({ exam_year: 2029, admission_year: 2030, estimated: false });
    expect(next.answers).toEqual(session.answers);
    expect(next.profile.target_date).toBeNull();
    expect(next.revision).toBe(session.revision + 1);
  });

  it("moves past exam synonyms and prioritizes personal circumstances", async () => {
    let session = await advanceOnboarding(newSession(), { type: "answer", answer: "考试备考" });
    session = await advanceOnboarding(session, { type: "answer", answer: "研究生招生" });
    expect(session.profile.goal_subtype).toBe("考研");
    expect(session.question).toContain("大几");
    expect(session.question).not.toContain("具体考试");
    session = await advanceOnboarding(session, { type: "answer", answer: "大三，准备上海交通大学计算机技术专硕，英语比较差" });
    expect(session.question).not.toMatch(/大几|哪一类.*考试|什么专业|哪所院校|什么时候/);
    expect(session.learning_context.facts.program.value).toBe("计算机技术");
  });

  it("uses verified public knowledge to expand 408 without creating another curriculum layer", () => {
    const session = newSession();
    session.answers = [{ question: FIRST_QUESTION, answer: "准备考研，专业课408" }];
    session.research = ResearchSchema.parse({ status: "verified", facts: [{ statement: "408包含四门课程", subjects: ["数据结构", "计算机组成原理", "操作系统", "计算机网络"], source_url: "https://www.chsi.com.cn/outline", quote: "408包含数据结构、计算机组成原理、操作系统、计算机网络。", applicable_year: null }] });
    expect(knownStudySubjects(session)).toEqual(["数据结构", "计算机组成原理", "操作系统", "计算机网络"]);
  });

  it("does not repeatedly ask deferred optional information", () => {
    const session = newSession();
    session.profile.goal_type = "exam";
    session.profile.goal_subtype = "考研";
    session.answers = [{ question: FIRST_QUESTION, answer: "考研，大三" }, { question: "你想报考哪所院校、什么专业？学硕还是专硕？", answer: "暂未确定，先补基础" }];
    const prompt = buildSafeInterview(session);
    expect(prompt.question).not.toMatch(/哪所院校|什么专业|学硕还是专硕/);
  });

  it("follows a vague weakness with one practical diagnostic question", async () => {
    let session = newSession();
    session.profile = { ...session.profile, goal_type: "exam", goal_subtype: "考研" };
    session.answers = [{ question: FIRST_QUESTION, answer: "大三考研，上海交通大学计算机技术专硕，英语基础学完了但比较差" }];
    const prompt = buildSafeInterview(session);
    expect(prompt.question_fields).toEqual(["diagnostic"]);
    expect(prompt.question).toContain("最近做题");
    session = { ...session, ...prompt, question_fields: prompt.question_fields ?? [] };
    const next = await advanceOnboarding(session, { type: "answer", answer: "做得慢，阅读经常来不及" });
    expect(next.learning_context.facts.diagnostic.value).toContain("来不及");
    expect(next.question_fields).not.toContain("diagnostic");
  });

  it("supports arbitrary subject updates only when backed by the user's actual answer", () => {
    const session = newSession();
    session.answers = [{ question: FIRST_QUESTION, answer: "准备法律职业资格考试，民法学完总则，刑法做题速度慢" }];
    const context = buildLearningContext(session, [], now, [
      { name: "民法", progress: "学完总则", weakness: "", answer_index: 0, quote: "民法学完总则" },
      { name: "刑法", progress: "", weakness: "做题速度慢", answer_index: 0, quote: "刑法做题速度慢" },
      { name: "数学一", progress: "已学完", weakness: "", answer_index: 0, quote: "民法学完总则" },
    ]);
    expect(context.subjects.map(subject => subject.name)).toEqual(expect.arrayContaining(["民法", "刑法"]));
    expect(context.subjects.some(subject => subject.name === "数学一")).toBe(false);
  });

  it("invalidates old target-specific facts on an explicit change while retaining identity", () => {
    const session = newSession();
    session.answers = [{ question: FIRST_QUESTION, answer: "大三，考研，上海交通大学计算机技术，408零基础" }, { question: "你的目标是什么？", answer: "不考研了，改为雅思，目标7分" }];
    const context = buildLearningContext(session, [], now);
    expect(context.facts.identity).toBeDefined();
    expect(context.facts.school).toBeUndefined();
    expect(context.subjects.some(subject => subject.name === "408")).toBe(false);
  });
});
