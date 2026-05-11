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
