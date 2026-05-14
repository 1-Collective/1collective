# 1collective

Operations software for the trades — a back-office platform for blue-collar businesses (construction, HVAC, plumbing, electrical, landscaping, remodeling).

## Stack

- Next.js 16 (App Router) + TypeScript
- Tailwind CSS v4
- Dev server runs on port 5000, host 0.0.0.0

## Run

```bash
npm install
npm run dev
```

## Deploy

Configured as Replit Autoscale deployment:
- Build: `npm run build`
- Run: `npm run start` (binds 0.0.0.0:5000)

## Source of truth

GitHub: https://github.com/1-Collective/1collective

The working loop: Claude Code edits locally → push to GitHub → Replit pulls. Or: Replit Agent edits → push to GitHub → pull down in Claude Code.

## Code style

- No comments unless explaining a non-obvious *why*
- No premature abstractions, no speculative "utils" layers
- No error handling for cases that can't happen
- Edit existing files rather than creating new ones when possible
- No emojis in the UI

## Foundational module convention

Code ported from Contractor Command, or built fresh as part of the post-merge buildout, lives under `src/foundational/` and is tagged with a `// [CC-FOUNDATION]` header on the first line. Each module is registered in `src/foundational/registry.ts` with an `enabled` flag and a `requiredCredentials` array. Server Actions check `isModuleEnabled()` before executing; `/app/integrations` reads `missingCredentialsFor()` to surface "Setup required" banners. CC-only tables are prefixed `cc_` (e.g. `cc_oauth_connections`); tables that extend an existing 1collective table stay un-prefixed and add columns additively.

External-service factories (`src/lib/integrations/*.ts`) throw `MissingCredentialsError` at call time, never at module load. This guarantees the app boots and the workspace remains usable with all third-party credentials blank — affected pages render "Attention needed" instead of crashing.

## Sidebar information architecture

The app sidebar is grouped into business-flow sections (Marketing → Sales → Delivery → Accounting → Files → Admin), reflecting how a job moves through a trades business. Section headers are defined in `src/app/(app)/layout.tsx` as `NavSection[]`. The Sidebar component supports both flat `NavItem[]` (used by the admin portal) and grouped `NavSection[]` (used by the tenant app).
