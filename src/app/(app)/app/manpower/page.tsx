import { requireTenantUser } from "@/lib/auth/session";
import { ModuleStatus } from "@/components/app-shell/module-status";

export default async function ManpowerPage() {
  await requireTenantUser();
  return (
    <ModuleStatus
      kind="coming_soon"
      title="Manpower"
      description="Crew scheduling, timeclock, and field communication. Separate from Admin → Team, which manages user accounts and roles."
    />
  );
}
