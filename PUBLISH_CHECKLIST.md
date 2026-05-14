# PUBLISH CHECKLIST — One Collective

Living document tracking everything that must be addressed before deploying
1collective to production. Items grouped by severity. Update as items are
resolved.

Last audited: 2026-05-14 (commit `0893a31`).

---

## CRITICAL — must resolve before publish

### C1. Apply migration `0011_foundational.sql` to Supabase
- File: `db/migrations/0011_foundational.sql`
- Creates `cc_oauth_connections` (encrypted-at-rest OAuth token store) plus RLS policies.
- Action: run `node db/apply.mjs` against the prod Supabase, or apply via the Supabase dashboard SQL editor.
- Blocks: any future integration that needs to persist tenant OAuth tokens (QBO, Google, Meta, Vapi).

### C2. Generate and set `INTEGRATION_TOKEN_ENCRYPTION_KEY`
- Required by `src/lib/integrations/base.ts` (`encryptToken` / `decryptToken`).
- Without this, any code path that touches `cc_oauth_connections` will throw `MissingCredentialsError` at call time.
- Generate with: `openssl rand -base64 32`
- Set in Replit Secrets (and, after generation, add an empty entry to `.env.example`).
- Action: also add `INTEGRATION_TOKEN_ENCRYPTION_KEY=` to `.env.example` so future operators see it. **Done in this commit.**

### C3. Confirm Stripe is in **live** mode (or explicitly stay in test)
- Verify `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `STRIPE_PRICE_ID_STANDARD` are live-mode values in production secrets.
- Confirm the live webhook endpoint is registered with Stripe pointing at `https://<prod-domain>/api/webhooks/stripe`.
- Webhook signature validation is already in place at `src/app/api/webhooks/stripe/route.ts:17` (verified).

### C4. Set `NEXT_PUBLIC_APP_URL` to the actual production URL
- Currently falls back to `https://1-collective.replit.app` in `src/app/forgot-password/actions.ts` and `src/app/(app)/app/settings/account/actions.ts`.
- If the real prod URL differs, password-reset and email-change confirmation links will be broken.

### C6. User-flagged attention list — resolve each before publish

Five items the product owner has explicitly flagged as needing attention before launch. Some are net-new work, some are scope-confirmation gates. Resolve each with a yes/no/deferred verdict before flipping the publish switch.

**A. Account-security follow-ups (currently deferred — confirm verdict)**
- WebAuthn / passkeys (web "biometric"). Detail: see MEDIUM line 99.
- MFA / TOTP via Supabase Auth. Detail: see MEDIUM line 100.
- Account-deletion UI (multi-tenant safety logic for sole-super-admin transfer). Detail: see MEDIUM line 101.
- Verdict needed: ship v1 without these (current direction), or block publish until at least MFA + deletion ship?

**B. Resend wired for transactional email (currently deferred — confirm verdict)**
- Status: `RESEND_API_KEY` is in `.env.example` but no factory exists in `src/lib/integrations/`. Invite-link signup never emails the invitee; the trial-expiry warning has no email backstop. Detail: see HIGH line 80–82.
- Verdict needed: rely on Supabase's built-in email for v1 (current direction — note this means invites only work if you hand-deliver the link), or build the Resend factory + invite/trial-expiry templates before publish?

**C. Realtime / notifications / global search (currently post-launch)**
- Status: zero Supabase Realtime usage anywhere. No notification center. No global search. Detail: see HIGH line 84–91.
- Verdict needed: ship v1 SSR-only (current direction), or build at least the notification center before publish?

**D. Contractor Command repo — boundary**
- Rule: we do NOT touch the Contractor Command repo directly. CC code is only ported into `src/foundational/` with a `// [CC-FOUNDATION]` header. CC stays read-only as a reference.
- Pre-publish check: `rg "[CC-FOUNDATION]" src/foundational/` to confirm every ported file carries the tag. Any untagged file in `src/foundational/` is a process violation and must be tagged or moved.

**E. Shipping modules — no cosmetic refactors**
- Rule: Branding, CRM, Revenue, Drive, Onboarding, Billing-display work today. Do not touch them for cosmetics-only changes during the pre-publish push. Bug fixes only.
- Pre-publish check: review the git diff of each shipping module since this checkpoint; reject any change that is purely cosmetic or refactoring without a linked bug.

---

