// [CC-FOUNDATION] Estimating zod schemas + decimal-safe money helpers.
// All money is stored as integer cents. We parse user input as a string and
// route through integer math so 1.005-style values round deterministically
// (no `Number` round-trip). Quantities are stored at 4-decimal precision
// (numeric(12,4)) and computed internally as integer ten-thousandths.
import { z } from "zod";

export const ESTIMATE_STATUSES = [
  "draft",
  "sent",
  "accepted",
  "declined",
  "expired",
] as const;
export type EstimateStatus = (typeof ESTIMATE_STATUSES)[number];

export const MAX_LINE_ITEMS = 200;
const MAX_MONEY_CENTS = 9_999_999_999;
const MAX_QTY_TEN_THOUSANDTHS = 99_999_999;

const MONEY_RE = /^\d+(\.\d{1,2})?$/;
const QTY_RE = /^\d+(\.\d{1,4})?$/;
const PERCENT_RE = /^\d{1,3}(\.\d{1,4})?$/;

function normalizeNumericString(input: string | number | undefined | null): string | null {
  if (input === undefined || input === null) return null;
  const s = typeof input === "number" ? input.toString() : input.trim();
  if (s === "") return null;
  return s;
}

export function moneyDollarsToCents(input: string | number | undefined | null): number {
  const s = normalizeNumericString(input);
  if (s === null) return 0;
  if (!MONEY_RE.test(s)) {
    throw new Error("Money values must be non-negative numbers with up to two decimal places.");
  }
  const [whole, fracRaw = ""] = s.split(".");
  const frac = (fracRaw + "00").slice(0, 2);
  const cents = Number(whole) * 100 + Number(frac);
  if (!Number.isSafeInteger(cents)) throw new Error("Money value out of range.");
  if (cents > MAX_MONEY_CENTS) {
    throw new Error("Money value exceeds maximum supported amount.");
  }
  return cents;
}

export function centsToDollars(cents: number): number {
  return Math.round(cents) / 100;
}

export function quantityToTenThousandths(input: string | number | undefined | null): number {
  const s = normalizeNumericString(input);
  if (s === null) throw new Error("Quantity is required.");
  if (!QTY_RE.test(s)) {
    throw new Error("Quantity must be a non-negative number with up to four decimal places.");
  }
  const [whole, fracRaw = ""] = s.split(".");
  const frac = (fracRaw + "0000").slice(0, 4);
  const tt = Number(whole) * 10000 + Number(frac);
  if (!Number.isSafeInteger(tt) || tt <= 0) {
    throw new Error("Quantity must be greater than zero.");
  }
  if (tt > MAX_QTY_TEN_THOUSANDTHS) {
    throw new Error("Quantity exceeds maximum supported amount.");
  }
  return tt;
}

export function tenThousandthsToDecimalString(tt: number): string {
  const whole = Math.trunc(tt / 10000);
  const frac = (tt % 10000).toString().padStart(4, "0");
  return `${whole}.${frac}`;
}

export function percentToBps(input: string | number | undefined | null): number {
  const s = normalizeNumericString(input);
  if (s === null) return 0;
  if (!PERCENT_RE.test(s)) {
    throw new Error("Tax rate must be a number with up to four decimal places.");
  }
  const [whole, fracRaw = ""] = s.split(".");
  const frac = (fracRaw + "0000").slice(0, 4);
  // 1% = 100 bps; percent stored as integer hundred-thousandths => /10 -> bps.
  // bps = whole*100 + frac/100, computed via integer math then rounded.
  const scaled = Number(whole) * 1_000_000 + Number(frac) * 100;
  const bps = Math.round(scaled / 10_000);
  if (bps < 0 || bps > 10000) {
    throw new Error("Tax rate must be between 0 and 100.");
  }
  return bps;
}

const optionalUuid = z
  .string()
  .uuid()
  .or(z.literal(""))
  .transform((v) => (v === "" ? null : v));

const optionalText = (max: number) =>
  z
    .string()
    .max(max)
    .optional()
    .transform((v) => (v ? v : null));

const moneyField = z
  .union([z.string(), z.number()])
  .transform((v) => moneyDollarsToCents(v));

const quantityField = z
  .union([z.string(), z.number()])
  .transform((v) => quantityToTenThousandths(v));

const taxRateField = z
  .union([z.string(), z.number()])
  .optional()
  .transform((v) => percentToBps(v ?? null));

export const createEstimateSchema = z.object({
  title: z.string().trim().min(1, "Title is required.").max(200),
  company_id: optionalUuid.optional(),
  project_id: optionalUuid.optional(),
  valid_until: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/, "Valid-until must be a date.")
    .or(z.literal(""))
    .optional()
    .transform((v) => (v ? v : null)),
  notes: optionalText(4000),
  terms: optionalText(4000),
  tax_rate_percent: taxRateField,
});

export const updateEstimateSchema = createEstimateSchema.extend({
  estimate_id: z.string().uuid(),
});

export const estimateIdSchema = z.object({
  estimate_id: z.string().uuid(),
});

export const lineItemBaseSchema = z.object({
  estimate_id: z.string().uuid(),
  description: z.string().trim().min(1, "Description is required.").max(500),
  quantity: quantityField,
  unit: z.string().trim().min(1).max(16).default("ea"),
  unit_price: moneyField,
});

export const createLineItemSchema = lineItemBaseSchema;

export const updateLineItemSchema = lineItemBaseSchema.extend({
  line_item_id: z.string().uuid(),
});

export const lineItemIdSchema = z.object({
  line_item_id: z.string().uuid(),
});

export const setStatusSchema = z.object({
  estimate_id: z.string().uuid(),
  status: z.enum(ESTIMATE_STATUSES),
});

// Float-safe line total: tt * cents are both safe integers (<= ~10^16); their
// product fits inside Number.MAX_SAFE_INTEGER for all permitted ranges.
export function lineItemTotalCents(qtyTenThousandths: number, unitPriceCents: number): number {
  if (!Number.isSafeInteger(qtyTenThousandths) || qtyTenThousandths <= 0) {
    throw new Error("Quantity must be > 0.");
  }
  if (!Number.isSafeInteger(unitPriceCents) || unitPriceCents < 0) {
    throw new Error("Unit price must be >= 0.");
  }
  const product = qtyTenThousandths * unitPriceCents;
  if (!Number.isSafeInteger(product)) {
    throw new Error("Line total exceeds safe integer range.");
  }
  // Banker-agnostic: round half away from zero (positive only here).
  return Math.floor((product + 5000) / 10000);
}

export function taxCents(subtotalCents: number, rateBps: number): number {
  if (subtotalCents < 0) throw new Error("Subtotal must be >= 0.");
  if (rateBps < 0 || rateBps > 10000) throw new Error("Tax rate out of range.");
  const product = subtotalCents * rateBps;
  if (!Number.isSafeInteger(product)) throw new Error("Tax computation overflow.");
  return Math.floor((product + 5000) / 10000);
}
