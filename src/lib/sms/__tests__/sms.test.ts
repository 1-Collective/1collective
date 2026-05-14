import { afterEach, describe, expect, it } from "vitest";
import { MissingCredentialsError } from "@/lib/integrations/base";
import { isE164, resetSmsClientForTests, sendSms } from "../index";

const ORIGINAL = { ...process.env };

afterEach(() => {
  process.env = { ...ORIGINAL };
  resetSmsClientForTests();
});

describe("isE164", () => {
  it("accepts valid E.164 numbers", () => {
    expect(isE164("+15551234567")).toBe(true);
    expect(isE164("+447700900123")).toBe(true);
  });
  it("rejects formats that aren't E.164", () => {
    expect(isE164("5551234567")).toBe(false);
    expect(isE164("(555) 123-4567")).toBe(false);
    expect(isE164("+0123")).toBe(false);
    expect(isE164("")).toBe(false);
  });
});

describe("sendSms", () => {
  it("throws MissingCredentialsError when Twilio env is absent", async () => {
    delete process.env.TWILIO_ACCOUNT_SID;
    delete process.env.TWILIO_AUTH_TOKEN;
    delete process.env.TWILIO_FROM_NUMBER;
    await expect(
      sendSms({ to: "+15551234567", body: "Hi" })
    ).rejects.toBeInstanceOf(MissingCredentialsError);
  });

  it("rejects empty body", async () => {
    process.env.TWILIO_ACCOUNT_SID = "ACtest";
    process.env.TWILIO_AUTH_TOKEN = "test";
    process.env.TWILIO_FROM_NUMBER = "+15550000000";
    await expect(
      sendSms({ to: "+15551234567", body: "   " })
    ).rejects.toThrow(/non-empty/);
  });

  it("rejects non-E.164 to-numbers before calling Twilio", async () => {
    process.env.TWILIO_ACCOUNT_SID = "ACtest";
    process.env.TWILIO_AUTH_TOKEN = "test";
    process.env.TWILIO_FROM_NUMBER = "+15550000000";
    await expect(
      sendSms({ to: "555-1234", body: "Hi" })
    ).rejects.toThrow(/E\.164/);
  });

  it("rejects non-E.164 'from' override before calling Twilio", async () => {
    process.env.TWILIO_ACCOUNT_SID = "ACtest";
    process.env.TWILIO_AUTH_TOKEN = "test";
    process.env.TWILIO_FROM_NUMBER = "+15550000000";
    await expect(
      sendSms({ to: "+15551234567", body: "Hi", from: "555-1234" })
    ).rejects.toThrow(/from.*E\.164/);
  });
});
