import { randomBytes } from "node:crypto";
import { writeFile } from "node:fs/promises";

const password = randomBytes(32).toString("hex");
const contents = [
  "PORT=8787",
  `POSTGRES_PASSWORD=${password}`,
  `DATABASE_URL=postgres://planner:${password}@db:5432/planner`,
  `JWT_ACCESS_SECRET=${randomBytes(48).toString("base64url")}`,
  `JWT_REFRESH_SECRET=${randomBytes(48).toString("base64url")}`,
  "WEB_ORIGIN=http://127.0.0.1:5180",
  "AI_BASE_URL=https://api.deepseek.com",
  "AI_API_KEY=",
  "AI_MODEL=deepseek-flash",
  "AI_REASONING_EFFORT=max",
  "SMTP_HOST=smtp.qq.com",
  "SMTP_PORT=465",
  "SMTP_USER=",
  "SMTP_PASS=",
  "SMTP_FROM=",
  "",
].join("\n");

try {
  await writeFile(new URL(".env", import.meta.url), contents, {
    encoding: "utf8",
    flag: "wx",
    mode: 0o600,
  });
  console.log("Created apps/api/.env with random database and JWT secrets.");
  console.log("AI_API_KEY is empty; deterministic fallback is enabled.");
} catch (error) {
  if (error?.code === "EEXIST") {
    console.error("apps/api/.env already exists; no changes were made.");
  } else {
    console.error(`Could not create apps/api/.env (${error?.code || "unknown error"}).`);
  }
  process.exitCode = 1;
}
