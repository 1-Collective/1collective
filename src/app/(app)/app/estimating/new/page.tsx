import type { Metadata } from "next";
import { redirect } from "next/navigation";
import Link from "next/link";
import { requireTenantUser } from "@/lib/auth/session";
import { createAdminClient } from "@/lib/supabase/admin";
import { isModuleEnabled } from "@/foundational/registry";
import { ModuleStatus } from "@/components/app-shell/module-status";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { createEstimate } from "@/lib/estimating/actions";

export const metadata: Metadata = { title: "New estimate" };

export default async function NewEstimatePage() {
  const session = await requireTenantUser();

  if (!isModuleEnabled("estimating")) {
    return (
      <ModuleStatus
        kind="coming_soon"
        title="Estimating"
        description="Module not yet enabled."
      />
    );
  }

  const admin = createAdminClient();
  const { data: companies } = await admin
    .from("companies")
    .select("id, name")
    .eq("tenant_id", session.tenantId)
    .is("deleted_at", null)
    .order("name");

  async function handleCreate(formData: FormData) {
    "use server";
    const result = await createEstimate(formData);
    if (!result.ok) {
      throw new Error(result.error);
    }
    redirect(`/app/estimating/${result.data.estimate_id}`);
  }

  return (
    <div className="p-8">
      <div className="mb-6 flex items-center justify-between">
        <h1 className="text-2xl font-semibold tracking-tight">New estimate</h1>
        <Button variant="ghost" asChild>
          <Link href="/app/estimating">Cancel</Link>
        </Button>
      </div>

      <Card className="max-w-2xl">
        <CardHeader>
          <CardTitle className="text-base">Estimate details</CardTitle>
        </CardHeader>
        <CardContent>
          <form action={handleCreate} className="space-y-4">
            <div>
              <label className="block text-sm font-medium" htmlFor="title">
                Title
              </label>
              <input
                id="title"
                name="title"
                required
                maxLength={200}
                placeholder="Roof replacement — 142 Elm St"
                className="mt-1 w-full rounded-md border border-[var(--color-border)] bg-[var(--color-background)] px-3 py-2 text-sm"
              />
            </div>

            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <div>
                <label className="block text-sm font-medium" htmlFor="company_id">
                  Customer
                </label>
                <select
                  id="company_id"
                  name="company_id"
                  className="mt-1 w-full rounded-md border border-[var(--color-border)] bg-[var(--color-background)] px-3 py-2 text-sm"
                  defaultValue=""
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
                <label className="block text-sm font-medium" htmlFor="valid_until">
                  Valid until
                </label>
                <input
                  id="valid_until"
                  name="valid_until"
                  type="date"
                  className="mt-1 w-full rounded-md border border-[var(--color-border)] bg-[var(--color-background)] px-3 py-2 text-sm"
                />
              </div>
            </div>

            <div>
              <label className="block text-sm font-medium" htmlFor="tax_rate_percent">
                Tax rate (%)
              </label>
              <input
                id="tax_rate_percent"
                name="tax_rate_percent"
                type="number"
                step="0.01"
                min="0"
                max="100"
                defaultValue="0"
                className="mt-1 w-32 rounded-md border border-[var(--color-border)] bg-[var(--color-background)] px-3 py-2 text-sm"
              />
            </div>

            <div>
              <label className="block text-sm font-medium" htmlFor="notes">
                Notes
              </label>
              <textarea
                id="notes"
                name="notes"
                rows={3}
                maxLength={4000}
                className="mt-1 w-full rounded-md border border-[var(--color-border)] bg-[var(--color-background)] px-3 py-2 text-sm"
              />
            </div>

            <div>
              <label className="block text-sm font-medium" htmlFor="terms">
                Terms
              </label>
              <textarea
                id="terms"
                name="terms"
                rows={2}
                maxLength={4000}
                className="mt-1 w-full rounded-md border border-[var(--color-border)] bg-[var(--color-background)] px-3 py-2 text-sm"
              />
            </div>

            <div className="flex justify-end">
              <Button type="submit">Create estimate</Button>
            </div>
          </form>
        </CardContent>
      </Card>
    </div>
  );
}
