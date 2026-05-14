-- Address security advisor warnings:
--   1) function_search_path_mutable: pin search_path on every function we defined
--   2) anon/authenticated_security_definer_function_executable: revoke public EXECUTE
--      from helper functions; they are only meant to be called from within RLS policies

-- (1) Pin search_path
alter function public.current_tenant_id()
  set search_path = public, pg_temp;

alter function public.set_updated_at()
  set search_path = public, pg_temp;

alter function public.enforce_user_operator_disjoint()
  set search_path = public, pg_temp;

alter function public.enforce_operator_user_disjoint()
  set search_path = public, pg_temp;

alter function public.custom_access_token_hook(jsonb)
  set search_path = public, pg_temp;

alter function public.is_platform_operator()
  set search_path = public, pg_temp;

alter function public.is_field_role()
  set search_path = public, pg_temp;

alter function public.field_user_can_see(uuid, text)
  set search_path = public, pg_temp;

alter function public.user_is_assigned_to_project(uuid)
  set search_path = public, pg_temp;

-- (2) Revoke EXECUTE from public on helper functions that should only be invoked
-- from inside RLS policies (running in the authenticated user's context via SECURITY DEFINER).
-- Internal Postgres execution still works since RLS policies run as superuser-equivalent.
revoke execute on function public.is_platform_operator()           from public;
revoke execute on function public.is_field_role()                  from public;
revoke execute on function public.field_user_can_see(uuid, text)   from public;
revoke execute on function public.user_is_assigned_to_project(uuid) from public;
revoke execute on function public.current_tenant_id()              from public;

-- supabase_auth_admin still needs custom_access_token_hook (grant remains)
-- supabase_auth_admin needs to use these helpers indirectly via the hook;
-- it does so by reading the underlying tables (granted in 0006), not by calling the helpers.
