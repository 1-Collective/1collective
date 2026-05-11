-- One Collective: Row Level Security policies + helper functions.
-- Multi-tenant isolation, platform-operator gating, and field-role row scoping.

-- ============================================================
-- HELPER FUNCTIONS (security definer where needed for RLS perf)
-- ============================================================

-- The tenant_id encoded into the JWT custom claim at login.
-- Returns NULL when running as a platform operator or for anon users.
create or replace function current_tenant_id() returns uuid
  language sql stable
  as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'tenant_id', '')::uuid;
$$;

-- Is the current auth user a platform operator?
create or replace function is_platform_operator() returns boolean
  language sql stable security definer set search_path = public
  as $$
  select exists (select 1 from platform_operators where id = auth.uid());
$$;

-- Does the current user hold any role flagged is_field for their active tenant?
create or replace function is_field_role() returns boolean
  language sql stable security definer set search_path = public
  as $$
  select exists (
    select 1
    from user_role_assignments ura
    join roles r on r.id = ura.role_id
    where ura.user_id = auth.uid()
      and ura.tenant_id = current_tenant_id()
      and r.is_field = true
  );
$$;

-- Can a field user see a specific sensitive field on a specific project?
-- Returns true if either (a) user isn't a field role, or (b) an override exists.
create or replace function field_user_can_see(p_project_id uuid, p_field_name text) returns boolean
  language sql stable security definer set search_path = public
  as $$
  select case
    when not is_field_role() then true
    else exists (
      select 1 from project_field_overrides
      where project_id = p_project_id
        and field_name = p_field_name
        and (user_id is null or user_id = auth.uid())
    )
  end;
$$;

-- Is the current user assigned to a project? (used in field-role row policies)
create or replace function user_is_assigned_to_project(p_project_id uuid) returns boolean
  language sql stable security definer set search_path = public
  as $$
  select exists (
    select 1 from project_assignments
    where project_id = p_project_id
      and user_id = auth.uid()
      and removed_at is null
  );
$$;

-- ============================================================
-- ENABLE RLS on every tenant-owned table
-- ============================================================

alter table tenants enable row level security;
alter table tenant_locations enable row level security;
alter table tenant_service_areas enable row level security;
alter table users enable row level security;
alter table user_tenant_memberships enable row level security;
alter table platform_operators enable row level security;
alter table roles enable row level security;
alter table role_permissions enable row level security;
alter table user_role_assignments enable row level security;
alter table onboarding_progress enable row level security;
alter table onboarding_contract_ingestion enable row level security;
alter table setup_tasks enable row level security;
alter table brand_content enable row level security;
alter table brand_content_versions enable row level security;
alter table companies enable row level security;
alter table contacts enable row level security;
alter table projects enable row level security;
alter table project_stage_history enable row level security;
alter table project_contacts enable row level security;
alter table project_assignments enable row level security;
alter table project_field_overrides enable row level security;
alter table email_accounts enable row level security;
alter table tenant_bids_setup enable row level security;
alter table communications enable row level security;
alter table automation_schedules enable row level security;
alter table automation_message_templates enable row level security;
alter table automation_runs enable row level security;
alter table contracts enable row level security;
alter table contract_versions enable row level security;
alter table contract_flags enable row level security;
alter table pre_job_checklists enable row level security;
alter table pre_job_checklist_items enable row level security;
alter table revenue_history enable row level security;
alter table qbo_connections enable row level security;
alter table qbo_chart_of_accounts_snapshots enable row level security;
alter table qbo_chart_recommendations enable row level security;
alter table financial_health_scores enable row level security;
alter table google_drive_connections enable row level security;
alter table drive_folder_template_applications enable row level security;
alter table drive_file_index enable row level security;
alter table admin_folder_templates enable row level security;
alter table admin_folder_template_nodes enable row level security;
alter table admin_checklist_items enable row level security;
alter table admin_clause_library enable row level security;
alter table cross_tenant_contract_patterns enable row level security;
alter table invite_links enable row level security;
alter table invite_link_redemptions enable row level security;
alter table tenant_billing enable row level security;
alter table accountant_billing_grants enable row level security;
alter table billing_events enable row level security;
alter table audit_log enable row level security;
alter table integration_events enable row level security;

-- ============================================================
-- TENANT-ISOLATED TABLES: standard tenant_id filter
-- ============================================================

