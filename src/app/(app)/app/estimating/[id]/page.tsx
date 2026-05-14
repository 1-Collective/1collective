import type { Metadata } from "next";
import { notFound } from "next/navigation";
import Link from "next/link";
import { requireTenantUser } from "@/lib/auth/session";
import { createAdminClient } from "@/lib/supabase/admin";
import { isModuleEnabled } from "@/foundational/registry";
import { ModuleStatus } from "@/components/app-shell/module-status";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { formatDate } from "@/lib/utils";
import { centsToDollars } from "@/lib/estimating/schemas";
import {
  addLineItem,
  deleteEstimate,
  deleteLineItem,
  downloadEstimatePdf,
  setEstimateStatus,
  updateEstimate,
} from "@/lib/estimating/actions";

async function addLineItemForm(formData: FormData): Promise<void> {
  "use server";
  const r = await addLineItem(formData);
  if (!r.ok) throw new Error(r.error);
}

async function updateEstimateForm(formData: FormData): Promise<void> {
  "use server";
  const r = await updateEstimate(formData);
  if (!r.ok) throw new Error(r.error);
}

async function setEstimateStatusForm(formData: FormData): Promise<void> {
  "use server";
  const r = await setEstimateStatus(formData);
  if (!r.ok) throw new Error(r.error);
}

export const metadata: Metadata = { title: "Estimate" };

const STATUS_VARIANT: Record<string, "default" | "secondary" | "destructive" | "outline"> = {
  draft: "secondary",
  sent: "default",
  accepted: "default",
  declined: "destructive",
  expired: "outline",
};

function fmtMoney(cents: number): string {
  return centsToDollars(cents).toLocaleString("en-US", {
    style: "currency",
    currency: "USD",
  });
}

