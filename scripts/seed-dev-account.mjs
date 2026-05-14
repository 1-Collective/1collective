// One-shot dev account seeder. Provisions a confirmed super-admin user
// + a fresh tenant + permissions + onboarding row, the same way the
// /signup server action does. Idempotent: if the email already exists,
// resets its password and ensures it's confirmed.
//
// Run: node scripts/seed-dev-account.mjs <email> <password> "<Company Name>"

import { createClient } from "@supabase/supabase-js";
import { randomUUID } from "node:crypto";

const [, , emailArg, passwordArg, companyArg] = process.argv;
const email = (emailArg || "dev@1collective.local").toLowerCase();
const password = passwordArg || "DevPassword123!";
const companyName = companyArg || "Dev Workspace";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !key) {
  console.error("Missing NEXT_PUBLIC_SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
  process.exit(1);
}

const admin = createClient(url, key, { auth: { persistSession: false } });

function slugify(s) {
  return s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 48);
}

async function findOrCreateUser() {
  // List existing users; service role required.
  const { data: list } = await admin.auth.admin.listUsers({ page: 1, perPage: 200 });
  const existing = list?.users?.find((u) => (u.email || "").toLowerCase() === email);
  if (existing) {
    await admin.auth.admin.updateUserById(existing.id, {
      password,
      email_confirm: true,
    });
    console.log(`User exists, password reset: ${email} (id ${existing.id})`);
    return existing.id;
  }
  const { data: created, error } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { full_name: "Dev Owner" },
  });
  if (error) throw error;
  console.log(`User created: ${email} (id ${created.user.id})`);
  return created.user.id;
}

async function ensureTenant(userId) {
  const { data: existingMembership } = await admin
    .from("user_tenant_memberships")
    .select("tenant_id, tenants(name, slug, status)")
    .eq("user_id", userId)
    .maybeSingle();
  if (existingMembership?.tenant_id) {
    console.log(`User already member of tenant ${existingMembership.tenant_id}`);
    return existingMembership.tenant_id;
  }

  const baseSlug = slugify(companyName) || `dev-${randomUUID().slice(0, 6)}`;
  let slug = baseSlug;
  let suffix = 0;
  while (true) {
    const { data: collide } = await admin.from("tenants").select("id").eq("slug", slug).maybeSingle();
    if (!collide) break;
    suffix += 1;
    slug = `${baseSlug}-${suffix}`;
  }

  const { data: tenant, error } = await admin
    .from("tenants")
    .insert({ name: companyName, slug, status: "active" })
    .select("id")
    .single();
  if (error) throw error;
  console.log(`Tenant created: ${tenant.id} (slug=${slug})`);

  await admin.from("users").upsert(
    { id: userId, tenant_id: tenant.id, email, full_name: "Dev Owner" },
    { onConflict: "id" }
  );
  await admin.from("user_tenant_memberships").insert({
    user_id: userId,
    tenant_id: tenant.id,
    is_default: true,
  });

  // Provision per-tenant copies of system roles + permissions.
  const { data: systemRoles } = await admin
    .from("roles")
    .select("id, key, name, description, is_system, is_field, max_seats")
    .is("tenant_id", null);

  if (systemRoles && systemRoles.length > 0) {
    const payload = systemRoles.map((r) => ({
      tenant_id: tenant.id,
      key: r.key,
      name: r.name,
      description: r.description,
      is_system: r.is_system,
      is_field: r.is_field,
      max_seats: r.max_seats,
    }));
    const { data: newRoles } = await admin.from("roles").insert(payload).select("id, key");
    if (newRoles) {
      const keyToNew = new Map(newRoles.map((r) => [r.key, r.id]));
      const oldIds = systemRoles.map((r) => r.id);
      const { data: oldPerms } = await admin
        .from("role_permissions")
        .select("role_id, module, can_read, can_write, can_edit, can_delete")
        .in("role_id", oldIds);
      if (oldPerms) {
        const newPerms = oldPerms
          .map((p) => {
            const oldRole = systemRoles.find((r) => r.id === p.role_id);
            const newId = oldRole ? keyToNew.get(oldRole.key) : null;
            return newId
              ? {
                  role_id: newId,
                  module: p.module,
                  can_read: p.can_read,
                  can_write: p.can_write,
                  can_edit: p.can_edit,
                  can_delete: p.can_delete,
                }
              : null;
          })
          .filter(Boolean);
        if (newPerms.length > 0) await admin.from("role_permissions").insert(newPerms);
      }
      const superAdminId = keyToNew.get("super_admin");
      if (superAdminId) {
        await admin.from("user_role_assignments").insert({
          user_id: userId,
          role_id: superAdminId,
          tenant_id: tenant.id,
          assigned_by: userId,
        });
      }
    }
  }

  // Skip trial billing + onboarding rows; status='active' bypasses onboarding redirect.
  await admin.from("tenant_billing").upsert(
    {
      tenant_id: tenant.id,
      billing_mode: "free_forever",
      billing_status: "free_forever",
    },
    { onConflict: "tenant_id" }
  );
  await admin.from("onboarding_progress").upsert(
    {
      tenant_id: tenant.id,
      current_step_key: "complete",
      completed_steps: ["company_info", "branding", "revenue", "complete"],
      step_state: {},
      completed_at: new Date().toISOString(),
    },
    { onConflict: "tenant_id" }
  );

  return tenant.id;
}

const userId = await findOrCreateUser();
const tenantId = await ensureTenant(userId);

console.log("\n========================================");
console.log("DEV ACCOUNT READY");
console.log("========================================");
console.log(`URL:      http://localhost:5000/login`);
console.log(`Email:    ${email}`);
console.log(`Password: ${password}`);
console.log(`Tenant:   ${tenantId}`);
console.log("========================================\n");
