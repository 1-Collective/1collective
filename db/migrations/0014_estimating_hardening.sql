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
