import { requireTenantUser } from "@/lib/auth/session";
import { ModuleStatus } from "@/components/app-shell/module-status";

export default async function AiPhonePage() {
  await requireTenantUser();
  return (
    <ModuleStatus
      kind="coming_soon"
      title="AI Phone"
      description="Inbound AI receptionist (Daniella) and outbound AI calls (Serana) on a single phone hub."
    />
  );
}
