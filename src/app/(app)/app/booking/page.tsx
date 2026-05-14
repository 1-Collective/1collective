import { requireTenantUser } from "@/lib/auth/session";
import { ModuleStatus } from "@/components/app-shell/module-status";

export default async function BookingPage() {
  await requireTenantUser();
  return (
    <ModuleStatus
      kind="coming_soon"
      title="Booking"
      description="Public booking widget for your website plus the inbound submissions inbox. Honors Google Calendar availability when the Google integration is connected."
    />
  );
}
