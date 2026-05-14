-- Phase 1: track which users must set a new password on next sign-in.
-- Set by operators when they manually set/regenerate a password and want
-- the user to rotate it themselves. Cleared automatically on successful reset.

ALTER TABLE public.users
  ADD COLUMN password_reset_required boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN public.users.password_reset_required IS
  'When true, the next sign-in must redirect the user to the in-app set-new-password form before they can access the rest of the app. Cleared by the password-change flow.';

ALTER TABLE public.platform_operators
  ADD COLUMN password_reset_required boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN public.platform_operators.password_reset_required IS
  'When true, the next sign-in must redirect the operator to the in-app set-new-password form before they can access /admin. Cleared by the password-change flow.';
</content>
</invoke>