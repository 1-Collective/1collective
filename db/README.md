# Database

PostgreSQL hosted on Supabase. Multi-tenant via row-level security.

## Files

- `migrations/0001_init.sql` — enums, tables, indexes, foreign keys
- `migrations/0002_rls.sql` — RLS policies + helper functions
- `migrations/0003_field_views.sql` — field-role security-barrier view
- `migrations/0004_seed.sql` — system role templates + placeholder folder templates

Apply in numerical order. Each migration is idempotent only on the first run — re-running will error on existing objects. Migrations are immutable once applied.

## Applying migrations

### Option A: Supabase SQL Editor (no extra setup)

1. Open https://supabase.com/dashboard/project/xtkzughzlzrlggohhxbq/sql/new
2. Paste the contents of each migration file, in order (0001 → 0002 → 0003 → 0004).
3. Click **Run** for each.
4. Verify in the Table Editor — you should see the full schema.

### Option B: Direct connection via `apply.mjs`

Requires the database password (Supabase Dashboard → Project Settings → Database → Connection string).

```bash
export DATABASE_URL='postgresql://postgres:[PASSWORD]@db.xtkzughzlzrlggohhxbq.supabase.co:5432/postgres'
node db/apply.mjs
```

## Conventions

- All tenant-owned tables have `tenant_id uuid NOT NULL` and an RLS policy filtering on `current_tenant_id()`.
- All tables have `created_at`/`updated_at` and an `updated_at` trigger.
- Soft delete via `deleted_at` on user-facing entities. Hard delete on ephemeral.
- Money stored as `bigint` cents.
- Field roles must query the `projects_field_safe` view, never `projects` directly.
- Platform operator data (`admin_*`, `invite_links`, `cross_tenant_contract_patterns`) is RLS-gated to `is_platform_operator()`.

## Adding a new migration

1. Create `migrations/00NN_description.sql` with the next sequential number.
2. Write idempotent or strictly forward-only SQL — no destructive operations without an explicit data migration plan.
3. Apply in dev first, then production.
