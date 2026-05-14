"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { requirePlatformOperator } from "@/lib/auth/session";

function backWithError(
  tenantId: string,
  userId: string,
  msg: string
): never {
  redirect(
    `/admin/tenants/${tenantId}/users/${userId}?error=${encodeURIComponent(msg)}`
  );
}

export async function startImpersonationAction(formData: FormData) {
  const op = await requirePlatformOperator();
  const tenantId = String(formData.get("tenant_id") || "");
  const userId = String(formData.get("user_id") || "");
  const reason = String(formData.get("reason") || "").trim() || null;
  if (!tenantId || !userId) return;

  const admin = createAdminClient();

  // 1. Resolve the target user. Must belong to the tenant + must be a tenant user
  //    (i.e., not a platform operator — operators can't be impersonated).
  const { data: target } = await admin
    .from("users")
    .select("id, tenant_id, email")
    .eq("id", userId)
    .eq("tenant_id", tenantId)
    .maybeSingle();
  if (!target) backWithError(tenantId, userId, "User not found in this tenant.");

  // 2. Authorize: super operators can impersonate anyone; AMs only their tenants.
  if (op.operatorRole !== "super") {
    const { data: assn } = await admin
      .from("operator_tenant_assignments")
      .select("id")
      .eq("operator_id", op.userId)
      .eq("tenant_id", tenantId)
      .is("removed_at", null)
      .maybeSingle();
    if (!assn) {
      backWithError(
        tenantId,
        userId,
        "You are not assigned to this tenant."
      );
    }
  }

  // 3. End any prior in-flight session for this operator (defensive — the unique
  //    partial index would also reject the insert).
  await admin
    .from("impersonation_sessions")
    .update({ ended_at: new Date().toISOString() })
    .eq("operator_id", op.userId)
    .is("ended_at", null);

  // 4. Insert the new session.
  const { data: inserted, error: insertErr } = await admin
    .from("impersonation_sessions")
    .insert({
      operator_id: op.userId,
      target_user_id: userId,
      target_tenant_id: tenantId,
      reason,
    })
    .select("id")
    .single();
  if (insertErr || !inserted) {
    backWithError(tenantId, userId, insertErr?.message ?? "Failed to start.");
  }

  // 5. Audit trail.
  await admin.from("audit_log").insert({
    tenant_id: tenantId,
    actor_user_id: op.userId,
    actor_role: "platform_operator",
    action: "impersonation_started",
    entity_type: "user",
    entity_id: userId,
    after: { session_id: inserted.id, reason },
  });

  // 6. Force the operator's Supabase session to re-mint, so the JWT hook
  //    sees the new impersonation_sessions row and injects tenant claims.
  const supabase = await createClient();
  await supabase.auth.refreshSession();

  // 7. Land them in the tenant view.
  redirect("/app");
}

export async function stopImpersonationAction() {
  const op = await requirePlatformOperator();
  if (!op.impersonating) {
    // Nothing to stop — bounce back to admin.
    redirect("/admin");
  }

  const admin = createAdminClient();

  await admin
    .from("impersonation_sessions")
    .update({ ended_at: new Date().toISOString() })
    .eq("id", op.impersonating.sessionId);

  await admin.from("audit_log").insert({
    tenant_id: op.impersonating.tenantId,
    actor_user_id: op.userId,
    actor_role: "platform_operator",
    action: "impersonation_stopped",
    entity_type: "user",
    entity_id: op.impersonating.targetUserId,
    after: { session_id: op.impersonating.sessionId },
  });

  // Refresh session to drop the impersonation JWT claims.
  const supabase = await createClient();
  await supabase.auth.refreshSession();

  revalidatePath("/admin", "layout");
  revalidatePath("/app", "layout");
  redirect("/admin");
}
