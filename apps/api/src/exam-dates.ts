/**
 * 初试日期估算：每年 12 月的倒数第二个周六。
 *
 * 近年全国硕士研究生招生考试初试日期（2023-12-23、2024-12-21、2025-12-20、
 * 2026-12-19）都落在 12 月倒数第二个周六，因此只有初试年份时先按该规律估算。
 * 估算值不是官方通知，调用方必须在理由里说明以官方公告为准、可调整。
 */
export function estimatedExamDate(examYear: number): string {
  if (!Number.isInteger(examYear)) throw new Error("初试年份必须是整数");
  // 先取 12 月 31 日，回退到该月最后一个周六，再退一周得到倒数第二个周六。
  // getUTCDay: 0 表示周日、6 表示周六；日期运算统一用 UTC，避免时区把日期偏移一天。
  const lastDay = new Date(Date.UTC(examYear, 11, 31));
  const lastSaturday = 31 - ((lastDay.getUTCDay() + 1) % 7);
  return new Date(Date.UTC(examYear, 11, lastSaturday - 7)).toISOString().slice(0, 10);
}
