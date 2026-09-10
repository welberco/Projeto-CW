-- CW ERP V2 / W1A: minimum non-recursive RLS helpers, policies and grants.

create function private.is_active_principal()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null
    and exists (
      select 1
      from public.app_users as app_user
      where app_user.id = auth.uid()
        and app_user.status = 'active'
    );
$$;

create function private.can_access_tenant(target_tenant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select target_tenant_id is not null
    and exists (
      select 1
      from public.app_users as app_user
      join public.tenant_memberships as membership
        on membership.user_id = app_user.id
       and membership.status = 'active'
      join public.tenants as tenant
        on tenant.id = membership.tenant_id
       and tenant.status = 'active'
      where app_user.id = auth.uid()
        and app_user.status = 'active'
        and tenant.id = target_tenant_id
    );
$$;

revoke all on function private.is_active_principal() from public;
revoke all on function private.is_active_principal() from anon;
revoke all on function private.is_active_principal() from authenticated;
revoke all on function private.can_access_tenant(uuid) from public;
revoke all on function private.can_access_tenant(uuid) from anon;
revoke all on function private.can_access_tenant(uuid) from authenticated;

grant usage on schema private to authenticated;
grant execute on function private.is_active_principal() to authenticated;
grant execute on function private.can_access_tenant(uuid) to authenticated;

create policy app_users_select_self
on public.app_users
for select
to authenticated
using (id = (select auth.uid()));

create policy tenants_select_operational_membership
on public.tenants
for select
to authenticated
using (private.can_access_tenant(id));

create policy tenant_memberships_select_self
on public.tenant_memberships
for select
to authenticated
using (user_id = (select auth.uid()));

create policy tenant_entitlements_select_operational_tenant
on public.tenant_entitlements
for select
to authenticated
using (private.can_access_tenant(tenant_id));

grant select on table public.app_users to authenticated;
grant select on table public.tenants to authenticated;
grant select on table public.tenant_memberships to authenticated;
grant select on table public.tenant_entitlements to authenticated;

comment on function private.is_active_principal() is
  'Derives the current application principal exclusively from auth.uid().';
comment on function private.can_access_tenant(uuid) is
  'Treats its argument only as a target and verifies current Auth identity, application lifecycle, membership and tenant status.';
