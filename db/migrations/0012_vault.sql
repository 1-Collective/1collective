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
