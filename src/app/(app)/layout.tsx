import { redirect } from "next/navigation";
import Link from "next/link";
import { getSession } from "@/lib/auth/session";
import { createAdminClient } from "@/lib/supabase/admin";
import { Sidebar, type NavSection, type NavItem } from "@/components/app-shell/sidebar";
import {
  LayoutDashboard,
  Palette,
  Share2,
  CalendarDays,
  Users,
  Phone,
  Calculator,
  FileCheck,
  Briefcase,
  HardHat,
  TrendingUp,
  Receipt,
  FolderOpen,
  Lock,
  Plug,
  UsersRound,
  CreditCard,
  Settings,
  LogOut,
  AlertTriangle,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { differenceInDays } from "date-fns";

const ICON = "h-4 w-4";

const NAV_FULL: NavSection[] = [
  {
    section: "",
    items: [
      { label: "Dashboard", href: "/app", icon: <LayoutDashboard className={ICON} /> },
    ],
  },
  {
    section: "Marketing",
    items: [
      { label: "Branding", href: "/app/branding", icon: <Palette className={ICON} /> },
      { label: "Social", href: "/app/social", icon: <Share2 className={ICON} />, badge: "New" },
      { label: "Booking", href: "/app/booking", icon: <CalendarDays className={ICON} />, badge: "New" },
    ],
  },
  {
    section: "Sales",
    items: [
      { label: "CRM", href: "/app/crm", icon: <Users className={ICON} /> },
      { label: "AI Phone", href: "/app/ai-phone", icon: <Phone className={ICON} />, badge: "New" },
    ],
  },
  {
    section: "Delivery",
    items: [
      { label: "Estimating", href: "/app/estimating", icon: <Calculator className={ICON} /> },
      { label: "Pre-Con", href: "/app/precon", icon: <FileCheck className={ICON} /> },
      { label: "Projects", href: "/app/projects", icon: <Briefcase className={ICON} />, badge: "New" },
      { label: "Manpower", href: "/app/manpower", icon: <HardHat className={ICON} />, badge: "New" },
    ],
  },
  {
    section: "Accounting",
    items: [
      { label: "Revenue", href: "/app/revenue", icon: <TrendingUp className={ICON} /> },
      { label: "Invoicing", href: "/app/invoicing", icon: <Receipt className={ICON} />, badge: "New" },
    ],
  },
  {
    section: "Files",
    items: [
      { label: "Drive", href: "/app/drive", icon: <FolderOpen className={ICON} /> },
      { label: "Vault", href: "/app/vault", icon: <Lock className={ICON} />, badge: "New" },
    ],
  },
  {
    section: "Admin",
    items: [
      { label: "Integrations", href: "/app/integrations", icon: <Plug className={ICON} />, badge: "New" },
      { label: "Team", href: "/app/team", icon: <UsersRound className={ICON} /> },
      { label: "Billing", href: "/app/billing", icon: <CreditCard className={ICON} /> },
      { label: "Settings", href: "/app/settings", icon: <Settings className={ICON} /> },
    ],
  },
];

const NAV_FIELD: NavItem[] = [
  { label: "Dashboard", href: "/app", icon: <LayoutDashboard className={ICON} /> },
  { label: "My projects", href: "/app/projects", icon: <Briefcase className={ICON} /> },
  { label: "Files", href: "/app/drive", icon: <FolderOpen className={ICON} /> },
  { label: "Settings", href: "/app/settings", icon: <Settings className={ICON} /> },
];

export default async function AppLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const session = await getSession();
  if (session.kind === "anonymous") redirect("/login");
  if (session.kind === "platform_operator") redirect("/admin");
  if (!session.onboardingComplete && session.tenantStatus === "onboarding") {
    redirect("/onboarding");
  }
  if (session.tenantStatus === "suspended") {
    redirect("/login?error=" + encodeURIComponent("Your workspace has been suspended. Contact support."));
  }

  const admin = createAdminClient();
  const [{ data: tenant }, { data: billing }] = await Promise.all([
    admin
      .from("tenants")
      .select("name, primary_color_hex")
      .eq("id", session.tenantId)
      .single(),
    admin
      .from("tenant_billing")
      .select("billing_status, trial_ends_at, card_required_at, stripe_customer_id")
      .eq("tenant_id", session.tenantId)
      .single(),
  ]);

  const trialEndsAt = billing?.trial_ends_at ? new Date(billing.trial_ends_at) : null;
  const daysRemaining = trialEndsAt ? differenceInDays(trialEndsAt, new Date()) : null;
  const showTrialWarning =
    billing?.billing_status === "trialing" &&
    !billing?.stripe_customer_id &&
    daysRemaining !== null &&
    daysRemaining <= 30;

  const nav = session.isFieldRole ? NAV_FIELD : NAV_FULL;

  return (
    <div className="flex min-h-screen">
      <Sidebar
        title={tenant?.name ?? "Workspace"}
        subtitle="One Collective"
        items={nav}
        footer={
          <div className="space-y-1 text-xs text-[var(--color-muted-foreground)]">
            <div>{session.email}</div>
            <div className="text-[10px] uppercase tracking-wide">
              {session.roleKeys.join(", ") || "—"}
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

      <main className="flex-1 overflow-y-auto">
        {showTrialWarning && (
          <div className="border-b bg-[var(--color-warning)]/10 px-6 py-3">
            <div className="flex items-center justify-between gap-4">
              <div className="flex items-start gap-2 text-sm">
                <AlertTriangle className="mt-0.5 h-4 w-4 flex-shrink-0 text-[var(--color-warning)]" />
                <div>
                  <strong>{daysRemaining} {daysRemaining === 1 ? "day" : "days"} left in your free trial.</strong>{" "}
                  Add a credit card to keep your workspace running without
                  interruption.
                </div>
              </div>
              <Button asChild size="sm" variant="default">
                <Link href="/app/billing">Add card</Link>
              </Button>
            </div>
          </div>
        )}
        {children}
      </main>
    </div>
  );
}
