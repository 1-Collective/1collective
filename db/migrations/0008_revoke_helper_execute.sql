-- Revoke EXECUTE from anon + authenticated explicitly.
-- These helpers are only called from inside RLS policies; they should not be
-- exposed at /rest/v1/rpc/<name>.

revoke execute on function public.is_platform_operator()            from anon, authenticated;
revoke execute on function public.is_field_role()                   from anon, authenticated;
revoke execute on function public.field_user_can_see(uuid, text)    from anon, authenticated;
revoke execute on function public.user_is_assigned_to_project(uuid) from anon, authenticated;
revoke execute on function public.current_tenant_id()               from anon, authenticated;
