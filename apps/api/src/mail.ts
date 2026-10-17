import nodemailer from "nodemailer";
import { config } from "./config.js";

export function mailConfigured() {
  return Boolean(config.smtpHost && config.smtpUser && config.smtpPass && config.smtpFrom);
}

export async function sendRegistrationCode(email: string, code: string) {
  if (!mailConfigured()) throw new Error("SMTP is not configured");
  const transport = nodemailer.createTransport({
    host: config.smtpHost,
    port: config.smtpPort,
    secure: config.smtpPort === 465,
    requireTLS: config.smtpPort !== 465,
    auth: { user: config.smtpUser, pass: config.smtpPass },
    connectionTimeout: 10000,
    greetingTimeout: 10000,
    socketTimeout: 15000,
  });
  await transport.sendMail({
    from: { name: "不白学", address: config.smtpFrom },
    to: email,
    subject: "不白学注册验证码",
    text: `你的注册验证码是：${code}\n\n验证码 10 分钟内有效，请勿向他人提供。若非本人操作，请忽略此邮件。`,
  });
}
