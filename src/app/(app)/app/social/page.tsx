import { requireTenantUser } from "@/lib/auth/session";
import { ModuleStatus } from "@/components/app-shell/module-status";

export default async function SocialPage() {
  await requireTenantUser();
  return (
    <ModuleStatus
      kind="coming_soon"
      title="Social"
      description="Compose and schedule posts across Facebook, Instagram, and Google Business Profile. Amber AI assistance lights up automatically once the AI core is configured."
    />
  );
}
