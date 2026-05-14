-- One Collective: initial schema
-- Creates every table, enum, index, and foreign key for v1.
-- RLS policies live in 0002_rls.sql; views in 0003_field_views.sql; seeds in 0004_seed.sql.

create extension if not exists "pgcrypto";

-- ============================================================
-- ENUMS
-- ============================================================

create type trade_type as enum (
  'plumbing', 'mechanical', 'fire_protection', 'concrete', 'steel',
  'electrical', 'general_contracting', 'hvac', 'landscaping',
  'roofing', 'masonry', 'other'
);

create type tenant_status as enum ('onboarding', 'active', 'suspended', 'trial_expired');

create type project_stage as enum (
  'prospect', 'active_bid', 'awarded', 'in_progress', 'complete', 'archived'
);

create type project_status as enum ('on_track', 'at_risk', 'behind', 'on_hold');

create type flag_priority as enum ('critical', 'high', 'low');

create type flag_status as enum ('open', 'resolved', 'accepted', 'dismissed');

create type parse_status as enum ('pending', 'parsing', 'parsed', 'failed');

create type contract_status as enum ('in_review', 'sent', 'signed', 'archived');

create type oauth_status as enum ('connected', 'expired', 'revoked');

create type comm_channel as enum ('email', 'sms', 'call', 'note', 'meeting');

create type comm_direction as enum ('inbound', 'outbound', 'internal');

create type automation_status as enum ('queued', 'sending', 'sent', 'failed', 'cancelled');

create type invite_billing_mode as enum ('free_forever', 'free_trial', 'paid_immediate');

create type tenant_billing_status as enum (
  'trialing', 'active', 'past_due', 'cancelled', 'free_forever'
);

create type platform_operator_role as enum ('super', 'support', 'readonly');

create type module_key as enum (
  'dashboard', 'crm', 'precon', 'revenue', 'drive', 'estimating',
  'branding', 'team', 'billing', 'settings'
);

create type setup_task_type as enum (
  'complete_contract', 'connect_drive', 'connect_qbo', 'connect_gmail',
  'configure_bids_email', 'review_brand_content', 'invite_team'
);

create type setup_task_status as enum ('open', 'in_progress', 'dismissed', 'completed');

create type company_type as enum ('gc', 'owner', 'sub', 'vendor', 'other');

-- ============================================================
-- HELPER FUNCTIONS: updated_at auto-touch
-- ============================================================

create or replace function set_updated_at() returns trigger as $$
begin
  new.updated_at := now();
  return new;
end;
$$ language plpgsql;

-- ============================================================
-- IDENTITY & MULTI-TENANCY
-- ============================================================

