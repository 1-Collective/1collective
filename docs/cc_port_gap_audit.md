# Contractor Command → 1collective port gap audit

_Last updated: May 14, 2026._

This document tracks how much of Contractor Command (CC) has been ported into 1collective. CC source lives in `attached_assets/contractor_command_source_*.zip`. The CC backend has **136 route files**, **9 service libs**, and **1 cron scheduler**; the CC mobile app has **197 screens**.

Today, 1collective implements roughly **3–5%** of CC's surface area.

## Status legend

- **implemented** — schema applied, server actions written, UI built, tests pass
- **partial** — some pieces shipped (e.g. UI but no schema, or schema but no UI)
- **placeholder** — `ModuleShellPreview` page only, no schema or actions
- **missing** — no presence in 1collective at all (no page, no schema, no lib code, no registry entry)

## 1. Implemented (2 verticals)

| Module | CC source | 1collective surface |
|---|---|---|
| Vault | `vault.ts`, `storage.ts`, `upload.ts` | `db/migrations/0012_vault.sql`, `src/lib/vault/`, `src/app/(app)/app/vault/`, 26 tests, IDOR-hardened |
| OAuth token storage | `integrations.ts` | `cc_oauth_connections` table in `0011_foundational.sql`, `src/lib/integrations/` |

## 2. Placeholder shells (registry says `enabled: false`)

These render a pretty `ModuleShellPreview` page but have **zero schema, zero server actions, zero working code**.

| Module | CC route(s) needed | Rough scope |
|---|---|---|
| Estimating | `estimates.ts`, `estimateTemplates.ts`, `estimateBuilders.ts`, `takeoffs.ts`, `srMeasurements.ts`, `pricebook.ts`, `lineItemLibrary.ts`, `flatRateBundles.ts`, `proposalPdf.ts`, `proposals.ts`, `quotes.ts`, `estimatesPublic.ts` | XL — needs PDF lib, takeoffs UI, line-item catalog, e-sign |
| Invoicing | `invoices.ts`, `recurringInvoices.ts`, `payments.ts`, `receipts.ts`, `expenses.ts`, `stripe.ts` | L — needs Stripe wiring + recurring invoice cron |
| Projects | `projects.ts`, `jobNotes.ts`, `projectPhotos.ts`, `closeouts.ts`, `dailyLogs.ts`, `fieldReports.ts` | L |
| Manpower | `employees.ts`, `crewAssignments.ts`, `timeclock.ts`, `payroll.ts`, `timeOff.ts` | L |
| Booking | `bookingWidget.ts`, `bookingSlots.ts` | M — needs public widget host + Google Calendar availability |
| AI Phone | `daniella.ts`, `serana.ts`, `vapi.ts` | XL — needs Twilio + Vapi clients + AI core |
| Social | `amberSocial.ts`, `socialPosts.ts`, `socialMedia.ts` | L — needs Meta OAuth + amberPublisher |

## 3. Missing — entire verticals (no shell, no schema, no registry entry)

### Construction-specific billing (the trades differentiator)
- `aiaPayApp.ts` — AIA G702/G703 pay applications
- `retainage.ts` — retention tracking
- `lienWaivers.ts` — conditional/unconditional waivers
- `drawSchedules.ts` — progress-billing draw schedules
- `vendorInvoices.ts`, `subPayments.ts`, `financing.ts`

### Project execution
- `jobCosting.ts`, `jobCosts.ts`
- `changeOrders.ts`, `changeOrderSign.ts`
- `submittals.ts`, `subcontractors.ts`, `subBids.ts`
- `permits.ts`, `warranties.ts`, `serviceAgreements.ts`
- `projectEquipment.ts`, `renovation.ts`

### Crew & people
- `crewChat.ts`, `checkins.ts`
- `safety.ts`, `incidentReports.ts`
- `licenses.ts`, `insurance.ts` (COI tracker), `education.ts`
- `employeeNotify.ts`

### Equipment / fleet / inventory
- `fleet.ts`, `equipment.ts`, `equipmentMaintenance.ts`, `equipmentCheckout.ts`
- `mileage.ts`, `inventory.ts`, `materials.ts`

### Sales / marketing automation
- `funnels.ts`, `campaigns.ts`, `referrals.ts`, `followUpSequences.ts`
- `reviews.ts`, `reviewRequest.ts`, `marketing.ts`
- `automationRules.ts`, `alerts.ts`
- `customerProperties.ts`, `customerTimeline.ts`, `customerNotify.ts`

### AI tooling (~20 distinct features)
CC ships a deep AI catalog. None of these exist in 1collective:
- `aiIntelligence.ts`, `aiPhotoEstimate.ts`, `aiStaff.ts`, `aiUsage.ts`, `aiVoice.ts`
- `amberIntelligence.ts`, `amberBriefing.ts`, `seranaIntelligence.ts`
- `searchAI.ts`, `agentTasks.ts`
- Plus mobile-only AI screens: bidding coach, cashflow, change-order assistant, CLV, contract builder, contract review, crew optimizer, draft estimate, late-payment, lead pipeline, negotiate, profitability, seasonal, sentiment, sub scorecard, tax, upsell, voicemail triage

