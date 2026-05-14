-- Tell Postgres the projects_field_safe view should run as the caller (not view owner),
-- so it isn't flagged as SECURITY DEFINER. We still keep security_barrier=true for the
-- planner-level leak prevention on the conditional financial columns.

alter view public.projects_field_safe set (security_invoker = true);