### C5. Audit sign-in / sign-up for bypasses before publish
- Confirm there is **no way to reach `/app/*`, `/admin/*`, or `/onboarding/*` without a valid Supabase session**. Currently enforced in two layers (`src/proxy.ts` middleware + per-layout `requireTenantUser()` checks) — verify both still hold after every auth-related change.
- Walk every public path in `src/proxy.ts:PUBLIC_PATHS` and confirm it cannot be turned into an authentication bypass:
  - `/`, `/login`, `/admin/login` — render only
  - `/signup`, `/signup/[token]` — create accounts but require email + password
  - `/forgot-password`, `/reset-password` — issue / consume Supabase reset tokens; verify the password-reset session expires correctly and cannot be exchanged for a long-lived session without setting a new password
  - `/auth/callback` — exchanges Supabase code → session; verify the open-redirect guard on `next` still rejects external URLs
- Confirm `signupViaInviteAction` correctly enforces invite-link `expires_at`, `disabled_at`, and `max_redemptions` (currently does — keep covered after refactor).
- Decide and lock down: is public self-service signup at `/signup` allowed in prod, or invite-only? If invite-only, remove the `/signup` route + the "Create a workspace" link in `/login`.
- **Delete the dev seed account before publish.** `scripts/seed-dev-account.mjs` provisions `dev@1collective.local / DevPassword123!` against whatever Supabase the script targets. Either delete the user from the prod project, or rotate the password to a value not stored in source. The script itself is harmless to keep around (requires `SUPABASE_SERVICE_ROLE_KEY` to run).
- Confirm Supabase email-confirmation requirement matches policy: `signupAction` and `signupViaInviteAction` both auto-confirm with `email_confirm: true`. If you want to require email verification on public signup before granting access, flip that flag and add a verification gate.
- Verify Supabase Auth provider settings in the prod project: password minimum length, leaked-password protection, allowed redirect URLs (must include `${NEXT_PUBLIC_APP_URL}/auth/callback`).

---

## HIGH — placeholder modules visible in product

These render as "Coming soon" in the sidebar. They will not crash, but a user clicking on them will hit an unimplemented page. Either build them out before launch or hide their sidebar entries via a feature flag for the v1 release.

| Module | Path | Sidebar section |
|---|---|---|
| Vault | `src/app/(app)/app/vault/page.tsx` | Files |
| Invoicing | `src/app/(app)/app/invoicing/page.tsx` | Accounting |
| Manpower | `src/app/(app)/app/manpower/page.tsx` | Delivery |
| Projects | `src/app/(app)/app/projects/page.tsx` | Delivery |
| Social | `src/app/(app)/app/social/page.tsx` | Marketing |
| AI Phone | `src/app/(app)/app/ai-phone/page.tsx` | Sales |
| Booking | `src/app/(app)/app/booking/page.tsx` | Marketing |
| Integrations | `src/app/(app)/app/integrations/page.tsx` | Admin (functional — shows live setup status, no action items) |

Phased build sequence (already agreed): Foundation → Vault → AI Core → AI Phone → Booking → Social → Google → QuickBooks + Invoicing.

## HIGH — backend integrations are scaffolded but not wired

`src/lib/integrations/` contains only `base.ts` (errors + crypto helpers). The actual per-service factories that the foundational registry advertises do not exist yet.

| Service | Status | Required env (when built) |
|---|---|---|
| Anthropic (Claude) | `src/lib/ai/client.ts` exists, basic | `ANTHROPIC_API_KEY` (in `.env.example`) |
| OpenAI | not implemented | `OPENAI_API_KEY` (missing from `.env.example` — add when needed) |
| Twilio (voice + SMS) | not implemented | `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_VOICE_WEBHOOK_BASE_URL` |
| Vapi | not implemented | `VAPI_PRIVATE_KEY`, `VAPI_PUBLIC_KEY` |
| Google OAuth (Calendar + Drive + GBP) | not implemented | `GOOGLE_OAUTH_CLIENT_ID/SECRET/REDIRECT_URI` |
| QuickBooks Online | not implemented | `QBO_CLIENT_ID/SECRET/REDIRECT_URI/ENVIRONMENT` |
| Meta (Facebook + Instagram) | not implemented | `META_APP_ID`, `META_APP_SECRET`, `META_OAUTH_REDIRECT_URI` |
| Resend (transactional email) | **not implemented** despite being in `.env.example` — invites and trial-expiry emails currently do not send | `RESEND_API_KEY` |

**Resend gap is most pressing** — invite-link signup never actually emails the invitee, and the 30-day trial-expiry warning surfaced in the layout has no email backstop.

