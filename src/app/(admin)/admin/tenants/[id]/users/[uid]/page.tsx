import { notFound } from "next/navigation";
import Link from "next/link";
import { requirePlatformOperator } from "@/lib/auth/session";
import { createAdminClient } from "@/lib/supabase/admin";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { formatDateTime } from "@/lib/utils";
import { ChevronLeft, Eye } from "lucide-react";
import {
  updateUserProfileAction,
  setUserPasswordAction,
  generateRandomPasswordAction,
  toggleForcePasswordResetAction,
} from "./actions";
import { startImpersonationAction } from "./impersonation-actions";

type Params = Promise<{ id: string; uid: string }>;
type Search = Promise<{ temp_password?: string; error?: string }>;

export default async function TenantUserDetailPage({
  params,
  searchParams,
}: {
  params: Params;
  searchParams: Search;
}) {
  await requirePlatformOperator();
  const { id: tenantId, uid: userId } = await params;
  const { temp_password: tempPassword, error: errorMsg } = await searchParams;
  const admin = createAdminClient();

  const { data: tenant } = await admin
    .from("tenants")
    .select("id, name, slug")
    .eq("id", tenantId)
    .maybeSingle();

  if (!tenant) notFound();

  const { data: user } = await admin
    .from("users")
    .select(
      "id, tenant_id, email, full_name, phone_e164, last_active_at, created_at, updated_at, password_reset_required"
    )
    .eq("id", userId)
    .maybeSingle();

  if (!user || user.tenant_id !== tenantId) notFound();

  // Roles
  const { data: assignments } = await admin
    .from("user_role_assignments")
    .select("roles!inner(key, name, is_field)")
    .eq("user_id", userId)
    .eq("tenant_id", tenantId);

  type RoleRow = {
    roles:
      | { key: string; name: string; is_field: boolean }
      | { key: string; name: string; is_field: boolean }[]
      | null;
  };
  const roles: { key: string; name: string; is_field: boolean }[] = [];
  for (const a of (assignments ?? []) as RoleRow[]) {
    if (Array.isArray(a.roles)) {
      a.roles.forEach((r) => roles.push(r));
    } else if (a.roles) {
      roles.push(a.roles);
    }
  }

  // Pull auth.users for email-verified + sign-in stats via admin API
  const { data: authData } = await admin.auth.admin.getUserById(userId);
  const authUser = authData?.user ?? null;

  return (
    <div className="p-8">
      <Link
        href={`/admin/tenants/${tenantId}`}
        className="inline-flex items-center gap-1 text-sm text-[var(--color-muted-foreground)] hover:text-[var(--color-foreground)]"
      >
        <ChevronLeft className="h-4 w-4" />
        {tenant.name}
      </Link>

      <div className="mt-3">
        <h1 className="text-2xl font-semibold tracking-tight">
          {user.full_name || user.email}
        </h1>
        <p className="mt-0.5 text-sm text-[var(--color-muted-foreground)]">
          {user.email}
        </p>
        <div className="mt-2 flex flex-wrap gap-1.5">
          {roles.map((r) => (
            <Badge
              key={r.key}
              variant={r.is_field ? "warning" : "secondary"}
              className="text-xs"
            >
              {r.name}
            </Badge>
          ))}
          {roles.length === 0 && (
            <Badge variant="default" className="text-xs">
              No role
            </Badge>
          )}
          {user.password_reset_required && (
            <Badge variant="destructive" className="text-xs">
              Password reset required
            </Badge>
          )}
        </div>
      </div>

      <div className="mt-4 rounded-lg border bg-[var(--color-background)] p-4">
        <form
          action={startImpersonationAction}
          className="flex flex-wrap items-end gap-3"
        >
          <input type="hidden" name="tenant_id" value={tenantId} />
          <input type="hidden" name="user_id" value={userId} />
          <div className="flex-1 min-w-[260px]">
            <Label htmlFor="reason" className="text-xs">
              View as {user.full_name || user.email}
            </Label>
            <Input
              id="reason"
              name="reason"
              placeholder="Reason (optional, audit log)"
              className="mt-1"
            />
          </div>
          <Button type="submit" size="sm">
            <Eye className="mr-1.5 h-3.5 w-3.5" />
            Start
          </Button>
        </form>
        <p className="mt-2 text-xs text-[var(--color-muted-foreground)]">
          Opens the tenant view as a super admin of {tenant.name}. A banner
          shows on every page during the session, and start/stop events are
          written to the audit log.
        </p>
      </div>

      {tempPassword && (
        <div className="mt-4 rounded-md border border-[color:var(--color-warning)] bg-[color:var(--color-warning-muted,#fef3c7)] p-4">
          <div className="text-sm font-medium">
            Temporary password generated
          </div>
          <p className="mt-1 text-xs text-[var(--color-muted-foreground)]">
            Copy this now and share it with the user securely. It will not be
            shown again. The user will be required to set a new password on
            their next sign-in.
          </p>
          <code className="mt-2 block break-all rounded bg-[var(--color-background)] px-2 py-1 text-sm font-mono">
            {tempPassword}
          </code>
        </div>
      )}
      {errorMsg && (
        <div className="mt-4 rounded-md border border-[color:var(--color-destructive)] bg-[color:var(--color-destructive-muted,#fee2e2)] p-3 text-sm">
          {errorMsg}
        </div>
      )}

      <div className="mt-6 grid gap-6 lg:grid-cols-2">
        {/* Profile */}
        <Card>
          <CardHeader>
            <CardTitle className="text-sm font-medium uppercase tracking-wide">
              Profile
            </CardTitle>
          </CardHeader>
          <CardContent>
            <form action={updateUserProfileAction} className="space-y-4">
              <input type="hidden" name="tenant_id" value={tenantId} />
              <input type="hidden" name="user_id" value={userId} />
              <div>
                <Label htmlFor="full_name">Full name</Label>
                <Input
                  id="full_name"
                  name="full_name"
                  defaultValue={user.full_name ?? ""}
                />
              </div>
              <div>
                <Label htmlFor="email">Email</Label>
                <Input
                  id="email"
                  name="email"
                  type="email"
                  defaultValue={user.email}
                />
                <p className="mt-1 text-xs text-[var(--color-muted-foreground)]">
                  Updates the address in both the app profile and Supabase Auth.
                </p>
              </div>
              <div>
                <Label htmlFor="phone_e164">Phone (E.164)</Label>
                <Input
                  id="phone_e164"
                  name="phone_e164"
                  defaultValue={user.phone_e164 ?? ""}
                  placeholder="+12145550101"
                />
              </div>
              <Button type="submit" size="sm">
                Save profile
              </Button>
            </form>
          </CardContent>
        </Card>

        {/* Password */}
        <Card>
          <CardHeader>
            <CardTitle className="text-sm font-medium uppercase tracking-wide">
              Password
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-5">
            <form action={setUserPasswordAction} className="space-y-3">
              <input type="hidden" name="tenant_id" value={tenantId} />
              <input type="hidden" name="user_id" value={userId} />
              <div>
                <Label htmlFor="new_password">Set password manually</Label>
                <Input
                  id="new_password"
                  name="new_password"
                  type="text"
                  minLength={8}
                  placeholder="At least 8 characters"
                  autoComplete="off"
                  required
                />
              </div>
              <div className="flex items-center gap-2">
                <input
                  id="force_reset_after"
                  name="force_reset_after"
                  type="checkbox"
                  defaultChecked
                  className="h-4 w-4"
                />
                <Label
                  htmlFor="force_reset_after"
                  className="text-xs font-normal"
                >
                  Require user to set a new password on next sign-in
                </Label>
              </div>
              <Button type="submit" size="sm">
                Set password
              </Button>
            </form>

            <div className="border-t pt-4">
              <form action={generateRandomPasswordAction}>
                <input type="hidden" name="tenant_id" value={tenantId} />
                <input type="hidden" name="user_id" value={userId} />
                <Button type="submit" size="sm" variant="outline">
                  Generate random password
                </Button>
              </form>
              <p className="mt-1 text-xs text-[var(--color-muted-foreground)]">
                Generates a strong random password and displays it once. User
                will be required to change it on next sign-in.
              </p>
            </div>

            <div className="border-t pt-4">
              <form action={toggleForcePasswordResetAction}>
                <input type="hidden" name="tenant_id" value={tenantId} />
                <input type="hidden" name="user_id" value={userId} />
                <input
                  type="hidden"
                  name="value"
                  value={user.password_reset_required ? "false" : "true"}
                />
                <Button type="submit" size="sm" variant="outline">
                  {user.password_reset_required
                    ? "Clear password-reset flag"
                    : "Require password reset on next sign-in"}
                </Button>
              </form>
            </div>
          </CardContent>
        </Card>

        {/* Roles + auth info */}
        <Card className="lg:col-span-2">
          <CardHeader>
            <CardTitle className="text-sm font-medium uppercase tracking-wide">
              Auth + Activity
            </CardTitle>
          </CardHeader>
          <CardContent>
            <dl className="grid grid-cols-2 gap-x-4 gap-y-2 text-sm lg:grid-cols-3">
              <dt className="text-[var(--color-muted-foreground)]">User ID</dt>
              <dd className="lg:col-span-2 font-mono text-xs">{user.id}</dd>
              <dt className="text-[var(--color-muted-foreground)]">
                Email confirmed
              </dt>
              <dd className="lg:col-span-2">
                {authUser?.email_confirmed_at
                  ? formatDateTime(authUser.email_confirmed_at)
                  : "Pending"}
              </dd>
              <dt className="text-[var(--color-muted-foreground)]">
                Last sign-in
              </dt>
              <dd className="lg:col-span-2">
                {authUser?.last_sign_in_at
                  ? formatDateTime(authUser.last_sign_in_at)
                  : "Never"}
              </dd>
              <dt className="text-[var(--color-muted-foreground)]">
                Created
              </dt>
              <dd className="lg:col-span-2">{formatDateTime(user.created_at)}</dd>
              <dt className="text-[var(--color-muted-foreground)]">
                Last active in-app
              </dt>
              <dd className="lg:col-span-2">
                {user.last_active_at
                  ? formatDateTime(user.last_active_at)
                  : "Never"}
              </dd>
            </dl>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
