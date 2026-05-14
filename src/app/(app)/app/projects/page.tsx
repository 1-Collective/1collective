import { requireTenantUser } from "@/lib/auth/session";
import { ModuleStatus } from "@/components/app-shell/module-status";

export default async function ProjectsPage() {
  await requireTenantUser();
  return (
    <ModuleStatus
      kind="coming_soon"
      title="Projects"
      description="Pipeline, work-in-progress, change orders, and project execution tracking."
    />
  );
}