create table tenants (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  logo_storage_path text,
  primary_color_hex text,
  secondary_color_hex text,
  brand_color_meta jsonb default '{}'::jsonb,
  trade_types trade_type[] not null default '{}',
  custom_trade_types text[] not null default '{}',
  google_workspace_domain text,
  bids_email_address text,
  status tenant_status not null default 'onboarding',
  created_via_invite_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create trigger tenants_set_updated_at before update on tenants for each row execute function set_updated_at();

create table tenant_locations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  label text not null,
  street text,
  city text,
  state text,
  postal_code text,
  country text default 'US',
  latitude numeric(9,6),
  longitude numeric(9,6),
  service_radius_miles int,
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index tenant_locations_tenant_id_idx on tenant_locations(tenant_id);
create trigger tenant_locations_set_updated_at before update on tenant_locations for each row execute function set_updated_at();

create table tenant_service_areas (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  label text not null,
  region_type text not null default 'custom',
  region_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index tenant_service_areas_tenant_id_idx on tenant_service_areas(tenant_id);
create trigger tenant_service_areas_set_updated_at before update on tenant_service_areas for each row execute function set_updated_at();

create table users (
  id uuid primary key,                          -- = auth.users.id
  tenant_id uuid references tenants(id) on delete cascade,
  email text not null,
  full_name text,
  phone_e164 text,
  twilio_number_e164 text unique,
  twilio_subaccount_sid text,
  profile_image_storage_path text,
  last_active_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index users_tenant_id_idx on users(tenant_id);
create index users_email_idx on users(email);
create trigger users_set_updated_at before update on users for each row execute function set_updated_at();

create table user_tenant_memberships (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  tenant_id uuid not null references tenants(id) on delete cascade,
  is_default boolean not null default true,
  created_at timestamptz not null default now(),
  unique (user_id, tenant_id)
);
create index user_tenant_memberships_user_idx on user_tenant_memberships(user_id);
create index user_tenant_memberships_tenant_idx on user_tenant_memberships(tenant_id);

create table platform_operators (
  id uuid primary key,                          -- = auth.users.id
  email text not null unique,
  full_name text,
  operator_role platform_operator_role not null default 'support',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create trigger platform_operators_set_updated_at before update on platform_operators for each row execute function set_updated_at();

-- Disjointness: an auth user is either a tenant user OR a platform operator, never both.
-- Enforced via a trigger because we can't FK to both tables and need a clean check.
create or replace function enforce_user_operator_disjoint() returns trigger as $$
begin
  if exists (select 1 from platform_operators where id = new.id) then
    raise exception 'auth user % is already a platform_operator; cannot also be a tenant user', new.id;
  end if;
  return new;
end;
$$ language plpgsql;
create trigger users_disjoint_operators
  before insert or update of id on users
  for each row execute function enforce_user_operator_disjoint();

create or replace function enforce_operator_user_disjoint() returns trigger as $$
begin
  if exists (select 1 from users where id = new.id) then
    raise exception 'auth user % is already a tenant user; cannot also be a platform_operator', new.id;
  end if;
  return new;
end;
$$ language plpgsql;
create trigger operators_disjoint_users
  before insert or update of id on platform_operators
  for each row execute function enforce_operator_user_disjoint();

-- ============================================================
-- ROLES & PERMISSIONS
-- ============================================================

create table roles (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade,
  key text not null,
  name text not null,
  description text,
  is_system boolean not null default false,
  is_field boolean not null default false,
  max_seats int,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, key)
);
create index roles_tenant_id_idx on roles(tenant_id);
create trigger roles_set_updated_at before update on roles for each row execute function set_updated_at();

create table role_permissions (
  id uuid primary key default gen_random_uuid(),
  role_id uuid not null references roles(id) on delete cascade,
  module module_key not null,
  can_read boolean not null default false,
  can_write boolean not null default false,
  can_edit boolean not null default false,
  can_delete boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (role_id, module)
);
create index role_permissions_role_idx on role_permissions(role_id);
create trigger role_permissions_set_updated_at before update on role_permissions for each row execute function set_updated_at();

create table user_role_assignments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  role_id uuid not null references roles(id) on delete cascade,
  tenant_id uuid not null references tenants(id) on delete cascade,
  assigned_by uuid references users(id),
  created_at timestamptz not null default now(),
  unique (user_id, role_id)
);
create index user_role_assignments_user_idx on user_role_assignments(user_id);
create index user_role_assignments_tenant_idx on user_role_assignments(tenant_id);

-- ============================================================
-- ONBOARDING
-- ============================================================

create table onboarding_progress (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade unique,
  current_step_key text not null default 'company_info',
  completed_steps text[] not null default '{}',
  step_state jsonb not null default '{}'::jsonb,
  started_at timestamptz not null default now(),
  last_active_at timestamptz not null default now(),
  completed_at timestamptz
);

create table onboarding_contract_ingestion (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  file_storage_path text not null,
  original_filename text,
  parse_status parse_status not null default 'pending',
  parse_error text,
  parsed_at timestamptz,
  created_contract_id uuid,
  incomplete_fields text[] default '{}',
  created_at timestamptz not null default now()
);
create index onboarding_contract_ingestion_tenant_idx on onboarding_contract_ingestion(tenant_id);

create table setup_tasks (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  task_type setup_task_type not null,
  target_id uuid,
  title text not null,
  description text,
  status setup_task_status not null default 'open',
  priority int not null default 50,
  assigned_to uuid references users(id),
  completed_at timestamptz,
  created_at timestamptz not null default now()
);
create index setup_tasks_tenant_idx on setup_tasks(tenant_id);
create index setup_tasks_status_idx on setup_tasks(status);

-- ============================================================
-- BRAND CONTENT (Purpose, Values, Vision)
-- ============================================================

create table brand_content (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade unique,
  purpose text,
  core_values jsonb not null default '[]'::jsonb,
  vision text,
  mission text,
  about_us_layout jsonb not null default '{}'::jsonb,
  current_version_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger brand_content_set_updated_at before update on brand_content for each row execute function set_updated_at();

create table brand_content_versions (
  id uuid primary key default gen_random_uuid(),
  brand_content_id uuid not null references brand_content(id) on delete cascade,
  tenant_id uuid not null references tenants(id) on delete cascade,
  version_number int not null,
  snapshot jsonb not null,
  edited_by uuid references users(id),
  created_at timestamptz not null default now(),
  unique (brand_content_id, version_number)
);
create index brand_content_versions_brand_idx on brand_content_versions(brand_content_id);

alter table brand_content
  add constraint brand_content_current_version_fk
  foreign key (current_version_id) references brand_content_versions(id) on delete set null;

-- ============================================================
-- CRM: Companies, Contacts, Projects, Communications, Automations
-- ============================================================

create table companies (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  name text not null,
  type company_type not null default 'other',
  website text,
  primary_address jsonb default '{}'::jsonb,
  notes text,
  default_automation_schedule_id uuid,
  created_via text not null default 'manual',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index companies_tenant_idx on companies(tenant_id);
create trigger companies_set_updated_at before update on companies for each row execute function set_updated_at();

create table contacts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  company_id uuid references companies(id) on delete set null,
  first_name text,
  last_name text,
  title text,
  email text,
  phone_e164 text,
  role_at_company text,
  default_automation_schedule_id uuid,
  preferred_channel text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index contacts_tenant_idx on contacts(tenant_id);
create index contacts_company_idx on contacts(company_id);
create trigger contacts_set_updated_at before update on contacts for each row execute function set_updated_at();

create table projects (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  company_id uuid references companies(id) on delete set null,
  name text not null,
  project_number text,
  trade_types trade_type[] not null default '{}',
  region text,
  stage project_stage not null default 'prospect',
  stage_entered_at timestamptz not null default now(),
  contract_value_cents bigint,
  billed_to_date_cents bigint,
  amount_remaining_cents bigint,
  percent_complete numeric(5,2),
  projected_completion_date date,
  actual_completion_date date,
  bid_submitted_at timestamptz,
  contract_awarded_at timestamptz,
  status project_status not null default 'on_track',
  description text,
  custom_fields jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (tenant_id, project_number)
);
create index projects_tenant_idx on projects(tenant_id);
create index projects_company_idx on projects(company_id);
create index projects_stage_idx on projects(stage);
create trigger projects_set_updated_at before update on projects for each row execute function set_updated_at();

create table project_stage_history (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id) on delete cascade,
  tenant_id uuid not null references tenants(id) on delete cascade,
  from_stage project_stage,
  to_stage project_stage not null,
  changed_by uuid references users(id),
  note text,
  changed_at timestamptz not null default now()
);
create index project_stage_history_project_idx on project_stage_history(project_id);

create table project_contacts (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id) on delete cascade,
  contact_id uuid not null references contacts(id) on delete cascade,
  tenant_id uuid not null references tenants(id) on delete cascade,
  role_on_project text,
  created_at timestamptz not null default now(),
  unique (project_id, contact_id)
);
create index project_contacts_project_idx on project_contacts(project_id);
create index project_contacts_contact_idx on project_contacts(contact_id);

create table project_assignments (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id) on delete cascade,
  user_id uuid not null references users(id) on delete cascade,
  tenant_id uuid not null references tenants(id) on delete cascade,
  role_on_project text,
  assigned_by uuid references users(id),
  created_at timestamptz not null default now(),
  removed_at timestamptz
);
create index project_assignments_project_idx on project_assignments(project_id);
create index project_assignments_user_idx on project_assignments(user_id);

create table project_field_overrides (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id) on delete cascade,
  user_id uuid references users(id) on delete cascade,
  tenant_id uuid not null references tenants(id) on delete cascade,
  field_name text not null,
  granted_by uuid references users(id),
  created_at timestamptz not null default now(),
  unique (project_id, user_id, field_name)
);
create index project_field_overrides_project_idx on project_field_overrides(project_id);

create table email_accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  tenant_id uuid not null references tenants(id) on delete cascade,
  provider text not null,
  email_address text not null,
  oauth_tokens jsonb not null default '{}'::jsonb,
  scopes text[] not null default '{}',
  is_bids_alias boolean not null default false,
  last_synced_at timestamptz,
  status oauth_status not null default 'connected',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index email_accounts_tenant_idx on email_accounts(tenant_id);
create index email_accounts_user_idx on email_accounts(user_id);
create trigger email_accounts_set_updated_at before update on email_accounts for each row execute function set_updated_at();

