-- One Collective: seed data for system roles + initial admin reference data.
-- System roles are template definitions copied into each tenant on creation.

-- ============================================================
-- SYSTEM ROLE TEMPLATES
-- These rows have tenant_id = NULL, marking them as templates.
-- Tenant provisioning copies them into per-tenant rows.
-- ============================================================

insert into roles (id, tenant_id, key, name, description, is_system, is_field, max_seats) values
  (gen_random_uuid(), null, 'super_admin', 'Super Admin',
   'Full platform access including billing. Two seats per tenant for redundancy.',
   true, false, 2),
  (gen_random_uuid(), null, 'owner',       'Owner / Executive',
   'Full admin access to all modules and data. No billing access unless also Super Admin.',
   true, false, null),
  (gen_random_uuid(), null, 'admin',       'Admin',
   'Administrative access to all modules except billing.',
   true, false, null),
  (gen_random_uuid(), null, 'bookkeeper',  'Bookkeeper / Accountant',
   'Read access to financial data, CRM activity, and contracts. Billing access requires explicit Super Admin grant.',
   true, false, null),
  (gen_random_uuid(), null, 'estimator',   'Estimator',
   'Access to CRM, projects in bidding stages, and Pre-Con. No billing.',
   true, false, null),
  (gen_random_uuid(), null, 'pm',          'Project Manager',
   'Full access to projects assigned to them as PM, plus CRM. No billing.',
   true, false, null),
  (gen_random_uuid(), null, 'office',      'Office Staff',
   'CRM and project administrative access. No financial detail visibility.',
   true, false, null),
  (gen_random_uuid(), null, 'field_foreman', 'Field Foreman',
   'Field role: scoped to assigned projects only. Sees pre-job checklist, project files, and project details (no financials by default).',
   true, true, null);

-- ============================================================
-- DEFAULT PERMISSIONS PER SYSTEM ROLE
-- Format: (role_key, module, R, W, E, D)
-- ============================================================

-- super_admin: full on everything including billing
insert into role_permissions (role_id, module, can_read, can_write, can_edit, can_delete)
select r.id, m::module_key, true, true, true, true
from roles r
cross join (values ('dashboard'),('crm'),('precon'),('revenue'),('drive'),
                   ('estimating'),('branding'),('team'),('billing'),('settings')) as mods(m)
where r.tenant_id is null and r.key = 'super_admin';

-- owner: full on everything EXCEPT billing
insert into role_permissions (role_id, module, can_read, can_write, can_edit, can_delete)
select r.id, m::module_key,
  true, true, true, true
from roles r
cross join (values ('dashboard'),('crm'),('precon'),('revenue'),('drive'),
                   ('estimating'),('branding'),('team'),('settings')) as mods(m)
where r.tenant_id is null and r.key = 'owner';

insert into role_permissions (role_id, module, can_read, can_write, can_edit, can_delete)
select r.id, 'billing'::module_key, false, false, false, false
from roles r where r.tenant_id is null and r.key = 'owner';

-- admin: full on everything EXCEPT billing (same as owner; distinction is policy/seats)
insert into role_permissions (role_id, module, can_read, can_write, can_edit, can_delete)
select r.id, m::module_key, true, true, true, true
from roles r
cross join (values ('dashboard'),('crm'),('precon'),('revenue'),('drive'),
                   ('estimating'),('branding'),('team'),('settings')) as mods(m)
where r.tenant_id is null and r.key = 'admin';
insert into role_permissions (role_id, module, can_read, can_write, can_edit, can_delete)
select r.id, 'billing'::module_key, false, false, false, false
from roles r where r.tenant_id is null and r.key = 'admin';

-- bookkeeper: read CRM/precon/revenue, edit revenue; no billing by default (grant required)
insert into role_permissions (role_id, module, can_read, can_write, can_edit, can_delete) values
  ((select id from roles where tenant_id is null and key='bookkeeper'), 'dashboard', true, false, false, false),
  ((select id from roles where tenant_id is null and key='bookkeeper'), 'crm',       true, false, false, false),
  ((select id from roles where tenant_id is null and key='bookkeeper'), 'precon',    true, false, false, false),
  ((select id from roles where tenant_id is null and key='bookkeeper'), 'revenue',   true, true, true, false),
  ((select id from roles where tenant_id is null and key='bookkeeper'), 'drive',     true, false, false, false),
  ((select id from roles where tenant_id is null and key='bookkeeper'), 'estimating', false, false, false, false),
  ((select id from roles where tenant_id is null and key='bookkeeper'), 'branding',  true, false, false, false),
  ((select id from roles where tenant_id is null and key='bookkeeper'), 'team',      true, false, false, false),
  ((select id from roles where tenant_id is null and key='bookkeeper'), 'billing',   false, false, false, false),
  ((select id from roles where tenant_id is null and key='bookkeeper'), 'settings',  true, false, false, false);

-- estimator: full CRM, precon, drive; read estimating (when built)
insert into role_permissions (role_id, module, can_read, can_write, can_edit, can_delete) values
  ((select id from roles where tenant_id is null and key='estimator'), 'dashboard',  true, false, false, false),
  ((select id from roles where tenant_id is null and key='estimator'), 'crm',        true, true, true, false),
  ((select id from roles where tenant_id is null and key='estimator'), 'precon',     true, true, true, false),
  ((select id from roles where tenant_id is null and key='estimator'), 'revenue',    false, false, false, false),
  ((select id from roles where tenant_id is null and key='estimator'), 'drive',      true, true, true, false),
  ((select id from roles where tenant_id is null and key='estimator'), 'estimating', true, true, true, false),
  ((select id from roles where tenant_id is null and key='estimator'), 'branding',   true, false, false, false),
  ((select id from roles where tenant_id is null and key='estimator'), 'team',       true, false, false, false),
  ((select id from roles where tenant_id is null and key='estimator'), 'billing',    false, false, false, false),
  ((select id from roles where tenant_id is null and key='estimator'), 'settings',   true, false, false, false);

