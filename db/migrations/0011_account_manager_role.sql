-- Phase 1: Account Manager role + operator-to-tenant assignments.
-- An account_manager is a One Collective employee responsible for a specific set
-- of tenants. Super operators see/manage all tenants; account_managers only see
-- the tenants assigned to them via operator_tenant_assignments.

ALTER TYPE platform_operator_role ADD VALUE IF NOT EXISTS 'account_manager';
</content>
</invoke>