export default async function EstimateDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const session = await requireTenantUser();

  if (!isModuleEnabled("estimating")) {
    return <ModuleStatus kind="coming_soon" title="Estimating" description="Module not yet enabled." />;
  }

  const { id } = await params;
  const admin = createAdminClient();

  const { data: estimate } = await admin
    .from("cc_estimates")
    .select(
      "id, tenant_id, estimate_number, title, status, company_id, project_id, subtotal_cents, tax_rate_bps, tax_cents, total_cents, valid_until, sent_at, accepted_at, declined_at, notes, terms, created_at"
    )
    .eq("id", id)
    .maybeSingle();

  if (!estimate || estimate.tenant_id !== session.tenantId) notFound();

  const [{ data: items }, { data: companies }] = await Promise.all([
    admin
      .from("cc_estimate_line_items")
      .select("id, position, description, quantity, unit, unit_price_cents, total_cents")
      .eq("estimate_id", estimate.id)
      .eq("tenant_id", session.tenantId)
      .order("position", { ascending: true }),
    admin
      .from("companies")
      .select("id, name")
      .eq("tenant_id", session.tenantId)
      .is("deleted_at", null)
      .order("name"),
  ]);

  const lineItems = items ?? [];
  const taxRatePercent = estimate.tax_rate_bps / 100;

  return (
    <div className="space-y-6 p-8">
      <div className="flex items-start justify-between gap-4">
        <div>
          <div className="flex items-center gap-2">
            <h1 className="text-2xl font-semibold tracking-tight">{estimate.title}</h1>
            <Badge variant={STATUS_VARIANT[estimate.status] ?? "secondary"}>{estimate.status}</Badge>
          </div>
          <p className="mt-1 text-sm text-[var(--color-muted-foreground)]">
            {estimate.estimate_number} · created {formatDate(estimate.created_at)}
          </p>
        </div>
        <div className="flex gap-2">
          <form action={downloadEstimatePdf}>
            <input type="hidden" name="estimate_id" value={estimate.id} />
            <Button type="submit" variant="outline">
              Download PDF
            </Button>
          </form>
          <Button variant="ghost" asChild>
            <Link href="/app/estimating">Back</Link>
          </Button>
        </div>
      </div>

      <div className="grid gap-6 lg:grid-cols-[1fr_360px]">
        <div className="space-y-6">
          <Card>
            <CardHeader>
              <CardTitle className="text-base">Line items</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              {lineItems.length === 0 ? (
                <div className="rounded-md border border-dashed border-[var(--color-border)] py-8 text-center text-sm text-[var(--color-muted-foreground)]">
                  No line items yet. Add one below.
                </div>
              ) : (
                <div className="overflow-x-auto">
                  <table className="w-full text-sm">
                    <thead className="text-left text-xs uppercase tracking-wide text-[var(--color-muted-foreground)]">
                      <tr className="border-b border-[var(--color-border)]">
                        <th className="py-2 pr-3">Description</th>
                        <th className="py-2 pr-3 text-right">Qty</th>
                        <th className="py-2 pr-3 text-right">Unit price</th>
                        <th className="py-2 pr-3 text-right">Total</th>
                        <th className="py-2"></th>
                      </tr>
                    </thead>
                    <tbody>
                      {lineItems.map((li) => (
                        <tr key={li.id} className="border-b border-[var(--color-border)]/50">
                          <td className="py-2 pr-3">{li.description}</td>
                          <td className="py-2 pr-3 text-right">
                            {Number(li.quantity)} {li.unit}
                          </td>
                          <td className="py-2 pr-3 text-right">
                            {fmtMoney(Number(li.unit_price_cents))}
                          </td>
                          <td className="py-2 pr-3 text-right font-medium">
                            {fmtMoney(Number(li.total_cents))}
                          </td>
                          <td className="py-2 text-right">
                            <form action={deleteLineItem} className="inline">
                              <input type="hidden" name="line_item_id" value={li.id} />
                              <input type="hidden" name="estimate_id" value={estimate.id} />
                              <Button type="submit" variant="ghost" size="sm">
                                Remove
                              </Button>
                            </form>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}

              <form action={addLineItemForm} className="grid grid-cols-12 gap-2 pt-3">
                <input type="hidden" name="estimate_id" value={estimate.id} />
                <input
                  name="description"
                  required
                  placeholder="Description"
                  className="col-span-5 rounded-md border border-[var(--color-border)] bg-[var(--color-background)] px-3 py-2 text-sm"
                />
                <input
                  name="quantity"
                  type="number"
                  step="0.01"
                  min="0.01"
                  required
                  defaultValue="1"
                  placeholder="Qty"
                  className="col-span-2 rounded-md border border-[var(--color-border)] bg-[var(--color-background)] px-3 py-2 text-sm"
                />
                <input
                  name="unit"
                  defaultValue="ea"
                  className="col-span-1 rounded-md border border-[var(--color-border)] bg-[var(--color-background)] px-3 py-2 text-sm"
                />
                <input
                  name="unit_price"
                  type="number"
                  step="0.01"
                  min="0"
                  required
                  placeholder="Unit price"
                  className="col-span-3 rounded-md border border-[var(--color-border)] bg-[var(--color-background)] px-3 py-2 text-sm"
                />
                <Button type="submit" className="col-span-1" size="sm">
                  Add
                </Button>
              </form>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle className="text-base">Estimate details</CardTitle>
            </CardHeader>
            <CardContent>
              <form action={updateEstimateForm} className="space-y-3">
                <input type="hidden" name="estimate_id" value={estimate.id} />
                <div>
                  <label className="block text-xs font-medium uppercase tracking-wide text-[var(--color-muted-foreground)]">
                    Title
                  </label>
                  <input
                    name="title"
                    required
                    defaultValue={estimate.title}
                    className="mt-1 w-full rounded-md border border-[var(--color-border)] bg-[var(--color-background)] px-3 py-2 text-sm"
                  />
                </div>
                <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                  <div>
                    <label className="block text-xs font-medium uppercase tracking-wide text-[var(--color-muted-foreground)]">
                      Customer
                    </label>
                    <select
                      name="company_id"
                      defaultValue={estimate.company_id ?? ""}
                      className="mt-1 w-full rounded-md border border-[var(--color-border)] bg-[var(--color-background)] px-3 py-2 text-sm"
                    >
                      <option value="">— No customer linked —</option>
                      {(companies ?? []).map((c) => (
                        <option key={c.id} value={c.id}>
                          {c.name}
                        </option>
                      ))}
                    </select>
                  </div>
                  <div>
                    <label className="block text-xs font-medium uppercase tracking-wide text-[var(--color-muted-foreground)]">
                      Valid until
                    </label>
                    <input
                      name="valid_until"
                      type="date"
                      defaultValue={estimate.valid_until ?? ""}
                      className="mt-1 w-full rounded-md border border-[var(--color-border)] bg-[var(--color-background)] px-3 py-2 text-sm"
                    />
                  </div>
                </div>
                <div>
                  <label className="block text-xs font-medium uppercase tracking-wide text-[var(--color-muted-foreground)]">
                    Tax rate (%)
                  </label>
                  <input
                    name="tax_rate_percent"
                    type="number"
                    step="0.01"
                    min="0"
                    max="100"
                    defaultValue={taxRatePercent}
                    className="mt-1 w-32 rounded-md border border-[var(--color-border)] bg-[var(--color-background)] px-3 py-2 text-sm"
                  />
                </div>
                <div>
                  <label className="block text-xs font-medium uppercase tracking-wide text-[var(--color-muted-foreground)]">
                    Notes
                  </label>
                  <textarea
                    name="notes"
                    rows={3}
                    defaultValue={estimate.notes ?? ""}
                    className="mt-1 w-full rounded-md border border-[var(--color-border)] bg-[var(--color-background)] px-3 py-2 text-sm"
                  />
                </div>
                <div>
                  <label className="block text-xs font-medium uppercase tracking-wide text-[var(--color-muted-foreground)]">
                    Terms
                  </label>
                  <textarea
                    name="terms"
                    rows={2}
                    defaultValue={estimate.terms ?? ""}
                    className="mt-1 w-full rounded-md border border-[var(--color-border)] bg-[var(--color-background)] px-3 py-2 text-sm"
                  />
                </div>
                <div className="flex justify-end">
                  <Button type="submit">Save changes</Button>
                </div>
              </form>
            </CardContent>
          </Card>
        </div>

        <div className="space-y-6">
          <Card>
            <CardHeader>
              <CardTitle className="text-base">Totals</CardTitle>
            </CardHeader>
            <CardContent className="space-y-2 text-sm">
              <Row label="Subtotal" value={fmtMoney(estimate.subtotal_cents)} />
              <Row
                label={`Tax (${taxRatePercent.toFixed(2).replace(/\.?0+$/, "")}%)`}
                value={fmtMoney(estimate.tax_cents)}
              />
              <div className="mt-2 flex items-center justify-between border-t border-[var(--color-border)] pt-2 text-base font-semibold">
                <span>Total</span>
                <span>{fmtMoney(estimate.total_cents)}</span>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle className="text-base">Status</CardTitle>
            </CardHeader>
            <CardContent className="space-y-2">
              <StatusButtons estimateId={estimate.id} current={estimate.status} />
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle className="text-base">Danger zone</CardTitle>
            </CardHeader>
            <CardContent>
              <form action={deleteEstimate}>
                <input type="hidden" name="estimate_id" value={estimate.id} />
                <Button type="submit" variant="destructive" size="sm">
                  Delete estimate
                </Button>
              </form>
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between">
      <span className="text-[var(--color-muted-foreground)]">{label}</span>
      <span>{value}</span>
    </div>
  );
}

function StatusButtons({ estimateId, current }: { estimateId: string; current: string }) {
  const transitions: Array<{ to: string; label: string; show: boolean }> = [
    { to: "sent", label: "Mark as sent", show: current === "draft" },
    { to: "accepted", label: "Mark accepted", show: current === "sent" },
    { to: "declined", label: "Mark declined", show: current === "sent" },
    { to: "draft", label: "Reopen as draft", show: current !== "draft" },
  ];
  return (
    <div className="flex flex-col gap-2">
      {transitions
        .filter((t) => t.show)
        .map((t) => (
          <form key={t.to} action={setEstimateStatusForm}>
            <input type="hidden" name="estimate_id" value={estimateId} />
            <input type="hidden" name="status" value={t.to} />
            <Button type="submit" variant="outline" size="sm" className="w-full">
              {t.label}
            </Button>
          </form>
        ))}
    </div>
  );
}
