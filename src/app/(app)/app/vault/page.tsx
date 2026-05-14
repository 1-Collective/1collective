import { requireTenantUser } from "@/lib/auth/session";
import { ModuleStatus } from "@/components/app-shell/module-status";

export default async function VaultPage() {
  await requireTenantUser();
  return (
    <ModuleStatus
      kind="coming_soon"
      title="Vault"
      description="Encrypted, tenant-scoped document storage on Supabase Storage. Separate from Drive, which is for shared/synced files."
    />
  );
}
