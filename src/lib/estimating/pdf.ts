// [CC-FOUNDATION] Adapter: estimate row + line items -> generateDocumentPdf input.
import type { SupabaseClient } from "@supabase/supabase-js";
import { generateDocumentPdf, type DocumentPdfData, type PdfBrand } from "@/lib/pdf/document-pdf";
import { centsToDollars } from "./schemas";

export interface RenderEstimatePdfArgs {
  admin: SupabaseClient;
  tenantId: string;
  estimateId: string;
}

export async function renderEstimatePdf({
  admin,
  tenantId,
  estimateId,
}: RenderEstimatePdfArgs): Promise<{ buffer: Buffer; estimateNumber: string }> {
  const { data: estimate, error: eErr } = await admin
    .from("cc_estimates")
    .select(
      "id, tenant_id, estimate_number, title, status, subtotal_cents, tax_rate_bps, tax_cents, total_cents, valid_until, notes, terms, created_at, company_id"
    )
    .eq("id", estimateId)
    .eq("tenant_id", tenantId)
    .maybeSingle();
  if (eErr) throw new Error(`Could not load estimate: ${eErr.message}`);
  if (!estimate) throw new Error("Estimate not found.");

  const [{ data: items, error: liErr }, { data: tenant, error: tErr }, companyResult] =
    await Promise.all([
      admin
        .from("cc_estimate_line_items")
        .select("position, description, quantity, unit, unit_price_cents, total_cents")
        .eq("estimate_id", estimate.id)
        .eq("tenant_id", tenantId)
        .order("position", { ascending: true }),
      admin
        .from("tenants")
        .select("name, primary_color_hex")
        .eq("id", tenantId)
        .maybeSingle(),
      estimate.company_id
        ? admin
            .from("companies")
            .select("name")
            .eq("id", estimate.company_id)
            .eq("tenant_id", tenantId)
            .maybeSingle()
        : Promise.resolve({ data: null }),
    ]);
  if (liErr) throw new Error(`Could not load line items: ${liErr.message}`);
  if (tErr) throw new Error(`Could not load tenant: ${tErr.message}`);

  const brand: PdfBrand = {
    accent: tenant?.primary_color_hex || "#0A0A0A",
  };

  const composedNotes = composeNotes({
    subtotal_cents: estimate.subtotal_cents,
    tax_rate_bps: estimate.tax_rate_bps,
    tax_cents: estimate.tax_cents,
    notes: estimate.notes,
    terms: estimate.terms,
  });

  const data: DocumentPdfData = {
    type: "quote",
    docNumber: estimate.estimate_number,
    jobName: estimate.title,
    status: mapStatusForPdf(estimate.status),
    createdAt: estimate.created_at,
    validUntil: estimate.valid_until ?? undefined,
    total: centsToDollars(estimate.total_cents),
    notes: composedNotes,
    companyName: tenant?.name ?? "Your Company",
    customerName: companyResult?.data?.name ?? "Customer",
    lineItems: (items ?? []).map((li) => ({
      description: li.description,
      quantity: Number(li.quantity),
      unit_price: centsToDollars(li.unit_price_cents),
      total: centsToDollars(li.total_cents),
    })),
  };

  const buffer = await generateDocumentPdf(data, brand);
  return { buffer, estimateNumber: estimate.estimate_number };
}

// Estimate statuses -> PDF status labels (the renderer maps these to colors).
function mapStatusForPdf(status: string): string {
  switch (status) {
    case "draft":
      return "draft";
    case "sent":
      return "quote_sent";
    case "accepted":
      return "won";
    case "declined":
      return "lost";
    case "expired":
      return "lost";
    default:
      return status;
  }
}

interface NotesSource {
  subtotal_cents: number;
  tax_rate_bps: number;
  tax_cents: number;
  notes: string | null;
  terms: string | null;
}

function composeNotes(src: NotesSource): string | undefined {
  const lines: string[] = [];
  if (src.tax_rate_bps > 0) {
    const ratePct = (src.tax_rate_bps / 100).toFixed(2).replace(/\.?0+$/, "");
    lines.push(
      `Subtotal: $${centsToDollars(src.subtotal_cents).toFixed(2)}    Tax (${ratePct}%): $${centsToDollars(src.tax_cents).toFixed(2)}`
    );
  }
  if (src.notes?.trim()) lines.push(src.notes.trim());
  if (src.terms?.trim()) lines.push("Terms: " + src.terms.trim());
  return lines.length > 0 ? lines.join("\n\n") : undefined;
}
