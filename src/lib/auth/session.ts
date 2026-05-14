import "server-only";
import { cache } from "react";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";

export type ImpersonationContext = {
  sessionId: string;
  startedAt: string;
  tenantId: string;
  tenantSlug: string;
  tenantName: string;
  targetUserId: string;
  targetUserEmail: string;
  targetUserName: string | null;
};

export type SessionContext =
  | { kind: "anonymous" }
  | {
      kind: "tenant_user";
      userId: string;
      email: string;
      tenantId: string;
      tenantSlug: string;
      tenantStatus: string;
      roleKeys: string[];
      isFieldRole: boolean;
      onboardingComplete: boolean;
      passwordResetRequired: boolean;
    }
  | {
      kind: "platform_operator";
      userId: string;
      email: string;
      operatorRole: string;
      passwordResetRequired: boolean;
      impersonating: ImpersonationContext | null;
    };

export const getSession = cache(async (): Promise<SessionContext> => {
  const supabase = await createClient();
  const { data: authData } = await supabase.auth.getUser();
  const authUser = authData.user;
  if (!authUser) return { kind: "anonymous" };

  // Admin client to look up operator vs tenant role membership (bypasses RLS for this lookup).
  const admin = createAdminClient();

  const { data: operator } = await admin
    .from("platform_operators")
    .select("id, email, operator_role, password_reset_required")
    .eq("id", authUser.id)
    .maybeSingle();

  if (operator) {
    // Look up active impersonation, if any
    const { data: imp } = await admin
      .from("impersonation_sessions")
      .select(
        "id, started_at, target_user_id, target_tenant_id, tenants ( slug, name ), users ( email, full_name )"
      )
      .eq("operator_id", operator.id)
      .is("ended_at", null)
      .order("started_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    type ImpRow = {
      id: string;
      started_at: string;
      target_user_id: string;
      target_tenant_id: string;
      tenants:
        | { slug: string; name: string }
        | { slug: string; name: string }[]
        | null;
      users:
        | { email: string; full_name: string | null }
        | { email: string; full_name: string | null }[]
        | null;
    } | null;

    const impTyped = imp as ImpRow;
    let impersonating: ImpersonationContext | null = null;
    if (impTyped) {
      const tenant = Array.isArray(impTyped.tenants)
        ? impTyped.tenants[0]
        : impTyped.tenants;
      const target = Array.isArray(impTyped.users)
        ? impTyped.users[0]
        : impTyped.users;
      if (tenant && target) {
        impersonating = {
          sessionId: impTyped.id,
          startedAt: impTyped.started_at,
          tenantId: impTyped.target_tenant_id,
          tenantSlug: tenant.slug,
          tenantName: tenant.name,
          targetUserId: impTyped.target_user_id,
          targetUserEmail: target.email,
          targetUserName: target.full_name,
        };
      }
    }

    return {
      kind: "platform_operator",
      userId: operator.id,
      email: operator.email,
      operatorRole: operator.operator_role,
      passwordResetRequired: !!operator.password_reset_required,
      impersonating,
    };
  }

  const { data: profile } = await admin
    .from("users")
    .select("id, email, tenant_id, password_reset_required")
    .eq("id", authUser.id)
    .maybeSingle();

  if (!profile || !profile.tenant_id) {
    return { kind: "anonymous" };
  }

  const [{ data: tenant }, { data: assignments }, { data: onboarding }] =
    await Promise.all([
      admin
        .from("tenants")
        .select("id, slug, status")
        .eq("id", profile.tenant_id)
        .maybeSingle(),
      admin
        .from("user_role_assignments")
        .select("role_id, roles!inner(key, is_field)")
        .eq("user_id", authUser.id)
        .eq("tenant_id", profile.tenant_id),
      admin
        .from("onboarding_progress")
        .select("completed_at")
        .eq("tenant_id", profile.tenant_id)
        .maybeSingle(),
    ]);

  if (!tenant) return { kind: "anonymous" };

  type RoleRow = { roles: { key: string; is_field: boolean } | { key: string; is_field: boolean }[] };
  const roleKeys: string[] = [];
  let isFieldRole = false;
  for (const a of (assignments ?? []) as RoleRow[]) {
    const r = Array.isArray(a.roles) ? a.roles[0] : a.roles;
    if (r) {
      roleKeys.push(r.key);
      if (r.is_field) isFieldRole = true;
    }
  }

  return {
    kind: "tenant_user",
    userId: profile.id,
    email: profile.email,
    tenantId: tenant.id,
    tenantSlug: tenant.slug,
    tenantStatus: tenant.status,
    roleKeys,
    isFieldRole,
    onboardingComplete: !!onboarding?.completed_at,
    passwordResetRequired: !!profile.password_reset_required,
  };
});

export async function requireTenantUser() {
  const session = await getSession();
  if (session.kind !== "tenant_user") {
    throw new Error("Unauthorized: tenant user required");
  }
  return session;
}

export async function requirePlatformOperator() {
  const session = await getSession();
  if (session.kind !== "platform_operator") {
    throw new Error("Unauthorized: platform operator required");
  }
  return session;
}
