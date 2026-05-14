import { requireTenantUser } from "@/lib/auth/session";
import { ModuleStatus } from "@/components/app-shell/module-status";

export default async function InvoicingPage() {
  await requireTenantUser();
  return (
    <ModuleStatus
      kind="coming_soon"
      title="Invoicing"
      description="Native invoices, payments, and ledger. QuickBooks Online sync configures inside this page."
    />
  );
}