## HIGH — no real-time features

`rg "channel\(|postgres_changes|broadcast"` returns zero hits. Notifications, multi-user editing, live job-cost updates, and any "live" surfacing of crew location are all SSR-only at the moment. Consider before launch:
- Notifications: any new lead / invoice / message should real-time push to the recipient
- Crew chat (Manpower): polling is unacceptable
- Project status changes: should propagate without refresh

Decision: Supabase Realtime is the cheapest path (built-in, RLS-aware). Defer until at least one consuming surface (Notifications) is built.

---

## MEDIUM — auth flows that exist but need follow-up

| Item | Status | Notes |
|---|---|---|
| WebAuthn / passkeys (web "biometric") | not built | Direct port of CC's biometric ask, web-style. Needs a `cc_passkeys` table + `@simplewebauthn/server` library. ~1 dedicated turn. |
| MFA / TOTP | not built | Supabase Auth supports natively; UI not wired. |
| Account deletion UI | intentionally deferred | Multi-tenant safety logic (sole-super-admin transfer) needs design. Currently Settings → Account shows "contact admin". |
| Email verification gate on signup | not enforced | `signupAction` auto-confirms via `email_confirm: true`. Acceptable for invite-link flow; consider tightening for public self-service signup. |
| Signup is non-transactional | reliability debt | `signupAction` performs ~6 sequential inserts without rollback. Partial failure can leave orphan rows. Refactor when extracting the shared `provisionTenantForUser` helper. |
| Magic-link login | not built | Supabase native; ~30-min UI lift. Optional. |

## MEDIUM — auth/operational policy items

- **Public signup is wide open.** `/signup` allows anyone with an email + password to create a tenant. If the GTM plan is invite-only, hide the route and remove the "Create a workspace" link from `/login`.
- **Rate limiting on auth endpoints** — Supabase has some built-in protections but no per-IP throttling at the app layer. Not blocking, monitor abuse.

## MEDIUM — env var hygiene

Every entry below is missing from `.env.example` but required by registered modules. Adding empty entries (done in this commit) so operators see the full surface area:
- `INTEGRATION_TOKEN_ENCRYPTION_KEY` (CRITICAL — see C2)
- `OPENAI_API_KEY` (for AI core, when enabled)
- `VAPI_PRIVATE_KEY`, `VAPI_PUBLIC_KEY` (for Serana outbound calls)
- `META_APP_ID`, `META_APP_SECRET`, `META_OAUTH_REDIRECT_URI` (for Amber social)
- `GOOGLE_OAUTH_REDIRECT_URI` (paired with the existing `GOOGLE_OAUTH_CLIENT_*`)
- `QBO_REDIRECT_URI` (paired with the existing `QBO_CLIENT_*`)
- `TWILIO_VOICE_WEBHOOK_BASE_URL` (for Daniella inbound webhooks)

## MEDIUM — high-value CC features deferred (not lost, not blocking publish)

- AI-powered global search (semantic across customers, projects, docs)
- In-app notification center + persisted notification log
- Server-side PDF generation (lands with Estimating port)
- Excel export
- AI job costing
- i18n (Spanish/English) — high value for trades workforce

---

## LOW

- Old `/app/settings/connectors` page still exists alongside the new `/app/integrations` page. Either decommission `/connectors` or redirect it. Currently `/app/settings` no longer links to `/connectors` (links to `/integrations`).
- Hardcoded fallback URL `https://1-collective.replit.app` in two action files. Acceptable as long as `NEXT_PUBLIC_APP_URL` is set in prod.
- `cc_*` table prefix convention documented in `replit.md` but `0011_foundational.sql` is the only migration using it so far. Watch for drift as more CC tables land.

---

## VERIFIED CLEAN — auditor false positives

Items the audit subagent flagged that I verified are NOT issues:
- "Broken `href="#"` links in connectors page" — none exist; the connectors page uses dynamic `actionHref`.
- "Missing tables (`integration_events`, `google_drive_connections`, `qbo_connections`, `email_accounts`, `tenant_bids_setup`, `brand_content`, `revenue_history`)" — all defined in existing migrations.
- "Stripe webhook lacks signature verification" — `constructEvent()` is called at `src/app/api/webhooks/stripe/route.ts:17`.
- "Service role key leaking client-side" — only used in `src/lib/supabase/admin.ts`, server-only via `import "server-only"` chain.
