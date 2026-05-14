// [CC-FOUNDATION] Transactional email via Resend.
// Factory throws MissingCredentialsError at call time so the app boots cleanly
// with RESEND_API_KEY blank.

import { Resend } from "resend";
import { requireEnv } from "@/lib/integrations/base";

let cached: Resend | null = null;

function client(): Resend {
  if (cached) return cached;
  const env = requireEnv("Resend", ["RESEND_API_KEY"]);
  cached = new Resend(env.RESEND_API_KEY);
  return cached;
}

export interface SendEmailInput {
  to: string | string[];
  subject: string;
  html?: string;
  text?: string;
  from?: string;
  replyTo?: string;
}

export interface SendEmailResult {
  id: string;
}

function isLikelyEmail(s: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(s);
}

export async function sendEmail(input: SendEmailInput): Promise<SendEmailResult> {
  const env = requireEnv("Resend", ["RESEND_API_KEY"]);
  const from = input.from ?? process.env.EMAIL_FROM_ADDRESS;
  if (!from) {
    throw new Error(
      "sendEmail requires either input.from or EMAIL_FROM_ADDRESS in environment."
    );
  }
  if (!input.html && !input.text) {
    throw new Error("sendEmail requires either html or text body.");
  }
  if (!input.subject.trim()) {
    throw new Error("sendEmail requires a non-empty subject.");
  }
  const recipients = Array.isArray(input.to) ? input.to : [input.to];
  if (recipients.length === 0 || recipients.some((r) => !isLikelyEmail(r))) {
    throw new Error("sendEmail requires at least one valid recipient address.");
  }

  void env;
  const base = {
    from,
    to: input.to,
    subject: input.subject,
    replyTo: input.replyTo,
  };
  const payload = input.html
    ? { ...base, html: input.html }
    : { ...base, text: input.text as string };
  const r = await client().emails.send(payload);

  if (r.error) {
    throw new Error(`Resend send failed: ${r.error.message}`);
  }
  return { id: r.data?.id ?? "" };
}

export function resetEmailClientForTests(): void {
  cached = null;
}
