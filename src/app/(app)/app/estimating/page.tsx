import type { Metadata } from "next";
import Link from "next/link";
import { requireTenantUser } from "@/lib/auth/session";
import { createAdminClient } from "@/lib/supabase/admin";
import { isModuleEnabled } from "@/foundational/registry";
import { ModuleStatus } from "@/components/app-shell/module-status";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { formatDate } from "@/lib/utils";
import { centsToDollars } from "@/lib/estimating/schemas";

export const metadata: Metadata = { title: "Estimating" };

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

export default async function EstimatingPage() {
  const session = await requireTenantUser();

  if (!isModuleEnabled("estimating")) {
    return (
      <ModuleStatus
        kind="coming_soon"
        title="Estimating"
        description="Build estimates from your unit-price catalog. Convert won estimates into projects in one click."
      />
    );
  }

  const admin = createAdminClient();
  const { data: estimates } = await admin
    .from("cc_estimates")
    .select("id, estimate_number, title, status, total_cents, valid_until, created_at")
    .eq("tenant_id", session.tenantId)
    .is("deleted_at", null)
    .order("created_at", { ascending: false });

  const rows = estimates ?? [];
  const open = rows.filter((r) => r.status === "draft" || r.status === "sent");
  const won = rows.filter((r) => r.status === "accepted");
  const pipelineCents = open.reduce((s, r) => s + Number(r.total_cents), 0);
  const wonCents = won.reduce((s, r) => s + Number(r.total_cents), 0);
  const closedCount = won.length + rows.filter((r) => r.status === "declined").length;
  const winRate = closedCount === 0 ? null : Math.round((won.length / closedCount) * 100);
  const avgTicket = won.length === 0 ? null : Math.round(wonCents / won.length);

  const stats = [
    { label: "Open estimates", value: String(open.length) },
    { label: "Pipeline value", value: fmtMoney(pipelineCents) },
    { label: "Win rate (90d)", value: winRate === null ? "—" : `${winRate}%` },
    { label: "Avg ticket", value: avgTicket === null ? "—" : fmtMoney(avgTicket) },
  ];

  return (
    <div className="p-8">
      <div className="flex items-start justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Estimating</h1>
          <p className="mt-1 text-sm text-[var(--color-muted-foreground)]">
            Build estimates with itemized line items, send branded PDFs, and track wins.
          </p>
        </div>
        <Button asChild>
          <Link href="/app/estimating/new">New estimate</Link>
        </Button>
      </div>

      <div className="mt-6 grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
        {stats.map((s) => (
          <Card key={s.label}>
            <CardContent className="py-4">
              <div className="text-xs uppercase tracking-wide text-[var(--color-muted-foreground)]">
                {s.label}
              </div>
              <div className="mt-1 text-2xl font-semibold tracking-tight">{s.value}</div>
            </CardContent>
          </Card>
        ))}
      </div>

      <div className="mt-6 space-y-3">
        {rows.length === 0 ? (
          <Card>
            <CardContent className="py-12 text-center text-sm text-[var(--color-muted-foreground)]">
              No estimates yet. Click <span className="font-medium">New estimate</span> to create your first one.
            </CardContent>
          </Card>
        ) : (
          rows.map((r) => (
            <Card key={r.id}>
              <CardContent className="flex items-center justify-between gap-4 py-4">
                <div className="min-w-0">
                  <div className="flex items-center gap-2">
                    <Link
                      href={`/app/estimating/${r.id}`}
                      className="truncate font-medium hover:underline"
                    >
                      {r.title}
                    </Link>
                    <Badge variant={STATUS_VARIANT[r.status] ?? "secondary"}>{r.status}</Badge>
                  </div>
                  <div className="mt-1 text-xs text-[var(--color-muted-foreground)]">
                    {r.estimate_number} · created {formatDate(r.created_at)}
                    {r.valid_until ? ` · valid until ${formatDate(r.valid_until)}` : ""}
                  </div>
                </div>
                <div className="shrink-0 text-right">
                  <div className="text-lg font-semibold">{fmtMoney(Number(r.total_cents))}</div>
                </div>
              </CardContent>
            </Card>
          ))
        )}
      </div>
    </div>
  );
}
