-- Phase 1: impersonation_sessions tracks active "View as" sessions.
-- The JWT hook reads this to inject the target user's tenant context
-- into the operator's session. The audit log writes records on start/stop.

CREATE TABLE public.impersonation_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  operator_id uuid NOT NULL REFERENCES public.platform_operators(id) ON DELETE CASCADE,
  target_user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  target_tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  reason text,
  started_at timestamptz NOT NULL DEFAULT now(),
  ended_at timestamptz
);

CREATE UNIQUE INDEX impersonation_sessions_one_active_per_operator_idx
  ON public.impersonation_sessions(operator_id)
  WHERE ended_at IS NULL;
CREATE INDEX impersonation_sessions_target_user_idx
  ON public.impersonation_sessions(target_user_id);
CREATE INDEX impersonation_sessions_tenant_idx
  ON public.impersonation_sessions(target_tenant_id);

ALTER TABLE public.impersonation_sessions ENABLE ROW LEVEL SECURITY;

-- Operators see/write only their own impersonation records.
-- Super operators see all (for audit / oversight).
CREATE POLICY impersonation_sessions_self_or_super ON public.impersonation_sessions
  FOR ALL USING (
    operator_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.platform_operators
      WHERE id = auth.uid() AND operator_role = 'super'
    )
  )
  WITH CHECK (operator_id = auth.uid());

-- The JWT hook (running as supabase_auth_admin) needs to read this table
-- to know whether to apply impersonation claims.
GRANT SELECT ON public.impersonation_sessions TO supabase_auth_admin;

ALTER TABLE public.impersonation_sessions FORCE ROW LEVEL SECURITY;
CREATE POLICY auth_admin_read ON public.impersonation_sessions
  FOR SELECT TO supabase_auth_admin
  USING (true);
</content>
</invoke>