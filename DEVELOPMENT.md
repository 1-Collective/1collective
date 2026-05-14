# Development guide

## Architecture

One Collective is a multi-tenant Next.js 16 (App Router) + Supabase app.

- `src/app/(app)/app/*` — authenticated tenant workspace
- `src/app/(admin)/admin/*` — platform-operator portal
- `src/app/(onboarding)/*` — first-run wizard
- `src/app/login`, `signup/[token]`, `forgot-password`, `reset-password` — auth
- `src/app/page.tsx` + `error.tsx` + `not-found.tsx` + `loading.tsx` — public + global states
- `src/components/ui/*` — design-system primitives (Button, Card, Tabs, Sheet, Toast, …)
- `src/components/app-shell/*` — layout pieces shared by every authenticated page
- `src/lib/*` — pure-logic helpers and adapters
- `src/foundational/*` — registry-driven feature modules ported from Contractor Command
- `db/migrations/*` — versioned SQL applied to Supabase

## Foundational module pattern

Every module follows the same five-step recipe.

### 1. Register the module

In `src/foundational/registry.ts`, add an entry:

```ts
my_module: {
  key: "my_module",
  name: "My Module",
  enabled: false,                    // flip to true when end-to-end works
  requiredCredentials: ["MY_API_KEY"],
  notes: "What this module does.",
}
```

`enabled` flips on once the module's full vertical slice (DB → action → UI) is shipped. `requiredCredentials` is read by `/app/integrations` to show the "Setup required" banner.

### 2. Write the migration

Create `db/migrations/00NN_my_module.sql`:

- All tenant tables prefixed `cc_` (e.g. `cc_my_documents`)
- RLS enabled with `tenant_id = current_tenant_id() or is_platform_operator()`
- If rows hold paths/refs that grant elevated access, **revoke direct INSERT/UPDATE/DELETE from `authenticated`** and add a `CHECK` constraint binding the path to `tenant_id`. Writes go through server actions only. See `0012_vault.sql` for the canonical example.
- `updated_at` trigger + `(tenant_id, created_at desc)` index

### 3. Write the schemas + helpers

`src/lib/my-module/schemas.ts`:

- Zod input schemas for every action
- Pure helpers (path builders, ownership assertions) — these are unit-testable

### 4. Write the server actions

`src/lib/my-module/actions.ts` (`"use server"`):

Every action does this in order:
1. `ensureModuleEnabled()` — gate on `isModuleEnabled("my_module")`
2. `await requireTenantUser()` — auth gate
3. `parseForm(schema, formData)` — Zod validation
4. **Tenant-ownership check** — `row.tenant_id === session.tenantId`
5. **Runtime invariant** — e.g. `assertPathOwned(row.path, session.tenantId)` if you handle storage paths
6. The work
7. `log.info("my_module.thing.success", { tenant_id, user_id, ... })` — structured log
8. `revalidatePath("/app/my-module")`

External-service factories must `throw new MissingCredentialsError(...)` at call time, never at import time. This guarantees the app boots cleanly even with no credentials.

### 5. Build the page + tests

- `src/app/(app)/app/my-module/page.tsx` — server component, queries by `tenant_id` for defense in depth on top of RLS
- Client components in same folder for forms (use `useTransition` + `router.refresh()` after mutating actions)
- `src/lib/my-module/__tests__/schemas.test.ts` — unit-test every schema and helper, including IDOR guards
- Until the module is shipped, the page can use `<ModuleShellPreview>` from `src/components/app-shell/module-shell-preview.tsx` to render real-looking placeholder UI

## Quality bar

- `npm run typecheck` — must be clean
- `npm test` — all tests must pass
- `npm run lint` — zero errors, zero warnings (the `.local/` skill templates are correctly ignored)
- New files: no comments unless explaining a non-obvious *why*; no emojis in UI; edit existing files when possible

## Layer-zero infrastructure libs

These live in `src/lib/<name>/` and are consumed by feature modules. Each follows the `MissingCredentialsError`-at-call-time convention so the app boots cleanly with all keys blank.

| Lib | Module | Required env | Notes |
|---|---|---|---|
| PDF | `src/lib/pdf/document-pdf.ts` | _(none)_ | `pdfkit`-based, branded invoice/quote layout. Externalized via `serverExternalPackages: ["pdfkit"]` in `next.config.ts` so the AFM font files load at runtime. Dev smoke route: `/api/dev/sample-pdf` (gated on `ENABLE_DEV_LOGIN=1` + `NODE_ENV !== "production"`). |
| Email | `src/lib/email/index.ts` | `RESEND_API_KEY`, `EMAIL_FROM_ADDRESS` | Resend client cached lazily; thin `sendEmail({ to, subject, html | text })` wrapper. |
| SMS | `src/lib/sms/index.ts` | `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_FROM_NUMBER` | Twilio client cached lazily; `isE164()` helper exposed for shared validation. |

When porting a CC route that needs PDFs/email/SMS, import from these libs rather than re-wiring the third-party SDK.

## Local commands

```bash
npm run dev          # next dev on 0.0.0.0:5000
npm run typecheck    # tsc --noEmit
npm test             # vitest run
npm run test:watch   # vitest in watch mode
npm run lint         # eslint
npm run build        # production build
node scripts/seed-dev-account.mjs    # idempotently create dev@1collective.local
```

## Dev login shortcut

When `ENABLE_DEV_LOGIN=1` is set in the **development** environment (and `NODE_ENV !== "production"`), the `/login` page renders a "Sign in as developer" button that auto-signs into the seeded `dev@1collective.local` account. The flag is gated server-side at two layers and the button never renders in production builds.
