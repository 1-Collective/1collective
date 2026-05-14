import { getSession } from "@/lib/auth/session";
import { stopImpersonationAction } from "@/app/(admin)/admin/tenants/[id]/users/[uid]/impersonation-actions";
import { Eye } from "lucide-react";

// Sticky banner shown across both /admin and /app whenever the current operator
// has an active impersonation session. Calls Server Action to stop on click.
export async function ImpersonationBanner() {
  const session = await getSession();
  if (session.kind !== "platform_operator") return null;
  if (!session.impersonating) return null;

  const imp = session.impersonating;
  return (
    <div className="sticky top-0 z-50 flex items-center justify-between gap-4 border-b border-amber-300 bg-amber-100 px-4 py-2 text-sm text-amber-900 shadow-sm">
      <div className="flex items-center gap-2 min-w-0">
        <Eye className="h-4 w-4 flex-shrink-0" />
        <div className="truncate">
          You are viewing as{" "}
          <strong>{imp.targetUserName || imp.targetUserEmail}</strong> from{" "}
          <strong>{imp.tenantName}</strong>. Actions you take are recorded
          against your operator account.
        </div>
      </div>
      <form action={stopImpersonationAction}>
        <button
          type="submit"
          className="rounded-md border border-amber-400 bg-amber-50 px-3 py-1 text-xs font-medium hover:bg-amber-200"
        >
          Stop impersonating
        </button>
      </form>
    </div>
  );
}
