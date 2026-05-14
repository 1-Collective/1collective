-- Phase 1: extend custom_access_token_hook to inject impersonation claims.
--
-- When a platform operator has an active impersonation_session, the JWT issued
-- to them on token refresh gets:
--   tenant_id            = target's tenant_id  (so RLS scopes them to that tenant)
--   role_keys            = ['super_admin']     (so they have full power within it)
--   is_field_role        = false               (operators never field-scoped)
--   is_impersonating     = true                (so the UI shows the banner)
--   impersonating_user_id = target user UUID   (for banner display + audit context)
--   is_platform_operator = true                (preserved; they can still hit /admin)
--
-- This means the operator can navigate both /admin and /app/* during impersonation,
-- and the banner shows on every page.

CREATE OR REPLACE FUNCTION public.custom_access_token_hook(event jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid := (event ->> 'user_id')::uuid;
  v_tenant_id uuid;
  v_is_field boolean := false;
  v_role_keys text[];
  v_claims jsonb := event -> 'claims';
  v_imp_target_user_id uuid;
  v_imp_target_tenant_id uuid;
BEGIN
  -- 1. Standard tenant lookup
  SELECT tenant_id INTO v_tenant_id
  FROM public.users
  WHERE id = v_user_id;

  IF v_tenant_id IS NULL THEN
    -- 2. Not a tenant user. Probably a platform operator.
    IF EXISTS (SELECT 1 FROM public.platform_operators WHERE id = v_user_id) THEN
      v_claims := v_claims || jsonb_build_object('is_platform_operator', true);

      -- 3. Check active impersonation. If found, layer in tenant-context claims.
      SELECT i.target_user_id, i.target_tenant_id
        INTO v_imp_target_user_id, v_imp_target_tenant_id
        FROM public.impersonation_sessions i
       WHERE i.operator_id = v_user_id
         AND i.ended_at IS NULL
       ORDER BY i.started_at DESC
       LIMIT 1;

      IF v_imp_target_tenant_id IS NOT NULL THEN
        v_claims := v_claims
          || jsonb_build_object('tenant_id', v_imp_target_tenant_id::text)
          || jsonb_build_object('role_keys', jsonb_build_array('super_admin'))
          || jsonb_build_object('is_field_role', false)
          || jsonb_build_object('is_impersonating', true)
          || jsonb_build_object('impersonating_user_id', v_imp_target_user_id::text);
      END IF;
    END IF;
  ELSE
    -- 4. Tenant user
    SELECT
      coalesce(array_agg(r.key), array[]::text[]),
      coalesce(bool_or(r.is_field), false)
    INTO v_role_keys, v_is_field
    FROM public.user_role_assignments ura
    JOIN public.roles r ON r.id = ura.role_id
    WHERE ura.user_id = v_user_id
      AND ura.tenant_id = v_tenant_id;

    v_claims := v_claims
      || jsonb_build_object('tenant_id', v_tenant_id::text)
      || jsonb_build_object('role_keys', to_jsonb(v_role_keys))
      || jsonb_build_object('is_field_role', v_is_field);
  END IF;

  RETURN jsonb_build_object('claims', v_claims);
END;
$$;
</content>
</invoke>