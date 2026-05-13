import { getSession } from "@/lib/auth/session";
import { Sidebar, type NavItem } from "@/components/app-shell/sidebar";
import {
  LayoutDashboard,
  Building2,
  TicketIcon,
  ListChecks,
  BookOpen,
  Folders,
  LogOut,
} from "lucide-react";
import { Button } from "@/components/ui/button";

const ICON = "h-4 w-4";
const NAV: NavItem[] = [
  { label: "Overview", href: "/admin", icon: <LayoutDashboard className={ICON} /> },
  { label: "Tenants", href: "/admin/tenants", icon: <Building2 className={ICON} /> },
  { label: "Invite links", href: "/admin/invite-links", icon: <TicketIcon className={ICON} /> },
  { label: "Contract checklist", href: "/admin/checklist", icon: <ListChecks className={ICON} /> },
  { label: "Clause library", href: "/admin/clauses", icon: <BookOpen className={ICON} /> },
  { label: "Folder templates", href: "/admin/templates", icon: <Folders className={ICON} /> },
];

export default async function AdminLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const session = await getSession();

  // Render bare children for the login page (unauthenticated).
  // Authenticated pages call requirePlatformOperator() to enforce access.
  if (session.kind !== "platform_operator") {
    return <>{children}</>;
  }

  return (
    <div className="flex min-h-screen">
      <Sidebar
        title="Admin Portal"
        subtitle="One Collective"
        items={NAV}
        footer={
          <div className="space-y-1 text-xs text-[var(--color-muted-foreground)]">
            <div className="truncate">{session.email}</div>
            <div className="text-[10px] uppercase tracking-wide">
              {session.operatorRole}
            </div>
            <form action="/logout" method="post">
              <Button
                type="submit"
                variant="ghost"
                size="sm"
                className="-ml-2 mt-1 h-auto px-2 py-1 text-xs"
              >
                <LogOut className="mr-1.5 h-3 w-3" />
                Sign out
              </Button>
            </form>
          </div>
        }
      />
      <main className="flex-1 overflow-y-auto">{children}</main>
    </div>
  );
}
