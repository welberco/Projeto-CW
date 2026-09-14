-- CW ERP V2 / W2E: least-privilege closure for authorization infrastructure.

-- W1 operational RPCs are the only service-role boundary. Direct table access
-- could otherwise bypass W2C authorization commands and their audit contract.
revoke all privileges on table public.app_users from service_role;
revoke all privileges on table public.tenants from service_role;
revoke all privileges on table public.tenant_memberships from service_role;
revoke all privileges on table public.tenant_invitations from service_role;
revoke all privileges on table public.tenant_entitlements from service_role;
revoke all privileges on table public.audit_events from service_role;

-- The tenant-context resolver is a self projection for authenticated clients,
-- not a technical service-role operation.
revoke all on function public.resolve_my_tenant_context(uuid) from service_role;

-- Supabase starts with permissive defaults for objects created in public.
-- V2 requires every API-facing grant to be explicit, including future objects.
alter default privileges for role postgres in schema public
  revoke all on tables from public, anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke all on sequences from public, anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon, authenticated, service_role;
alter default privileges for role postgres in schema private
  revoke all on tables from public, anon, authenticated, service_role;
alter default privileges for role postgres in schema private
  revoke all on sequences from public, anon, authenticated, service_role;
alter default privileges for role postgres in schema private
  revoke execute on functions from public, anon, authenticated, service_role;

comment on function public.resolve_my_tenant_context(uuid) is
  'Authenticated self resolver. The route reference is only a selector; service_role has no functional projection grant.';
