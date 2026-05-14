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
