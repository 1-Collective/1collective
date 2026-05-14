import { afterEach, beforeEach, describe, expect, test } from "vitest";
import {
  FOUNDATIONAL_MODULES,
  isModuleEnabled,
  missingCredentialsFor,
} from "../registry";

const ORIGINAL_ENV = { ...process.env };

beforeEach(() => {
  process.env = { ...ORIGINAL_ENV };
});

afterEach(() => {
  process.env = { ...ORIGINAL_ENV };
});

describe("FOUNDATIONAL_MODULES", () => {
  test("every module key matches its record key", () => {
    for (const [key, mod] of Object.entries(FOUNDATIONAL_MODULES)) {
      expect(mod.key).toBe(key);
    }
  });

  test("every module has a non-empty name and a valid source", () => {
    const valid = new Set(["cc", "1coll", "merge", "new"]);
    for (const mod of Object.values(FOUNDATIONAL_MODULES)) {
      expect(mod.name.length).toBeGreaterThan(0);
      expect(valid.has(mod.source)).toBe(true);
    }
  });
});

describe("isModuleEnabled", () => {
  test("reflects the registry's enabled flag", () => {
    expect(isModuleEnabled("integrations_oauth")).toBe(
      FOUNDATIONAL_MODULES.integrations_oauth.enabled
    );
    expect(isModuleEnabled("crm")).toBe(FOUNDATIONAL_MODULES.crm.enabled);
  });
});

describe("missingCredentialsFor", () => {
  test("returns empty list when all required env vars are set", () => {
    process.env.ANTHROPIC_API_KEY = "x";
    process.env.OPENAI_API_KEY = "y";
    expect(missingCredentialsFor("ai_core")).toEqual([]);
  });

  test("returns only the env vars that are missing", () => {
    process.env.ANTHROPIC_API_KEY = "x";
    delete process.env.OPENAI_API_KEY;
    expect(missingCredentialsFor("ai_core")).toEqual(["OPENAI_API_KEY"]);
  });

  test("returns full list when nothing is set", () => {
    delete process.env.TWILIO_ACCOUNT_SID;
    delete process.env.TWILIO_AUTH_TOKEN;
    delete process.env.TWILIO_VOICE_WEBHOOK_BASE_URL;
    delete process.env.ANTHROPIC_API_KEY;
    expect(missingCredentialsFor("ai_phone_daniella").sort()).toEqual(
      [
        "ANTHROPIC_API_KEY",
        "TWILIO_ACCOUNT_SID",
        "TWILIO_AUTH_TOKEN",
        "TWILIO_VOICE_WEBHOOK_BASE_URL",
      ].sort()
    );
  });
});
