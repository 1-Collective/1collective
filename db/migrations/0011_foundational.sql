-- [CC-FOUNDATION] Phase 1: shared OAuth/credential storage for tenant
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
