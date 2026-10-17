import { describe, expect, it } from "vitest";
import { RegistrationSchema } from "./registration.js";

describe("email registration contract", () => {
  const valid = { email: "student@example.com", username: "小明_408", password: "Study4089", code: "123456" };

  it("requires a six digit code and a strong password", () => {
    expect(RegistrationSchema.safeParse(valid).success).toBe(true);
    expect(RegistrationSchema.safeParse({ ...valid, password: "short" }).success).toBe(false);
    expect(RegistrationSchema.safeParse({ ...valid, password: "onlyletters" }).success).toBe(false);
    expect(RegistrationSchema.safeParse({ ...valid, code: "12345" }).success).toBe(false);
  });

  it("normalizes email and validates the username alphabet", () => {
    const parsed = RegistrationSchema.safeParse({ ...valid, email: " Student@Example.COM " });
    expect(parsed.success).toBe(true);
    if (parsed.success) expect(parsed.data.email).toBe("student@example.com");
    expect(RegistrationSchema.safeParse({ ...valid, username: "bad name" }).success).toBe(false);
  });
});
