-- Phase 1: which Account Managers handle which tenants.

CREATE TABLE public.operator_tenant_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  operator_id uuid NOT NULL REFERENCES public.platform_operators(id) ON DELETE CASCADE,
  tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  assigned_by uuid REFERENCES public.platform_operators(id),
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  removed_at timestamptz,
  UNIQUE (operator_id, tenant_id)
);

CREATE INDEX operator_tenant_assignments_operator_active_idx
  ON public.operator_tenant_assignments(operator_id)
  WHERE removed_at IS NULL;
CREATE INDEX operator_tenant_assignments_tenant_idx
  ON public.operator_tenant_assignments(tenant_id);

ALTER TABLE public.operator_tenant_assignments ENABLE ROW LEVEL SECURITY;

-- Only operators can read/write this table. (Tenants never see operator-side data.)
CREATE POLICY operator_tenant_assignments_all ON public.operator_tenant_assignments
  FOR ALL USING (is_platform_operator())
  WITH CHECK (is_platform_operator());

-- Helper: does the current operator have access to this tenant?
-- Used by future RLS policies and Server Actions for AM-scoped queries.
CREATE OR REPLACE FUNCTION public.operator_can_access_tenant(p_tenant_id uuid)
  RETURNS boolean
  LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path = public, pg_temp
  AS $$
  SELECT
    CASE
      WHEN NOT is_platform_operator() THEN false
      WHEN EXISTS (
        SELECT 1 FROM public.platform_operators
        WHERE id = auth.uid() AND operator_role = 'super'
      ) THEN true
      ELSE EXISTS (
        SELECT 1 FROM public.operator_tenant_assignments
        WHERE operator_id = auth.uid()
          AND tenant_id = p_tenant_id
          AND removed_at IS NULL
      )
    END;
$$;
REVOKE EXECUTE ON FUNCTION public.operator_can_access_tenant(uuid) FROM public, anon, authenticated;