create table tenant_bids_setup (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade unique,
  target_address text,
  status text not null default 'pending',
  verified_email_account_id uuid references email_accounts(id) on delete set null,
  checked_at timestamptz
);

create table communications (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  channel comm_channel not null,
  direction comm_direction not null,
  company_id uuid references companies(id) on delete set null,
  contact_id uuid references contacts(id) on delete set null,
  project_id uuid references projects(id) on delete set null,
  user_id uuid references users(id) on delete set null,
  external_id text,
  subject text,
  body text,
  attachments jsonb default '[]'::jsonb,
  metadata jsonb default '{}'::jsonb,
  sent_via_email_account_id uuid references email_accounts(id) on delete set null,
  occurred_at timestamptz not null,
  created_at timestamptz not null default now()
);
create index communications_tenant_idx on communications(tenant_id);
create index communications_company_idx on communications(company_id);
create index communications_contact_idx on communications(contact_id);
create index communications_project_idx on communications(project_id);
create index communications_occurred_at_idx on communications(occurred_at desc);

create table automation_schedules (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  name text not null,
  description text,
  is_template boolean not null default false,
  rules jsonb not null default '[]'::jsonb,
  applies_to_value_above_cents bigint,
  created_by uuid references users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index automation_schedules_tenant_idx on automation_schedules(tenant_id);
create trigger automation_schedules_set_updated_at before update on automation_schedules for each row execute function set_updated_at();

create table automation_message_templates (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  name text not null,
  channel comm_channel not null,
  subject text,
  body text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index automation_message_templates_tenant_idx on automation_message_templates(tenant_id);
create trigger automation_message_templates_set_updated_at before update on automation_message_templates for each row execute function set_updated_at();

create table automation_runs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  automation_schedule_id uuid references automation_schedules(id) on delete set null,
  project_id uuid references projects(id) on delete set null,
  company_id uuid references companies(id) on delete set null,
  contact_id uuid references contacts(id) on delete set null,
  rule_index int,
  channel comm_channel,
  status automation_status not null default 'queued',
  scheduled_for timestamptz not null,
  attempted_at timestamptz,
  sent_at timestamptz,
  failure_reason text,
  resulting_communication_id uuid references communications(id) on delete set null,
  created_at timestamptz not null default now()
);
create index automation_runs_tenant_idx on automation_runs(tenant_id);
create index automation_runs_status_idx on automation_runs(status);
create index automation_runs_scheduled_for_idx on automation_runs(scheduled_for) where status = 'queued';

-- Wire up the FKs that pointed forward earlier
alter table companies
  add constraint companies_default_automation_fk
  foreign key (default_automation_schedule_id) references automation_schedules(id) on delete set null;

alter table contacts
  add constraint contacts_default_automation_fk
  foreign key (default_automation_schedule_id) references automation_schedules(id) on delete set null;

-- ============================================================
-- PRE-CON: Contracts, Versions, Flags, Pre-Job Checklist
-- ============================================================

create table contracts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  project_id uuid not null references projects(id) on delete cascade,
  title text not null,
  contract_type text not null default 'prime',
  current_version_id uuid,
  total_versions int not null default 0,
  health_score int,
  counterparty_company_id uuid references companies(id) on delete set null,
  counterparty_signer_contact_id uuid references contacts(id) on delete set null,
  status contract_status not null default 'in_review',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index contracts_tenant_idx on contracts(tenant_id);
create index contracts_project_idx on contracts(project_id);
create trigger contracts_set_updated_at before update on contracts for each row execute function set_updated_at();

create table contract_versions (
  id uuid primary key default gen_random_uuid(),
  contract_id uuid not null references contracts(id) on delete cascade,
  tenant_id uuid not null references tenants(id) on delete cascade,
  version_number int not null,
  storage_path text not null,
  mime_type text,
  size_bytes bigint,
  upload_source text,
  uploaded_by uuid references users(id),
  is_current boolean not null default false,
  parsed_at timestamptz,
  parse_status parse_status not null default 'pending',
  extracted_data jsonb default '{}'::jsonb,
  diff_from_previous jsonb default '{}'::jsonb,
  health_score int,
  created_at timestamptz not null default now(),
  unique (contract_id, version_number)
);
create index contract_versions_contract_idx on contract_versions(contract_id);

alter table contracts
  add constraint contracts_current_version_fk
  foreign key (current_version_id) references contract_versions(id) on delete set null;

create table contract_flags (
  id uuid primary key default gen_random_uuid(),
  contract_version_id uuid not null references contract_versions(id) on delete cascade,
  tenant_id uuid not null references tenants(id) on delete cascade,
  priority flag_priority not null,
  title text not null,
  explanation text,
  contract_line_reference jsonb default '{}'::jsonb,
  suggested_language text,
  suggested_language_source text,
  clause_library_entry_id uuid,
  checklist_item_id uuid,
  status flag_status not null default 'open',
  user_notes text,
  resolved_by uuid references users(id),
  resolved_at timestamptz,
  applied_to_version_id uuid references contract_versions(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index contract_flags_version_idx on contract_flags(contract_version_id);
create index contract_flags_status_idx on contract_flags(status);
create trigger contract_flags_set_updated_at before update on contract_flags for each row execute function set_updated_at();

create table pre_job_checklists (
  id uuid primary key default gen_random_uuid(),
  contract_id uuid not null references contracts(id) on delete cascade,
  project_id uuid not null references projects(id) on delete cascade,
  tenant_id uuid not null references tenants(id) on delete cascade,
  generated_at timestamptz not null default now(),
  trade_types trade_type[] not null default '{}',
  created_at timestamptz not null default now()
);
create index pre_job_checklists_project_idx on pre_job_checklists(project_id);

create table pre_job_checklist_items (
  id uuid primary key default gen_random_uuid(),
  pre_job_checklist_id uuid not null references pre_job_checklists(id) on delete cascade,
  tenant_id uuid not null references tenants(id) on delete cascade,
  project_id uuid not null references projects(id) on delete cascade,
  title text not null,
  description text,
  category text,
  order_index int not null default 0,
  status text not null default 'open',
  completed_by uuid references users(id),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index pre_job_checklist_items_checklist_idx on pre_job_checklist_items(pre_job_checklist_id);
create index pre_job_checklist_items_project_idx on pre_job_checklist_items(project_id);
create trigger pre_job_checklist_items_set_updated_at before update on pre_job_checklist_items for each row execute function set_updated_at();

-- ============================================================
-- REVENUE & QUICKBOOKS
-- ============================================================

create table revenue_history (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  year int not null,
  revenue_cents bigint not null,
  source text not null default 'manual',
  qbo_pulled_at timestamptz,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, year)
);
create trigger revenue_history_set_updated_at before update on revenue_history for each row execute function set_updated_at();

create table qbo_connections (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade unique,
  realm_id text not null,
  oauth_tokens jsonb not null default '{}'::jsonb,
  scopes text[] not null default '{}',
  last_synced_at timestamptz,
  sync_status text not null default 'ok',
  sync_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger qbo_connections_set_updated_at before update on qbo_connections for each row execute function set_updated_at();

create table qbo_chart_of_accounts_snapshots (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  snapshot_at timestamptz not null default now(),
  account_count int,
  accounts jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);
create index qbo_chart_snapshots_tenant_idx on qbo_chart_of_accounts_snapshots(tenant_id);

create table qbo_chart_recommendations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  snapshot_id uuid references qbo_chart_of_accounts_snapshots(id) on delete set null,
  recommendation_type text not null,
  target_account_id text,
  current_name text,
  suggested_name text,
  rationale text,
  priority int not null default 50,
  status text not null default 'open',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index qbo_chart_recs_tenant_idx on qbo_chart_recommendations(tenant_id);
create trigger qbo_chart_recs_set_updated_at before update on qbo_chart_recommendations for each row execute function set_updated_at();

create table financial_health_scores (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  computed_at timestamptz not null default now(),
  overall_score int,
  component_scores jsonb default '{}'::jsonb,
  trends jsonb default '{}'::jsonb,
  gaps jsonb default '{}'::jsonb,
  recommendations jsonb default '{}'::jsonb,
  input_snapshot_id uuid references qbo_chart_of_accounts_snapshots(id) on delete set null,
  created_at timestamptz not null default now()
);
create index financial_health_tenant_idx on financial_health_scores(tenant_id);

-- ============================================================
-- DRIVE & FOLDER TEMPLATES (Tenant-side records)
-- ============================================================

create table google_drive_connections (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade unique,
  connected_by uuid references users(id),
  oauth_tokens jsonb not null default '{}'::jsonb,
  google_account_email text,
  root_folder_id text,
  status oauth_status not null default 'connected',
  last_synced_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger google_drive_connections_set_updated_at before update on google_drive_connections for each row execute function set_updated_at();

create table drive_folder_template_applications (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  folder_template_id uuid not null,
  applied_at timestamptz not null default now(),
  status text not null default 'ok',
  drive_folder_ids jsonb default '{}'::jsonb
);
create index drive_folder_template_apps_tenant_idx on drive_folder_template_applications(tenant_id);

create table drive_file_index (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  drive_file_id text not null,
  drive_parent_id text,
  project_id uuid references projects(id) on delete set null,
  name text,
  mime_type text,
  size_bytes bigint,
  modified_at timestamptz,
  indexed_at timestamptz not null default now(),
  unique (tenant_id, drive_file_id)
);
create index drive_file_index_tenant_idx on drive_file_index(tenant_id);
create index drive_file_index_project_idx on drive_file_index(project_id);

-- ============================================================
-- ADMIN PORTAL (operator-managed reference data)
-- ============================================================

create table admin_folder_templates (
  id uuid primary key default gen_random_uuid(),
  trade_type trade_type,
  name text not null,
  is_placeholder boolean not null default false,
  created_by uuid references platform_operators(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger admin_folder_templates_set_updated_at before update on admin_folder_templates for each row execute function set_updated_at();

create table admin_folder_template_nodes (
  id uuid primary key default gen_random_uuid(),
  folder_template_id uuid not null references admin_folder_templates(id) on delete cascade,
  parent_node_id uuid references admin_folder_template_nodes(id) on delete cascade,
  name text not null,
  order_index int not null default 0,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index admin_folder_template_nodes_template_idx on admin_folder_template_nodes(folder_template_id);
create index admin_folder_template_nodes_parent_idx on admin_folder_template_nodes(parent_node_id);
create trigger admin_folder_template_nodes_set_updated_at before update on admin_folder_template_nodes for each row execute function set_updated_at();

alter table drive_folder_template_applications
  add constraint drive_folder_template_apps_template_fk
  foreign key (folder_template_id) references admin_folder_templates(id) on delete restrict;

create table admin_checklist_items (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  category text,
  trade_types trade_type[] default '{}',
  priority_default flag_priority not null default 'high',
  order_index int not null default 0,
  is_active boolean not null default true,
  created_by uuid references platform_operators(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index admin_checklist_items_active_idx on admin_checklist_items(is_active);
create trigger admin_checklist_items_set_updated_at before update on admin_checklist_items for each row execute function set_updated_at();

create table admin_clause_library (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  clause_text text not null,
  trade_types trade_type[] default '{}',
  linked_checklist_item_id uuid references admin_checklist_items(id) on delete set null,
  tags text[] default '{}',
  is_active boolean not null default true,
  created_by uuid references platform_operators(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index admin_clause_library_active_idx on admin_clause_library(is_active);
create trigger admin_clause_library_set_updated_at before update on admin_clause_library for each row execute function set_updated_at();

-- Now we can wire up the FK from contract_flags
alter table contract_flags
  add constraint contract_flags_clause_library_fk
  foreign key (clause_library_entry_id) references admin_clause_library(id) on delete set null,
  add constraint contract_flags_checklist_item_fk
  foreign key (checklist_item_id) references admin_checklist_items(id) on delete set null;

create table cross_tenant_contract_patterns (
  id uuid primary key default gen_random_uuid(),
  pattern_type text not null,
  trade_types trade_type[] default '{}',
  pattern_text text not null,
  frequency int not null default 1,
  linked_checklist_item_id uuid references admin_checklist_items(id) on delete set null,
  last_updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

-- ============================================================
-- BILLING & INVITE LINKS
-- ============================================================

create table invite_links (
  id uuid primary key default gen_random_uuid(),
  token text not null unique,
  billing_mode invite_billing_mode not null,
  trial_duration_days int,
  max_redemptions int default 1,
  redemptions int not null default 0,
  expires_at timestamptz,
  notes text,
  created_by uuid references platform_operators(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  disabled_at timestamptz
);
create trigger invite_links_set_updated_at before update on invite_links for each row execute function set_updated_at();

alter table tenants
  add constraint tenants_invite_fk
  foreign key (created_via_invite_id) references invite_links(id) on delete set null;

create table invite_link_redemptions (
  id uuid primary key default gen_random_uuid(),
  invite_link_id uuid not null references invite_links(id) on delete cascade,
  tenant_id uuid references tenants(id) on delete set null,
  redeeming_user_id uuid references users(id) on delete set null,
  redeemed_at timestamptz not null default now()
);
create index invite_link_redemptions_link_idx on invite_link_redemptions(invite_link_id);

create table tenant_billing (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade unique,
  billing_mode invite_billing_mode not null default 'free_trial',
  trial_started_at timestamptz,
  trial_ends_at timestamptz,
  trial_extended_count int not null default 0,
  trial_warning_dismissed_at timestamptz,
  stripe_customer_id text,
  stripe_subscription_id text,
  billing_status tenant_billing_status not null default 'trialing',
  card_required_at timestamptz,
  last_payment_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger tenant_billing_set_updated_at before update on tenant_billing for each row execute function set_updated_at();

create table accountant_billing_grants (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  user_id uuid not null references users(id) on delete cascade,
  granted_by uuid references users(id),
  created_at timestamptz not null default now(),
  revoked_at timestamptz
);
create unique index accountant_billing_grants_active_idx
  on accountant_billing_grants(tenant_id, user_id)
  where revoked_at is null;

create table billing_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  event_type text not null,
  actor_id uuid,
  stripe_event_id text unique,
  payload jsonb default '{}'::jsonb,
  occurred_at timestamptz not null default now()
);
create index billing_events_tenant_idx on billing_events(tenant_id);

-- ============================================================
-- SYSTEM: Audit log + integration event log
-- ============================================================

create table audit_log (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade,
  actor_user_id uuid,
  actor_role text,
  action text not null,
  entity_type text,
  entity_id uuid,
  before jsonb,
  after jsonb,
  occurred_at timestamptz not null default now()
);
create index audit_log_tenant_idx on audit_log(tenant_id);
create index audit_log_entity_idx on audit_log(entity_type, entity_id);

create table integration_events (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  external_event_id text not null,
  event_type text,
  payload jsonb default '{}'::jsonb,
  processed_at timestamptz,
  status text not null default 'received',
  created_at timestamptz not null default now(),
  unique (provider, external_event_id)
);
create index integration_events_status_idx on integration_events(status);
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
    'roles', 'user_role_assignments',
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
-- ROLE_PERMISSIONS: no direct tenant_id; isolate by joining through roles
-- ============================================================

create policy role_permissions_select on role_permissions
  for select using (
    is_platform_operator()
    or exists (
      select 1 from roles r
      where r.id = role_permissions.role_id
        and (r.tenant_id = current_tenant_id() or r.tenant_id is null)
    )
  );
create policy role_permissions_modify on role_permissions
  for all using (
    is_platform_operator()
    or exists (
      select 1 from roles r
      where r.id = role_permissions.role_id
        and r.tenant_id = current_tenant_id()
    )
  )
  with check (
    is_platform_operator()
    or exists (
      select 1 from roles r
      where r.id = role_permissions.role_id
        and r.tenant_id = current_tenant_id()
    )
  );

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
-- One Collective: field-role security-barrier view.
-- Field roles query projects_field_safe, never the base projects table.
-- Sensitive financial columns are conditionally exposed based on
-- project_field_overrides.

create or replace view projects_field_safe with (security_barrier = true) as
select
  p.id,
  p.tenant_id,
  p.company_id,
  p.name,
  p.project_number,
  p.trade_types,
  p.region,
  p.stage,
  p.stage_entered_at,
  p.percent_complete,
  p.projected_completion_date,
  p.actual_completion_date,
  p.bid_submitted_at,
  p.contract_awarded_at,
  p.status,
  p.description,
  -- Sensitive financial fields: returned only if override exists for this user/project
  case when field_user_can_see(p.id, 'contract_value_cents')
       then p.contract_value_cents end as contract_value_cents,
  case when field_user_can_see(p.id, 'billed_to_date_cents')
       then p.billed_to_date_cents end as billed_to_date_cents,
  case when field_user_can_see(p.id, 'amount_remaining_cents')
       then p.amount_remaining_cents end as amount_remaining_cents,
  case when field_user_can_see(p.id, 'custom_fields')
       then p.custom_fields end as custom_fields,
  p.created_at,
  p.updated_at
from projects p
where
  is_platform_operator()
  or (
    p.tenant_id = current_tenant_id()
    and (
      not is_field_role()
      or user_is_assigned_to_project(p.id)
    )
  )
  and p.deleted_at is null;

grant select on projects_field_safe to authenticated;
grant select on projects_field_safe to anon;

comment on view projects_field_safe is
  'Field-safe projection of projects. Field roles MUST query this view rather than the base projects table. Sensitive financial fields are returned as NULL unless a project_field_overrides row grants visibility.';
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
-- One Collective: Storage bucket policies.
-- The buckets themselves are created in db/bootstrap.mjs (via the storage API);
-- this migration installs the RLS policies that govern who can read/write
-- objects in each bucket.

-- ============================================================
-- LOGOS bucket (public read, tenant-scoped write)
-- Path convention: tenants/{tenant_id}/logo-{timestamp}.{ext}
-- ============================================================

drop policy if exists "logos: public read" on storage.objects;
create policy "logos: public read"
  on storage.objects for select
  using (bucket_id = 'logos');

drop policy if exists "logos: tenant write" on storage.objects;
create policy "logos: tenant write"
  on storage.objects for insert
  with check (
    bucket_id = 'logos'
    and (storage.foldername(name))[1] = 'tenants'
    and (storage.foldername(name))[2]::uuid = current_tenant_id()
  );

drop policy if exists "logos: tenant update" on storage.objects;
create policy "logos: tenant update"
  on storage.objects for update
  using (
    bucket_id = 'logos'
    and (storage.foldername(name))[1] = 'tenants'
    and (storage.foldername(name))[2]::uuid = current_tenant_id()
  );

drop policy if exists "logos: tenant delete" on storage.objects;
create policy "logos: tenant delete"
  on storage.objects for delete
  using (
    bucket_id = 'logos'
    and (storage.foldername(name))[1] = 'tenants'
    and (storage.foldername(name))[2]::uuid = current_tenant_id()
  );

-- ============================================================
-- CONTRACTS bucket (private; tenant-scoped read+write)
-- Path convention: tenants/{tenant_id}/contracts/{contract_id}/v{version}.pdf
-- ============================================================

drop policy if exists "contracts: tenant read" on storage.objects;
create policy "contracts: tenant read"
  on storage.objects for select
  using (
    bucket_id = 'contracts'
    and (
      (storage.foldername(name))[2]::uuid = current_tenant_id()
      or is_platform_operator()
    )
  );

drop policy if exists "contracts: tenant write" on storage.objects;
create policy "contracts: tenant write"
  on storage.objects for insert
  with check (
    bucket_id = 'contracts'
    and (storage.foldername(name))[1] = 'tenants'
    and (storage.foldername(name))[2]::uuid = current_tenant_id()
  );

drop policy if exists "contracts: tenant delete" on storage.objects;
create policy "contracts: tenant delete"
  on storage.objects for delete
  using (
    bucket_id = 'contracts'
    and (storage.foldername(name))[2]::uuid = current_tenant_id()
  );

-- ============================================================
-- DOCUMENTS bucket (private; tenant-scoped)
-- Path convention: tenants/{tenant_id}/...
-- General-purpose tenant documents (anything not contracts/logos).
-- ============================================================

drop policy if exists "documents: tenant read" on storage.objects;
create policy "documents: tenant read"
  on storage.objects for select
  using (
    bucket_id = 'documents'
    and (
      (storage.foldername(name))[2]::uuid = current_tenant_id()
      or is_platform_operator()
    )
  );

drop policy if exists "documents: tenant write" on storage.objects;
create policy "documents: tenant write"
  on storage.objects for insert
  with check (
    bucket_id = 'documents'
    and (storage.foldername(name))[1] = 'tenants'
    and (storage.foldername(name))[2]::uuid = current_tenant_id()
  );

drop policy if exists "documents: tenant delete" on storage.objects;
create policy "documents: tenant delete"
  on storage.objects for delete
  using (
    bucket_id = 'documents'
    and (storage.foldername(name))[2]::uuid = current_tenant_id()
  );
-- One Collective: Inject tenant_id and is_field_role into the auth JWT.
--
-- Supabase's "custom_access_token_hook" lets us augment the JWT at sign-in
-- with claims that RLS policies can read via auth.jwt().
--
-- After applying this migration, go to:
--   Supabase Dashboard → Authentication → Hooks → Custom Access Token Hook
-- and enable `public.custom_access_token_hook` as the active hook.

create or replace function public.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
stable
as $$
declare
  v_user_id uuid := (event ->> 'user_id')::uuid;
  v_tenant_id uuid;
  v_is_field boolean := false;
  v_role_keys text[];
  v_claims jsonb := event -> 'claims';
begin
  -- Look up tenant from users table (tenant users)
  select tenant_id into v_tenant_id
  from public.users
  where id = v_user_id;

  if v_tenant_id is null then
    -- Maybe a platform operator: no tenant claim, but mark them.
    if exists (select 1 from public.platform_operators where id = v_user_id) then
      v_claims := v_claims || jsonb_build_object('is_platform_operator', true);
    end if;
  else
    -- Collect role keys + field flag
    select
      coalesce(array_agg(r.key), array[]::text[]),
      coalesce(bool_or(r.is_field), false)
    into v_role_keys, v_is_field
    from public.user_role_assignments ura
    join public.roles r on r.id = ura.role_id
    where ura.user_id = v_user_id
      and ura.tenant_id = v_tenant_id;

    v_claims := v_claims
      || jsonb_build_object('tenant_id', v_tenant_id::text)
      || jsonb_build_object('role_keys', to_jsonb(v_role_keys))
      || jsonb_build_object('is_field_role', v_is_field);
  end if;

  return jsonb_build_object('claims', v_claims);
end;
$$;

-- Grant the auth admin role the right to invoke the hook
grant execute on function public.custom_access_token_hook to supabase_auth_admin;
grant usage on schema public to supabase_auth_admin;
grant select on public.users to supabase_auth_admin;
grant select on public.platform_operators to supabase_auth_admin;
grant select on public.user_role_assignments to supabase_auth_admin;
grant select on public.roles to supabase_auth_admin;

-- Allow supabase_auth_admin to bypass RLS on these tables when populating claims.
alter table public.users force row level security;
alter table public.platform_operators force row level security;
alter table public.user_role_assignments force row level security;
alter table public.roles force row level security;

drop policy if exists auth_admin_read on public.users;
create policy auth_admin_read on public.users
  for select to supabase_auth_admin
  using (true);

drop policy if exists auth_admin_read on public.platform_operators;
create policy auth_admin_read on public.platform_operators
  for select to supabase_auth_admin
  using (true);

drop policy if exists auth_admin_read on public.user_role_assignments;
create policy auth_admin_read on public.user_role_assignments
  for select to supabase_auth_admin
  using (true);

drop policy if exists auth_admin_read on public.roles;
create policy auth_admin_read on public.roles
  for select to supabase_auth_admin
  using (true);
-- Address security advisor warnings:
--   1) function_search_path_mutable: pin search_path on every function we defined
--   2) anon/authenticated_security_definer_function_executable: revoke public EXECUTE
--      from helper functions; they are only meant to be called from within RLS policies

-- (1) Pin search_path
alter function public.current_tenant_id()
  set search_path = public, pg_temp;

alter function public.set_updated_at()
  set search_path = public, pg_temp;

alter function public.enforce_user_operator_disjoint()
  set search_path = public, pg_temp;

alter function public.enforce_operator_user_disjoint()
  set search_path = public, pg_temp;

alter function public.custom_access_token_hook(jsonb)
  set search_path = public, pg_temp;

alter function public.is_platform_operator()
  set search_path = public, pg_temp;

alter function public.is_field_role()
  set search_path = public, pg_temp;

alter function public.field_user_can_see(uuid, text)
  set search_path = public, pg_temp;

alter function public.user_is_assigned_to_project(uuid)
  set search_path = public, pg_temp;

-- (2) Revoke EXECUTE from public on helper functions that should only be invoked
-- from inside RLS policies (running in the authenticated user's context via SECURITY DEFINER).
-- Internal Postgres execution still works since RLS policies run as superuser-equivalent.
revoke execute on function public.is_platform_operator()           from public;
revoke execute on function public.is_field_role()                  from public;
revoke execute on function public.field_user_can_see(uuid, text)   from public;
revoke execute on function public.user_is_assigned_to_project(uuid) from public;
revoke execute on function public.current_tenant_id()              from public;

-- supabase_auth_admin still needs custom_access_token_hook (grant remains)
-- supabase_auth_admin needs to use these helpers indirectly via the hook;
-- it does so by reading the underlying tables (granted in 0006), not by calling the helpers.
</content>
</invoke>-- Revoke EXECUTE from anon + authenticated explicitly.
-- These helpers are only called from inside RLS policies; they should not be
-- exposed at /rest/v1/rpc/<name>.

revoke execute on function public.is_platform_operator()            from anon, authenticated;
revoke execute on function public.is_field_role()                   from anon, authenticated;
revoke execute on function public.field_user_can_see(uuid, text)    from anon, authenticated;
revoke execute on function public.user_is_assigned_to_project(uuid) from anon, authenticated;
revoke execute on function public.current_tenant_id()               from anon, authenticated;
</content>
</invoke>-- The logos bucket has bucket.public = true, which already makes individual
-- object URLs publicly fetchable WITHOUT any SELECT policy. The "logos: public read"
-- SELECT policy is redundant for object fetches but allows clients to LIST all
-- files in the bucket - that's the warning. Drop the policy.

drop policy if exists "logos: public read" on storage.objects;
</content>
</invoke>-- Tell Postgres the projects_field_safe view should run as the caller (not view owner),
-- so it isn't flagged as SECURITY DEFINER. We still keep security_barrier=true for the
-- planner-level leak prevention on the conditional financial columns.

alter view public.projects_field_safe set (security_invoker = true);
</content>
</invoke>-- [CC-FOUNDATION] Phase 1: shared OAuth/credential storage for tenant
-- integrations (QuickBooks, Google, Meta, Vapi, Twilio sub-accounts).
-- Tokens are encrypted at the application layer using
-- INTEGRATION_TOKEN_ENCRYPTION_KEY (AES-256-GCM); only ciphertext is stored.

create table if not exists cc_oauth_connections (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  provider text not null check (provider in (
    'quickbooks', 'google', 'meta', 'vapi', 'twilio', 'anthropic', 'openai'
  )),
  account_label text,
  access_token_ciphertext text not null,
  refresh_token_ciphertext text,
  token_metadata jsonb not null default '{}'::jsonb,
  expires_at timestamptz,
  scopes text[],
  status text not null default 'active' check (status in ('active', 'revoked', 'error')),
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, provider, account_label)
);

create index if not exists cc_oauth_connections_tenant_provider_idx
  on cc_oauth_connections (tenant_id, provider);

create trigger cc_oauth_connections_updated_at
  before update on cc_oauth_connections
  for each row execute function set_updated_at();

alter table cc_oauth_connections enable row level security;

drop policy if exists cc_oauth_connections_tenant_select on cc_oauth_connections;
create policy cc_oauth_connections_tenant_select on cc_oauth_connections
  for select using (tenant_id = current_tenant_id() or is_platform_operator());

drop policy if exists cc_oauth_connections_tenant_modify on cc_oauth_connections;
create policy cc_oauth_connections_tenant_modify on cc_oauth_connections
  for all using (tenant_id = current_tenant_id() or is_platform_operator())
  with check (tenant_id = current_tenant_id() or is_platform_operator());

revoke all on cc_oauth_connections from anon, authenticated;
grant select, insert, update, delete on cc_oauth_connections to authenticated;
-- [CC-FOUNDATION] Phase 2: Vault — encrypted, tenant-scoped document store.
-- Files live in the existing private `documents` Supabase Storage bucket under
-- the path prefix `vault/{tenant_id}/{document_id}-{filename}`. This row table
-- holds metadata + ownership + RLS; storage RLS is enforced by serving signed
-- URLs only from server actions (never client-side direct access).

create table if not exists cc_vault_documents (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  name text not null check (length(name) between 1 and 255),
  description text,
  mime_type text,
  size_bytes bigint not null check (size_bytes >= 0),
  storage_path text not null unique,
  uploaded_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Hard-bind the storage object to the row's tenant. Without this, a tenant
  -- with insert privileges on the row table could record an arbitrary
  -- storage_path and use server actions (which run as service role) to mint
  -- signed URLs or delete files belonging to other tenants.
  constraint cc_vault_documents_storage_path_tenant_scoped
    check (storage_path like 'vault/' || tenant_id::text || '/%')
);

create index if not exists cc_vault_documents_tenant_created_idx
  on cc_vault_documents (tenant_id, created_at desc);

create trigger cc_vault_documents_updated_at
  before update on cc_vault_documents
  for each row execute function set_updated_at();

alter table cc_vault_documents enable row level security;

drop policy if exists cc_vault_documents_tenant_select on cc_vault_documents;
create policy cc_vault_documents_tenant_select on cc_vault_documents
  for select using (tenant_id = current_tenant_id() or is_platform_operator());

drop policy if exists cc_vault_documents_tenant_modify on cc_vault_documents;
create policy cc_vault_documents_tenant_modify on cc_vault_documents
  for all using (tenant_id = current_tenant_id() or is_platform_operator())
  with check (tenant_id = current_tenant_id() or is_platform_operator());

-- Writes go through server actions (service role) only. Authenticated tokens
-- can read their own tenant's rows (RLS still applies) but cannot insert /
-- update / delete directly. This blocks the IDOR vector where a tenant would
-- otherwise insert a row with a crafted storage_path pointing at another
-- tenant's file, then trick a server action into signing or deleting it.
revoke all on cc_vault_documents from anon, authenticated;
grant select on cc_vault_documents to authenticated;
-- [CC-FOUNDATION] Phase 2 vertical: Estimating
-- Per-tenant estimates with line items and an optional unit-price catalog.
-- Money is stored in cents (bigint). Tax is stored as basis points (bps:
-- 1% = 100 bps) so we never round-trip through floats.

do $$
begin
  if not exists (select 1 from pg_type where typname = 'cc_estimate_status') then
    create type cc_estimate_status as enum (
      'draft', 'sent', 'accepted', 'declined', 'expired'
    );
  end if;
end$$;

create table if not exists cc_estimate_catalog_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  name text not null check (length(name) between 1 and 200),
  description text,
  unit text not null default 'ea' check (length(unit) between 1 and 16),
  default_price_cents bigint not null check (default_price_cents >= 0),
  category text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists cc_estimate_catalog_items_tenant_idx
  on cc_estimate_catalog_items (tenant_id, is_active, name);
create trigger cc_estimate_catalog_items_updated_at
  before update on cc_estimate_catalog_items
  for each row execute function set_updated_at();

create table if not exists cc_estimates (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  estimate_number text not null,
  title text not null check (length(title) between 1 and 200),
  company_id uuid references companies(id) on delete set null,
  project_id uuid references projects(id) on delete set null,
  status cc_estimate_status not null default 'draft',
  subtotal_cents bigint not null default 0 check (subtotal_cents >= 0),
  tax_rate_bps integer not null default 0 check (tax_rate_bps between 0 and 10000),
  tax_cents bigint not null default 0 check (tax_cents >= 0),
  total_cents bigint not null default 0 check (total_cents >= 0),
  valid_until date,
  sent_at timestamptz,
  accepted_at timestamptz,
  declined_at timestamptz,
  notes text,
  terms text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (tenant_id, estimate_number)
);
create index if not exists cc_estimates_tenant_status_idx
  on cc_estimates (tenant_id, status, created_at desc);
create index if not exists cc_estimates_tenant_company_idx
  on cc_estimates (tenant_id, company_id);
create trigger cc_estimates_updated_at
  before update on cc_estimates
  for each row execute function set_updated_at();

create table if not exists cc_estimate_line_items (
  id uuid primary key default gen_random_uuid(),
  estimate_id uuid not null references cc_estimates(id) on delete cascade,
  tenant_id uuid not null references tenants(id) on delete cascade,
  position integer not null check (position >= 0),
  description text not null check (length(description) between 1 and 500),
  quantity numeric(12, 4) not null default 1 check (quantity > 0),
  unit text not null default 'ea' check (length(unit) between 1 and 16),
  unit_price_cents bigint not null check (unit_price_cents >= 0),
  total_cents bigint not null check (total_cents >= 0),
  catalog_item_id uuid references cc_estimate_catalog_items(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists cc_estimate_line_items_estimate_idx
  on cc_estimate_line_items (estimate_id, position);
create index if not exists cc_estimate_line_items_tenant_idx
  on cc_estimate_line_items (tenant_id);

alter table cc_estimate_catalog_items enable row level security;
alter table cc_estimates enable row level security;
alter table cc_estimate_line_items enable row level security;

drop policy if exists cc_estimate_catalog_items_tenant_select on cc_estimate_catalog_items;
create policy cc_estimate_catalog_items_tenant_select on cc_estimate_catalog_items
  for select using (tenant_id = current_tenant_id() or is_platform_operator());
drop policy if exists cc_estimate_catalog_items_tenant_modify on cc_estimate_catalog_items;
create policy cc_estimate_catalog_items_tenant_modify on cc_estimate_catalog_items
  for all using (tenant_id = current_tenant_id() or is_platform_operator())
  with check (tenant_id = current_tenant_id() or is_platform_operator());

drop policy if exists cc_estimates_tenant_select on cc_estimates;
create policy cc_estimates_tenant_select on cc_estimates
  for select using (tenant_id = current_tenant_id() or is_platform_operator());
drop policy if exists cc_estimates_tenant_modify on cc_estimates;
create policy cc_estimates_tenant_modify on cc_estimates
  for all using (tenant_id = current_tenant_id() or is_platform_operator())
  with check (tenant_id = current_tenant_id() or is_platform_operator());

drop policy if exists cc_estimate_line_items_tenant_select on cc_estimate_line_items;
create policy cc_estimate_line_items_tenant_select on cc_estimate_line_items
  for select using (tenant_id = current_tenant_id() or is_platform_operator());
drop policy if exists cc_estimate_line_items_tenant_modify on cc_estimate_line_items;
create policy cc_estimate_line_items_tenant_modify on cc_estimate_line_items
  for all using (tenant_id = current_tenant_id() or is_platform_operator())
  with check (tenant_id = current_tenant_id() or is_platform_operator());

-- All writes happen through server actions that run as service role and
-- enforce tenant isolation in code. Authenticated tokens get read access only.
revoke all on cc_estimate_catalog_items from anon, authenticated;
revoke all on cc_estimates from anon, authenticated;
revoke all on cc_estimate_line_items from anon, authenticated;
grant select on cc_estimate_catalog_items to authenticated;
grant select on cc_estimates to authenticated;
grant select on cc_estimate_line_items to authenticated;
-- [CC-FOUNDATION] Estimating hardening: atomic numbering + tenant-coupled FK.
-- Eliminates the read-then-write race in nextEstimateNumber and the cross-tenant
-- foreign-key window on cc_estimate_line_items.

create table if not exists cc_estimate_number_counters (
  tenant_id uuid not null references tenants(id) on delete cascade,
  year integer not null check (year between 2000 and 9999),
  last_seq integer not null default 0 check (last_seq >= 0),
  updated_at timestamptz not null default now(),
  primary key (tenant_id, year)
);

alter table cc_estimate_number_counters enable row level security;
revoke all on cc_estimate_number_counters from anon, authenticated;
-- The counter table is operated on exclusively from server actions running as
-- service role; tenants never need read access.

create or replace function cc_next_estimate_seq(p_tenant uuid, p_year integer)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_seq integer;
begin
  insert into cc_estimate_number_counters as c (tenant_id, year, last_seq)
  values (p_tenant, p_year, 1)
  on conflict (tenant_id, year) do update
    set last_seq = c.last_seq + 1,
        updated_at = now()
  returning c.last_seq into v_seq;
  return v_seq;
end
$$;

revoke all on function cc_next_estimate_seq(uuid, integer) from public, anon, authenticated;
grant execute on function cc_next_estimate_seq(uuid, integer) to service_role;

-- Backfill the counter from any estimates that already exist so the next
-- allocation never collides with an older `EST-YYYY-NNNN`.
insert into cc_estimate_number_counters (tenant_id, year, last_seq)
select tenant_id,
       (substring(estimate_number from 'EST-(\d{4})-'))::int,
       max((substring(estimate_number from 'EST-\d{4}-(\d+)$'))::int)
from cc_estimates
where estimate_number ~ '^EST-\d{4}-\d+$'
group by tenant_id, (substring(estimate_number from 'EST-(\d{4})-'))::int
on conflict (tenant_id, year) do update
  set last_seq = greatest(cc_estimate_number_counters.last_seq, excluded.last_seq);

-- Tenant-coupled FK: a line item cannot reference an estimate that belongs to
-- a different tenant. Requires a unique key on (id, tenant_id) of the parent.
alter table cc_estimates
  drop constraint if exists cc_estimates_id_tenant_unique;
alter table cc_estimates
  add constraint cc_estimates_id_tenant_unique unique (id, tenant_id);

alter table cc_estimate_line_items
  drop constraint if exists cc_estimate_line_items_estimate_id_fkey;
alter table cc_estimate_line_items
  drop constraint if exists cc_estimate_line_items_estimate_tenant_fkey;
alter table cc_estimate_line_items
  add constraint cc_estimate_line_items_estimate_tenant_fkey
  foreign key (estimate_id, tenant_id)
  references cc_estimates (id, tenant_id)
  on delete cascade;