### Communications & content
- `gmail.ts`, `googleCalendar.ts`, `googleDrive.ts`, `googleBusiness.ts`, `googleBusinessManage.ts`, `calendarSync.ts`, `calendarEvents.ts`
- `youtube.ts`
- `smsConsent.ts`, `smsConversations.ts`, `notifications.ts`, `voiceNotes.ts`, `chat.ts`, `conversations.ts`
- `contentLibrary.ts`, `playbook.ts`

### Customer / employee portals
Entire app surfaces in CC (`(customer-portal)/`, `(employee-portal)/`, `client-portal/`, `clientPortal.ts`, `portal.ts`) — completely absent from 1collective.

### Analytics & reporting
- `analytics.ts`, `pnlDashboard.ts`, `profitabilityReport.ts`

### Misc
- `weather.ts`, `tasks.ts`, `tools.ts`, `toolConnections.ts`
- `pipeline.ts`, `dispatch.ts`, `rateSettings.ts`, `overhead.ts`

## 4. Cross-cutting infrastructure

CC ships these as `lib/` modules. Each one is a prerequisite for many of the verticals above.

| CC lib | Used by | 1coll equivalent |
|---|---|---|
| `pdfGenerator.ts` | Estimating, Invoicing, AIA pay apps, change orders, lien waivers | ✅ `src/lib/pdf/document-pdf.ts` (5 tests, dev sample at `/api/dev/sample-pdf`) |
| `email.ts` | Transactional email everywhere | ✅ `src/lib/email/` (Resend; throws `MissingCredentialsError` until `RESEND_API_KEY` set) |
| `sms.ts` + `twilio.ts` | AI Phone (Daniella), SMS conversations, customer notify | ✅ `src/lib/sms/` (Twilio; throws `MissingCredentialsError` until Twilio env set) |
| `vapi.ts` | AI Phone (Serana outbound) | **none** |
| `push.ts` | Mobile push notifications | **none** (deferred until mobile app lands) |
| `objectAcl.ts` | Shared docs beyond Vault's tenant-scoped model | **none** |
| `amberPublisher.ts` | Meta/IG/GBP social posting | **none** |
| `cron/scheduler.ts` | Recurring invoices, follow-ups, reminders, weather pulls | **none** |
| `encryption.ts` | OAuth token encryption | partial — `src/lib/integrations/` has token encryption only |
| `objectStorage.ts` | File uploads | partial — Supabase Storage in Vault only |

## 5. Suggested phased roadmap

### Phase 1 — Layer-zero infrastructure (unblocks everything else)
1. ✅ `src/lib/pdf/` — PDF generation (ported from `pdfGenerator.ts`)
2. ✅ `src/lib/email/` — transactional email (Resend factory)
3. ✅ `src/lib/sms/` — SMS via Twilio
4. `src/lib/cron/` — scheduled jobs (Vercel/Replit cron)
5. `src/lib/push/` — push notifications (when mobile lands)

### Phase 2 — Core trades verticals (revenue-critical, no good generic alternative)
6. **Estimating** end-to-end (catalog → builder → PDF → e-sign)
7. **Invoicing** end-to-end (drafts → send → Stripe payments → recurring)
8. **AIA / construction-billing** (pay apps, retainage, lien waivers, draw schedules)
9. **Change orders** with e-sign
10. **Projects + field reports + photos + daily logs**

### Phase 3 — Crew operations
11. **Manpower** (timeclock, crew assignments, payroll, time off)
12. **Crew chat + checkins**
13. **Safety + incident reports**
14. **Equipment / fleet / mileage**

### Phase 4 — Sales & marketing automation
15. **CRM detail views** (leads, customer timeline, properties)
16. **Funnels, campaigns, follow-up sequences**
17. **Referrals + reviews + review-request flow**
18. **Automation rules + alerts**

### Phase 5 — AI catalog
19. **AI core** (LLM clients + per-tenant usage metering)
20. **Daniella** inbound AI receptionist
21. **Serana** outbound AI calls
22. **Amber** social composer + scheduler
23. The 20-ish AI mobile tools (draft estimate, contract builder, profitability, etc.)

### Phase 6 — External surfaces
24. **Booking widget** (public)
25. **Customer portal** (public-facing per-customer view)
26. **Employee portal** (mobile crew view)

### Phase 7 — Compliance, analytics, content
27. **COI tracker, licenses, contracts, legal**
28. **Analytics, P&L, profitability reports, data export**
29. **Content library, playbook, education**

## 6. Tracking convention

As each module ships, update its row in this table and flip its `enabled` flag in `src/foundational/registry.ts`. Use the foundational module recipe in `DEVELOPMENT.md` for every port.

CC route filenames cited above all live at `/tmp/cc/artifacts/api-server/src/routes/*.ts` after extracting the source zip.
