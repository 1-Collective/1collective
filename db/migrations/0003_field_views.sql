-- One Collective: field-role security-barrier view.
-- Field roles query projects_field_safe, never the base projects table.
-- Sensitive financial columns are conditionally exposed based on
-- project_field_overrides.

create or replace view projects_field_safe with (security_barrier = true) as
select
  p.id,
  p.tenant_id,
  p.company_id,
  p.name,
  p.project_number,
  p.trade_types,
  p.region,
  p.stage,
  p.stage_entered_at,
  p.percent_complete,
  p.projected_completion_date,
  p.actual_completion_date,
  p.bid_submitted_at,
  p.contract_awarded_at,
  p.status,
  p.description,
  -- Sensitive financial fields: returned only if override exists for this user/project
  case when field_user_can_see(p.id, 'contract_value_cents')
       then p.contract_value_cents end as contract_value_cents,
  case when field_user_can_see(p.id, 'billed_to_date_cents')
       then p.billed_to_date_cents end as billed_to_date_cents,
  case when field_user_can_see(p.id, 'amount_remaining_cents')
       then p.amount_remaining_cents end as amount_remaining_cents,
  case when field_user_can_see(p.id, 'custom_fields')
       then p.custom_fields end as custom_fields,
  p.created_at,
  p.updated_at
from projects p
where
  is_platform_operator()
  or (
    p.tenant_id = current_tenant_id()
    and (
      not is_field_role()
      or user_is_assigned_to_project(p.id)
    )
  )
  and p.deleted_at is null;

grant select on projects_field_safe to authenticated;
grant select on projects_field_safe to anon;

comment on view projects_field_safe is
  'Field-safe projection of projects. Field roles MUST query this view rather than the base projects table. Sensitive financial fields are returned as NULL unless a project_field_overrides row grants visibility.';
