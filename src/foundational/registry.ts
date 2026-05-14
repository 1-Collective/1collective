// [CC-FOUNDATION] Module registry.
// Every feature ported from Contractor Command, or built fresh as part of the
// post-merge buildout, is listed here with an enable flag and the credentials
// it needs. Server Actions check `enabled` before executing; the Integrations
// admin page reads `requiredCredentials` to surface "Setup required" banners.

export type FoundationalModuleKey =
  | "vault"
  | "integrations_oauth"
  | "ai_core"
  | "ai_phone_daniella"
  | "ai_phone_serana"
  | "social_amber"
  | "booking"
  | "google_sync"
  | "quickbooks_sync"
  | "invoicing"
  | "projects"
  | "manpower"
  | "estimating"
  | "crm";

export interface FoundationalModule {
  key: FoundationalModuleKey;
  name: string;
  enabled: boolean;
  source: "cc" | "1coll" | "merge" | "new";
  requiredCredentials: string[];
  notes?: string;
}

export const FOUNDATIONAL_MODULES: Record<FoundationalModuleKey, FoundationalModule> = {
  integrations_oauth: {
    key: "integrations_oauth",
    name: "OAuth token storage",
    enabled: true,
    source: "new",
    requiredCredentials: ["INTEGRATION_TOKEN_ENCRYPTION_KEY"],
    notes: "Encrypted-at-rest store for tenant OAuth tokens (QBO, Google, Meta, Vapi).",
  },
  vault: {
    key: "vault",
    name: "Vault",
    enabled: true,
    source: "new",
    requiredCredentials: [],
    notes: "Secure tenant-scoped document store on Supabase Storage. Tenant isolation enforced via RLS on cc_vault_documents and tenant-prefixed storage paths served only through short-lived signed URLs.",
  },
  ai_core: {
    key: "ai_core",
    name: "AI core",
    enabled: false,
    source: "merge",
    requiredCredentials: ["ANTHROPIC_API_KEY", "OPENAI_API_KEY"],
    notes: "LLM clients + per-tenant usage metering. Powers Daniella, Serana, Amber.",
  },
  ai_phone_daniella: {
    key: "ai_phone_daniella",
    name: "AI Phone — Daniella (Inbound)",
    enabled: false,
    source: "cc",
    requiredCredentials: [
      "ANTHROPIC_API_KEY",
      "TWILIO_ACCOUNT_SID",
      "TWILIO_AUTH_TOKEN",
      "TWILIO_VOICE_WEBHOOK_BASE_URL",
    ],
    notes: "Per-tenant Twilio phone number forwards inbound calls to AI receptionist.",
  },
  ai_phone_serana: {
    key: "ai_phone_serana",
    name: "AI Phone — Serana (Outbound)",
    enabled: false,
    source: "cc",
    requiredCredentials: ["ANTHROPIC_API_KEY", "VAPI_PRIVATE_KEY", "VAPI_PUBLIC_KEY"],
    notes: "Vapi-driven outbound AI calls for follow-ups, reminders, payment chasers.",
  },
  social_amber: {
    key: "social_amber",
    name: "Social — Amber",
    enabled: false,
    source: "cc",
    requiredCredentials: ["META_APP_ID", "META_APP_SECRET", "META_OAUTH_REDIRECT_URI"],
    notes: "Cross-platform composer + scheduler for Facebook, Instagram, Google Business Profile.",
  },
  booking: {
    key: "booking",
    name: "Booking widget",
    enabled: false,
    source: "new",
    requiredCredentials: [],
    notes: "Public per-tenant booking page; honors Google Calendar availability when google_sync is connected.",
  },
  google_sync: {
    key: "google_sync",
    name: "Google sync (Calendar + Drive + GBP)",
    enabled: false,
    source: "merge",
    requiredCredentials: [
      "GOOGLE_OAUTH_CLIENT_ID",
      "GOOGLE_OAUTH_CLIENT_SECRET",
      "GOOGLE_OAUTH_REDIRECT_URI",
    ],
    notes: "Single OAuth flow covering Calendar, Drive, and Business Profile scopes.",
  },
  quickbooks_sync: {
    key: "quickbooks_sync",
    name: "QuickBooks Online sync",
    enabled: false,
    source: "cc",
    requiredCredentials: [
      "QBO_CLIENT_ID",
      "QBO_CLIENT_SECRET",
      "QBO_REDIRECT_URI",
      "QBO_ENVIRONMENT",
    ],
    notes: "Two-way sync of customers, invoices, payments, items.",
  },
  invoicing: {
    key: "invoicing",
    name: "Invoicing",
    enabled: false,
    source: "cc",
    requiredCredentials: [],
    notes: "Native invoice + payment models; QuickBooks sync surfaces inside this page.",
  },
  projects: {
    key: "projects",
    name: "Projects (WIP / pipeline / change orders)",
    enabled: false,
    source: "cc",
    requiredCredentials: [],
    notes: "Extends 1collective's existing projects table with CC's operational columns.",
  },
  manpower: {
    key: "manpower",
    name: "Manpower (scheduling / timeclock / crew chat)",
    enabled: false,
    source: "cc",
    requiredCredentials: [],
    notes: "Distinct from Admin → Team (user management).",
  },
  estimating: {
    key: "estimating",
    name: "Estimating + Buyout",
    enabled: true,
    source: "cc",
    requiredCredentials: [],
    notes: "Itemized estimates with line items, per-tenant numbering (EST-YYYY-NNNN), branded PDF download. Catalog UI and e-signature land in a later phase.",
  },
  crm: {
    key: "crm",
    name: "CRM (leads / pipeline / referrals)",
    enabled: true,
    source: "merge",
    requiredCredentials: [],
    notes: "1coll schema + UI shell, CC backend logic for leads pipeline.",
  },
};

export function isModuleEnabled(key: FoundationalModuleKey): boolean {
  return FOUNDATIONAL_MODULES[key].enabled;
}

export function missingCredentialsFor(key: FoundationalModuleKey): string[] {
  const mod = FOUNDATIONAL_MODULES[key];
  return mod.requiredCredentials.filter((env) => !process.env[env]);
}
