import { afterEach, describe, expect, it } from "vitest";
import { MissingCredentialsError } from "@/lib/integrations/base";
import { resetEmailClientForTests, sendEmail } from "../index";

const ORIGINAL = { ...process.env };

afterEach(() => {
  process.env = { ...ORIGINAL };
  resetEmailClientForTests();
});

describe("sendEmail", () => {
  it("throws MissingCredentialsError when RESEND_API_KEY is missing", async () => {
    delete process.env.RESEND_API_KEY;
    await expect(
      sendEmail({ to: "x@example.test", subject: "Hi", text: "Hi" })
    ).rejects.toBeInstanceOf(MissingCredentialsError);
  });

  it("throws when neither html nor text body is provided", async () => {
    process.env.RESEND_API_KEY = "test_key";
    process.env.EMAIL_FROM_ADDRESS = "noreply@example.test";
    await expect(
      sendEmail({ to: "x@example.test", subject: "Hi" })
    ).rejects.toThrow(/html or text/);
  });

  it("throws when no from address is configured", async () => {
    process.env.RESEND_API_KEY = "test_key";
    delete process.env.EMAIL_FROM_ADDRESS;
    await expect(
      sendEmail({ to: "x@example.test", subject: "Hi", text: "Hi" })
    ).rejects.toThrow(/from|EMAIL_FROM_ADDRESS/);
  });

  it("rejects empty subject", async () => {
    process.env.RESEND_API_KEY = "test_key";
    process.env.EMAIL_FROM_ADDRESS = "noreply@example.test";
    await expect(
      sendEmail({ to: "x@example.test", subject: "  ", text: "Hi" })
    ).rejects.toThrow(/subject/);
  });

  it("rejects malformed recipient addresses", async () => {
    process.env.RESEND_API_KEY = "test_key";
    process.env.EMAIL_FROM_ADDRESS = "noreply@example.test";
    await expect(
      sendEmail({ to: "not-an-email", subject: "Hi", text: "Hi" })
    ).rejects.toThrow(/recipient/);
    await expect(
      sendEmail({ to: ["ok@example.test", "bad"], subject: "Hi", text: "Hi" })
    ).rejects.toThrow(/recipient/);
  });
});
