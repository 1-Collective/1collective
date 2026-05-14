// [CC-FOUNDATION] Base error + crypto helpers for tenant-scoped third-party
// integrations. Every integration factory (twilio, anthropic, qbo, google,
// meta, vapi) throws MissingCredentialsError at *call time*, never at module
// load time. This keeps the app bootable with all credentials blank.

import { createCipheriv, createDecipheriv, randomBytes, createHash } from "node:crypto";

export class MissingCredentialsError extends Error {
  readonly service: string;
  readonly missing: string[];
  constructor(service: string, missing: string[]) {
    super(
      `${service} integration is not configured. Set ${missing.join(", ")} in environment to enable it.`
    );
    this.name = "MissingCredentialsError";
    this.service = service;
    this.missing = missing;
  }
}

export function requireEnv(service: string, vars: string[]): Record<string, string> {
  const missing = vars.filter((v) => !process.env[v]);
  if (missing.length > 0) throw new MissingCredentialsError(service, missing);
  return Object.fromEntries(vars.map((v) => [v, process.env[v] as string]));
}

const ALG = "aes-256-gcm";

function getKey(): Buffer {
  const raw = process.env.INTEGRATION_TOKEN_ENCRYPTION_KEY;
  if (!raw) {
    throw new MissingCredentialsError("Token storage", ["INTEGRATION_TOKEN_ENCRYPTION_KEY"]);
  }
  // Accept either base64 (44 chars) or any string (hashed to 32 bytes).
  if (/^[A-Za-z0-9+/=]{43,44}$/.test(raw)) {
    const buf = Buffer.from(raw, "base64");
    if (buf.length === 32) return buf;
  }
  return createHash("sha256").update(raw).digest();
}

export function encryptToken(plaintext: string): string {
  const iv = randomBytes(12);
  const cipher = createCipheriv(ALG, getKey(), iv);
  const encrypted = Buffer.concat([cipher.update(plaintext, "utf8"), cipher.final()]);
  const tag = cipher.getAuthTag();
  return Buffer.concat([iv, tag, encrypted]).toString("base64");
}

export function decryptToken(ciphertext: string): string {
  const buf = Buffer.from(ciphertext, "base64");
  const iv = buf.subarray(0, 12);
  const tag = buf.subarray(12, 28);
  const encrypted = buf.subarray(28);
  const decipher = createDecipheriv(ALG, getKey(), iv);
  decipher.setAuthTag(tag);
  const decrypted = Buffer.concat([decipher.update(encrypted), decipher.final()]);
  return decrypted.toString("utf8");
}