-- pm: full on projects/CRM/precon/drive; no revenue/billing
insert into role_permissions (role_id, module, can_read, can_write, can_edit, can_delete) values
  ((select id from roles where tenant_id is null and key='pm'), 'dashboard', true, false, false, false),
  ((select id from roles where tenant_id is null and key='pm'), 'crm',       true, true, true, false),
  ((select id from roles where tenant_id is null and key='pm'), 'precon',    true, true, true, false),
  ((select id from roles where tenant_id is null and key='pm'), 'revenue',   false, false, false, false),
  ((select id from roles where tenant_id is null and key='pm'), 'drive',     true, true, true, false),
  ((select id from roles where tenant_id is null and key='pm'), 'estimating', true, false, false, false),
  ((select id from roles where tenant_id is null and key='pm'), 'branding',  true, false, false, false),
  ((select id from roles where tenant_id is null and key='pm'), 'team',      true, false, false, false),
  ((select id from roles where tenant_id is null and key='pm'), 'billing',   false, false, false, false),
  ((select id from roles where tenant_id is null and key='pm'), 'settings',  true, false, false, false);

-- office: read everything (except billing/revenue), edit CRM
insert into role_permissions (role_id, module, can_read, can_write, can_edit, can_delete) values
  ((select id from roles where tenant_id is null and key='office'), 'dashboard', true, false, false, false),
  ((select id from roles where tenant_id is null and key='office'), 'crm',       true, true, true, false),
  ((select id from roles where tenant_id is null and key='office'), 'precon',    true, false, false, false),
  ((select id from roles where tenant_id is null and key='office'), 'revenue',   false, false, false, false),
  ((select id from roles where tenant_id is null and key='office'), 'drive',     true, true, false, false),
  ((select id from roles where tenant_id is null and key='office'), 'estimating', true, false, false, false),
  ((select id from roles where tenant_id is null and key='office'), 'branding',  true, false, false, false),
  ((select id from roles where tenant_id is null and key='office'), 'team',      true, false, false, false),
  ((select id from roles where tenant_id is null and key='office'), 'billing',   false, false, false, false),
  ((select id from roles where tenant_id is null and key='office'), 'settings',  true, false, false, false);

-- field_foreman: drive (project files), pre-job checklist (read+complete) on assigned projects only.
-- CRM/precon/revenue/billing all DENIED; data-layer enforcement adds row scoping for projects.
insert into role_permissions (role_id, module, can_read, can_write, can_edit, can_delete) values
  ((select id from roles where tenant_id is null and key='field_foreman'), 'dashboard', true, false, false, false),
  ((select id from roles where tenant_id is null and key='field_foreman'), 'crm',       false, false, false, false),
  ((select id from roles where tenant_id is null and key='field_foreman'), 'precon',    true, true, false, false),  -- pre-job checklist only
  ((select id from roles where tenant_id is null and key='field_foreman'), 'revenue',   false, false, false, false),
  ((select id from roles where tenant_id is null and key='field_foreman'), 'drive',     true, false, false, false),
  ((select id from roles where tenant_id is null and key='field_foreman'), 'estimating', false, false, false, false),
  ((select id from roles where tenant_id is null and key='field_foreman'), 'branding',  false, false, false, false),
  ((select id from roles where tenant_id is null and key='field_foreman'), 'team',      false, false, false, false),
  ((select id from roles where tenant_id is null and key='field_foreman'), 'billing',   false, false, false, false),
  ((select id from roles where tenant_id is null and key='field_foreman'), 'settings',  false, false, false, false);

-- ============================================================
-- PLACEHOLDER FOLDER TEMPLATES (Accounting / Operations / HR)
-- Marked is_placeholder = true; trade-specific templates added later.
-- ============================================================

do $$
declare
  v_acct uuid := gen_random_uuid();
  v_ops uuid := gen_random_uuid();
  v_hr uuid := gen_random_uuid();
begin
  insert into admin_folder_templates (id, trade_type, name, is_placeholder)
  values
    (v_acct, null, 'Accounting (placeholder)', true),
    (v_ops,  null, 'Operations (placeholder)', true),
    (v_hr,   null, 'HR (placeholder)',         true);

  insert into admin_folder_template_nodes (folder_template_id, parent_node_id, name, order_index) values
    (v_acct, null, 'Accounts Payable', 10),
    (v_acct, null, 'Accounts Receivable', 20),
    (v_acct, null, 'Tax', 30),
    (v_acct, null, 'Payroll', 40),
    (v_ops,  null, 'Active Projects', 10),
    (v_ops,  null, 'Completed Projects', 20),
    (v_ops,  null, 'Equipment', 30),
    (v_ops,  null, 'Safety', 40),
    (v_hr,   null, 'Employees', 10),
    (v_hr,   null, 'Onboarding', 20),
    (v_hr,   null, 'Policies', 30),
    (v_hr,   null, 'Benefits', 40);
end$$;