-- Helper to apply the canonical policy to many tables in one block
do $$
declare
  t text;
  tenant_isolated text[] := array[
    'tenant_locations', 'tenant_service_areas',
    'user_tenant_memberships',
    'roles', 'role_permissions', 'user_role_assignments',
    'onboarding_progress', 'onboarding_contract_ingestion', 'setup_tasks',
    'brand_content', 'brand_content_versions',
    'companies', 'contacts',
    'project_stage_history', 'project_contacts',
    'project_assignments', 'project_field_overrides',
    'email_accounts', 'tenant_bids_setup',
    'communications', 'automation_schedules',
    'automation_message_templates', 'automation_runs',
    'contracts', 'contract_versions', 'contract_flags',
    'pre_job_checklists',
    'revenue_history', 'qbo_connections',
    'qbo_chart_of_accounts_snapshots', 'qbo_chart_recommendations',
    'financial_health_scores',
    'google_drive_connections', 'drive_folder_template_applications', 'drive_file_index',
    'tenant_billing', 'accountant_billing_grants', 'billing_events',
    'invite_link_redemptions'
  ];
begin
  foreach t in array tenant_isolated loop
    execute format($p$
      create policy tenant_isolation_select on %1$I
        for select using (
          tenant_id = current_tenant_id()
          or is_platform_operator()
        );
      create policy tenant_isolation_modify on %1$I
        for all using (
          tenant_id = current_tenant_id()
          or is_platform_operator()
        )
        with check (
          tenant_id = current_tenant_id()
          or is_platform_operator()
        );
    $p$, t);
  end loop;
end$$;

-- ============================================================
-- TENANTS table: users see only their own tenant rows
-- ============================================================

create policy tenants_select on tenants
  for select using (
    id = current_tenant_id()
    or is_platform_operator()
    or exists (
      select 1 from user_tenant_memberships
      where user_id = auth.uid() and tenant_id = tenants.id
    )
  );
create policy tenants_modify on tenants
  for all using (id = current_tenant_id() or is_platform_operator())
  with check (id = current_tenant_id() or is_platform_operator());

-- ============================================================
-- USERS table: see self + same-tenant; operators see all
-- ============================================================

create policy users_select on users
  for select using (
    id = auth.uid()
    or tenant_id = current_tenant_id()
    or is_platform_operator()
  );
create policy users_modify on users
  for all using (id = auth.uid() or is_platform_operator())
  with check (id = auth.uid() or is_platform_operator());

-- ============================================================
-- PLATFORM OPERATORS: operator-only
-- ============================================================

create policy platform_operators_all on platform_operators
  for all using (is_platform_operator())
  with check (is_platform_operator());

-- ============================================================
-- PROJECTS: tenant isolation + field-role row scoping
-- Field roles only see projects they're assigned to.
-- ============================================================

create policy projects_select on projects
  for select using (
    is_platform_operator()
    or (
      tenant_id = current_tenant_id()
      and (
        not is_field_role()
        or user_is_assigned_to_project(id)
      )
    )
  );
create policy projects_modify on projects
  for all using (
    is_platform_operator()
    or (tenant_id = current_tenant_id() and not is_field_role())
  )
  with check (
    is_platform_operator()
    or (tenant_id = current_tenant_id() and not is_field_role())
  );

-- ============================================================
-- PRE-JOB CHECKLIST ITEMS: field roles can READ items on their projects
-- ============================================================

create policy pre_job_checklist_items_select on pre_job_checklist_items
  for select using (
    is_platform_operator()
    or (
      tenant_id = current_tenant_id()
      and (
        not is_field_role()
        or user_is_assigned_to_project(project_id)
      )
    )
  );
create policy pre_job_checklist_items_modify on pre_job_checklist_items
  for all using (
    is_platform_operator()
    or (
      tenant_id = current_tenant_id()
      and (
        not is_field_role()
        or user_is_assigned_to_project(project_id)
      )
    )
  )
  with check (
    is_platform_operator()
    or (
      tenant_id = current_tenant_id()
      and (
        not is_field_role()
        or user_is_assigned_to_project(project_id)
      )
    )
  );

-- ============================================================
-- ADMIN PORTAL TABLES: platform operators only
-- ============================================================

do $$
declare
  t text;
  operator_only text[] := array[
    'admin_folder_templates',
    'admin_folder_template_nodes',
    'admin_checklist_items',
    'admin_clause_library',
    'cross_tenant_contract_patterns',
    'invite_links'
  ];
begin
  foreach t in array operator_only loop
    -- Operator-only WRITE; everyone authenticated can READ admin reference data
    -- (tenants need to see the checklist/clause library results referenced by their flags).
    execute format($p$
      create policy %1$s_read on %1$I
        for select using (true);
      create policy %1$s_write on %1$I
        for all using (is_platform_operator())
        with check (is_platform_operator());
    $p$, t);
  end loop;
end$$;

-- ============================================================
-- SYSTEM TABLES: audit log, integration events
-- ============================================================

create policy audit_log_select on audit_log
  for select using (
    is_platform_operator()
    or tenant_id = current_tenant_id()
  );
create policy audit_log_insert on audit_log
  for insert with check (true);  -- writes only via service role / triggers

create policy integration_events_all on integration_events
  for all using (is_platform_operator())
  with check (is_platform_operator());
