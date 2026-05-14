import { notFound } from "next/navigation";

// Public self-service signup is disabled while One Collective is invite-only.
// Invite-link signup at /signup/[token] still works.
// Re-enable before publish — see PUBLISH_CHECKLIST.md C6.
export default function SignupPage() {
  notFound();
}
