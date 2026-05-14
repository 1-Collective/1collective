// [CC-FOUNDATION] Per-tenant, per-year estimate numbering: EST-YYYY-NNNN.
// Atomic via cc_next_estimate_seq() in Postgres (counter row + ON CONFLICT
// DO UPDATE RETURNING). Two concurrent inserts always observe a strictly
// increasing sequence with no read-then-write window.
import type { SupabaseClient } from "@supabase/supabase-js";

const PREFIX = "EST";

export async function nextEstimateNumber(
  admin: SupabaseClient,
  tenantId: string,
  now: Date = new Date()
): Promise<string> {
  const year = now.getUTCFullYear();
  const { data, error } = await admin.rpc("cc_next_estimate_seq", {
    p_tenant: tenantId,
    p_year: year,
  });
  if (error || typeof data !== "number") {
    throw new Error(`Could not allocate estimate number: ${error?.message ?? "no row"}`);
  }
  return formatNumber(year, data);
}

export function formatNumber(year: number, seq: number): string {
  return `${PREFIX}-${year}-${seq.toString().padStart(4, "0")}`;
}
