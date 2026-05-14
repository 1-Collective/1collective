// [CC-FOUNDATION] SMS + voice via Twilio.
// Factory throws MissingCredentialsError at call time so the app boots cleanly
// with Twilio credentials blank. Used by AI Phone (Daniella, Serana), customer
// notifications, and SMS conversations.

import twilio, { type Twilio } from "twilio";
import { requireEnv } from "@/lib/integrations/base";

const REQUIRED_ENV = [
  "TWILIO_ACCOUNT_SID",
  "TWILIO_AUTH_TOKEN",
  "TWILIO_FROM_NUMBER",
] as const;

let cached: Twilio | null = null;

function client(): Twilio {
  if (cached) return cached;
  const env = requireEnv("Twilio", [...REQUIRED_ENV]);
  cached = twilio(env.TWILIO_ACCOUNT_SID, env.TWILIO_AUTH_TOKEN);
  return cached;
}

export interface SendSmsInput {
  to: string;
  body: string;
  from?: string;
}

export interface SendSmsResult {
  sid: string;
  status: string;
}

export async function sendSms(input: SendSmsInput): Promise<SendSmsResult> {
  const env = requireEnv("Twilio", [...REQUIRED_ENV]);
  if (!input.body.trim()) {
    throw new Error("sendSms requires a non-empty body.");
  }
  if (!isE164(input.to)) {
    throw new Error(`sendSms requires E.164 'to' (got: ${input.to}).`);
  }
  if (input.from !== undefined && !isE164(input.from)) {
    throw new Error(`sendSms 'from' override must be E.164 (got: ${input.from}).`);
  }

  const msg = await client().messages.create({
    to: input.to,
    from: input.from ?? env.TWILIO_FROM_NUMBER,
    body: input.body,
  });
  return { sid: msg.sid, status: msg.status };
}

export function isE164(s: string): boolean {
  return /^\+[1-9]\d{6,14}$/.test(s);
}

export function resetSmsClientForTests(): void {
  cached = null;
}
