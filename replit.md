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

GitHub: https://github.com/jorge570/1collective

The working loop: Claude Code edits locally → push to GitHub → Replit pulls. Or: Replit Agent edits → push to GitHub → pull down in Claude Code.

## Code style

- No comments unless explaining a non-obvious *why*
- No premature abstractions, no speculative "utils" layers
- No error handling for cases that can't happen
- Edit existing files rather than creating new ones when possible
- No emojis in the UI
