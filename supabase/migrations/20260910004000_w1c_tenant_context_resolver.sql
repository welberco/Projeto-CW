-- CW ERP V2 / W1C: authoritative session and tenant-context resolver.

create function public.resolve_my_tenant_context(
  target_tenant_ref uuid default null
)
returns table (
  context_status text,
  principal_id uuid,
  tenant_id uuid,
  tenant_ref uuid,
  tenant_display_name text,
  membership_id uuid,
  membership_version bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  resolved_principal_id uuid := auth.uid();
  resolved_principal_status text;
  resolved_membership public.tenant_memberships%rowtype;
  resolved_tenant public.tenants%rowtype;
  maintenance_enabled boolean;
begin
  if resolved_principal_id is null then
    return query select 'unauthenticated'::text, null::uuid, null::uuid,
      null::uuid, null::text, null::uuid, null::bigint;
    return;
  end if;

  select app_user.status
  into resolved_principal_status
  from public.app_users as app_user
  where app_user.id = resolved_principal_id;

  if not found then
    return query select 'profile_missing'::text, resolved_principal_id,
      null::uuid, null::uuid, null::text, null::uuid, null::bigint;
    return;
  end if;

  if resolved_principal_status <> 'active' then
    return query select 'principal_unavailable'::text, resolved_principal_id,
      null::uuid, null::uuid, null::text, null::uuid, null::bigint;
    return;
  end if;

  select membership.*
  into resolved_membership
  from public.tenant_memberships as membership
  where membership.user_id = resolved_principal_id
    and membership.status in ('active', 'blocked')
  order by membership.created_at desc, membership.id
  limit 1;

  if not found then
    if exists (
      select 1
      from public.tenant_memberships as historical_membership
      where historical_membership.user_id = resolved_principal_id
        and historical_membership.status = 'revoked'
    ) then
      return query select 'membership_unavailable'::text,
        resolved_principal_id, null::uuid, null::uuid, null::text, null::uuid,
        null::bigint;
    else
      return query select 'no_membership'::text, resolved_principal_id,
        null::uuid, null::uuid, null::text, null::uuid, null::bigint;
    end if;
    return;
  end if;

  if resolved_membership.status <> 'active' then
    return query select 'membership_unavailable'::text,
      resolved_principal_id, null::uuid, null::uuid, null::text, null::uuid,
      null::bigint;
    return;
  end if;

  select tenant.*
  into resolved_tenant
  from public.tenants as tenant
  where tenant.id = resolved_membership.tenant_id;

  if not found or resolved_tenant.status <> 'active' then
    return query select 'tenant_unavailable'::text, resolved_principal_id,
      null::uuid, null::uuid, null::text, null::uuid, null::bigint;
    return;
  end if;

  select entitlement.enabled
  into maintenance_enabled
  from public.tenant_entitlements as entitlement
  where entitlement.tenant_id = resolved_tenant.id
    and entitlement.module_key = 'maintenance';

  if maintenance_enabled is distinct from true then
    return query select 'feature_unavailable'::text, resolved_principal_id,
      null::uuid, null::uuid, null::text, null::uuid, null::bigint;
    return;
  end if;

  if target_tenant_ref is not null
    and target_tenant_ref <> resolved_tenant.tenant_ref then
    return query select 'tenant_context_unavailable'::text,
      resolved_principal_id, null::uuid, null::uuid, null::text, null::uuid,
      null::bigint;
    return;
  end if;

  return query select 'ready'::text, resolved_principal_id,
    resolved_tenant.id, resolved_tenant.tenant_ref,
    resolved_tenant.display_name, resolved_membership.id,
    resolved_membership.version;
end;
$$;

revoke all on function public.resolve_my_tenant_context(uuid) from public;
revoke all on function public.resolve_my_tenant_context(uuid) from anon;
revoke all on function public.resolve_my_tenant_context(uuid) from authenticated;
grant execute on function public.resolve_my_tenant_context(uuid) to authenticated;

comment on function public.resolve_my_tenant_context(uuid) is
  'Resolves only the current Auth principal and its single authoritative W1 tenant context. The route reference is an opaque selector, never authority.';
