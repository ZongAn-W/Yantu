import type { Subject, SubjectId } from "./types";

/** Stable seed courses; users can also create custom courses. */
export const seedCourses: Array<Pick<Subject, "id" | "name" | "color" | "priority">> = [
  { id: "calculus", name: "高数", color: "#4565c7", priority: 3 },
  { id: "linear-algebra", name: "线代", color: "#4565c7", priority: 3 },
  { id: "probability", name: "概率论", color: "#4565c7", priority: 3 },
  { id: "vocabulary", name: "词汇", color: "#147d6b", priority: 3 },
  { id: "grammar", name: "语法与长难句", color: "#147d6b", priority: 3 },
  { id: "reading", name: "阅读", color: "#147d6b", priority: 3 },
  { id: "writing", name: "写作", color: "#147d6b", priority: 3 },
  { id: "translation", name: "翻译", color: "#147d6b", priority: 2 },
  { id: "listening", name: "听力（六级）", color: "#147d6b", priority: 2 },
  { id: "data-structures", name: "数据结构", color: "#a85c21", priority: 2 },
  { id: "operating-systems", name: "操作系统", color: "#a85c21", priority: 2 },
  { id: "computer-organization", name: "计算机组成原理", color: "#a85c21", priority: 2 },
  { id: "computer-networks", name: "计算机网络", color: "#a85c21", priority: 2 },
  { id: "coding", name: "C/C++ 与机试", color: "#a85c21", priority: 2 },
  { id: "marxism", name: "马原", color: "#7a57aa", priority: 2 },
  { id: "mao", name: "毛中特", color: "#7a57aa", priority: 2 },
  { id: "xi-thought", name: "习思想", color: "#7a57aa", priority: 2 },
  { id: "history", name: "史纲", color: "#7a57aa", priority: 2 },
  { id: "ethics", name: "思修法基", color: "#7a57aa", priority: 2 },
  { id: "current-affairs", name: "时政", color: "#7a57aa", priority: 2 },
  { id: "math-mock", name: "数学整卷", color: "#4565c7", priority: 2 },
  { id: "english-mock", name: "英语整卷", color: "#147d6b", priority: 2 },
  { id: "mock-408", name: "408 整卷", color: "#a85c21", priority: 2 },
  { id: "politics-mock", name: "政治综合", color: "#7a57aa", priority: 2 },
];

const courseStages: Record<string, string[]> = {
  vocabulary: ["首轮记忆", "滚动复习"],
  grammar: ["语法基础", "真题句子拆解"],
  reading: ["真题精读", "限时训练"],
  writing: ["作文准备", "写作练习"],
  translation: ["真题训练", "错句复习"],
  listening: ["精听训练", "套题练习"],
  coding: ["语法基础", "算法训练", "模拟机试"],
  "current-affairs": ["日常积累", "考前整理"],
  "politics-mock": ["分析题背诵", "整卷模拟"],
};
for (const id of ["calculus", "linear-algebra", "probability"])
  courseStages[id] = ["基础一轮", "专题强化", "真题训练", "考前回顾"];
for (const id of ["data-structures", "operating-systems", "computer-organization", "computer-networks"])
  courseStages[id] = ["基础一轮", "重点强化", "真题训练", "考前回顾"];
for (const id of ["marxism", "mao", "xi-thought", "history", "ethics"])
  courseStages[id] = ["知识学习", "选择题训练"];
for (const id of ["math-mock", "english-mock", "mock-408"])
  courseStages[id] = ["限时模拟", "试卷复盘"];

export function stagesForCourse(courseId: SubjectId): string[] {
  return courseStages[courseId] ?? ["学习", "复习"];
}
