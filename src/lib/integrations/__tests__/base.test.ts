import { afterEach, beforeEach, describe, expect, test } from "vitest";
import { randomBytes } from "node:crypto";
import {
  MissingCredentialsError,
  decryptToken,
  encryptToken,
  requireEnv,
} from "../base";

const ORIGINAL_ENV = { ...process.env };

beforeEach(() => {
  process.env = { ...ORIGINAL_ENV };
});

afterEach(() => {
  process.env = { ...ORIGINAL_ENV };
});

describe("MissingCredentialsError", () => {
  test("carries service name and missing list", () => {
    const err = new MissingCredentialsError("twilio", ["TWILIO_ACCOUNT_SID", "TWILIO_AUTH_TOKEN"]);
    expect(err.name).toBe("MissingCredentialsError");
    expect(err.service).toBe("twilio");
    expect(err.missing).toEqual(["TWILIO_ACCOUNT_SID", "TWILIO_AUTH_TOKEN"]);
    expect(err.message).toContain("twilio");
    expect(err.message).toContain("TWILIO_ACCOUNT_SID");
  });
});

describe("requireEnv", () => {
  test("returns map when all vars present", () => {
    process.env.FOO = "1";
    process.env.BAR = "2";
    const result = requireEnv("svc", ["FOO", "BAR"]);
    expect(result).toEqual({ FOO: "1", BAR: "2" });
  });

  test("throws MissingCredentialsError listing only missing vars", () => {
    process.env.FOO = "1";
    delete process.env.BAR;
    delete process.env.BAZ;
    try {
      requireEnv("svc", ["FOO", "BAR", "BAZ"]);
      throw new Error("should have thrown");
    } catch (err) {
      expect(err).toBeInstanceOf(MissingCredentialsError);
      const e = err as MissingCredentialsError;
      expect(e.missing).toEqual(["BAR", "BAZ"]);
    }
  });
});

describe("encryptToken / decryptToken", () => {
  test("round-trips a typical token with a base64 32-byte key", () => {
    process.env.INTEGRATION_TOKEN_ENCRYPTION_KEY = randomBytes(32).toString("base64");
    const plaintext = "ya29.a0ARrdaM_super_secret_oauth_access_token_value";
    const ct = encryptToken(plaintext);
    expect(ct).not.toContain(plaintext);
    expect(decryptToken(ct)).toBe(plaintext);
  });

  test("round-trips with an arbitrary string key (sha256-derived)", () => {
    process.env.INTEGRATION_TOKEN_ENCRYPTION_KEY = "any-passphrase-that-isnt-base64";
    const plaintext = "qbo-refresh-token";
    expect(decryptToken(encryptToken(plaintext))).toBe(plaintext);
  });

  test("two encryptions of same plaintext produce different ciphertexts (random IV)", () => {
    process.env.INTEGRATION_TOKEN_ENCRYPTION_KEY = randomBytes(32).toString("base64");
    const a = encryptToken("same");
    const b = encryptToken("same");
    expect(a).not.toBe(b);
    expect(decryptToken(a)).toBe("same");
    expect(decryptToken(b)).toBe("same");
  });

  test("tampered ciphertext fails authentication", () => {
    process.env.INTEGRATION_TOKEN_ENCRYPTION_KEY = randomBytes(32).toString("base64");
    const ct = encryptToken("payload");
    const buf = Buffer.from(ct, "base64");
    buf[buf.length - 1] ^= 0xff;
    const tampered = buf.toString("base64");
    expect(() => decryptToken(tampered)).toThrow();
  });

  test("encrypt throws MissingCredentialsError when key absent", () => {
    delete process.env.INTEGRATION_TOKEN_ENCRYPTION_KEY;
    try {
      encryptToken("x");
      throw new Error("should have thrown");
    } catch (err) {
      expect(err).toBeInstanceOf(MissingCredentialsError);
      expect((err as MissingCredentialsError).missing).toContain(
        "INTEGRATION_TOKEN_ENCRYPTION_KEY"
      );
    }
  });
});
