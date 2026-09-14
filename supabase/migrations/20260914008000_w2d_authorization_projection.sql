-- CW ERP V2 / W2D: safe self authorization projection.

create function public.resolve_my_authorization()
returns table (
  projection_status text,
  principal_id uuid,
  tenant_id uuid,
  tenant_ref uuid,
  membership_id uuid,
  membership_version bigint,
  profile_id uuid,
  profile_version bigint,
  profile_name text,
  catalog_revision bigint,
  authorization_revision text,
  permission_codes text[],
  enabled_entitlements text[]
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
  resolved_profile public.tenant_profiles%rowtype;
  resolved_catalog_revision bigint;
  resolved_permission_codes text[];
  resolved_entitlements text[];
begin
  if resolved_principal_id is null then
    return query select
      'unauthenticated'::text, null::uuid, null::uuid, null::uuid,
      null::uuid, null::bigint, null::uuid, null::bigint, null::text,
      null::bigint, null::text, array[]::text[], array[]::text[];
    return;
  end if;

  select app_user.status
  into resolved_principal_status
  from public.app_users as app_user
  where app_user.id = resolved_principal_id;

  if not found or resolved_principal_status <> 'active' then
    return query select
      'principal_unavailable'::text, resolved_principal_id,
      null::uuid, null::uuid, null::uuid, null::bigint, null::uuid,
      null::bigint, null::text, null::bigint, null::text,
      array[]::text[], array[]::text[];
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
    return query select
      case
        when exists (
          select 1
          from public.tenant_memberships as historical_membership
          where historical_membership.user_id = resolved_principal_id
            and historical_membership.status = 'revoked'
        ) then 'membership_unavailable'::text
        else 'no_membership'::text
      end,
      resolved_principal_id, null::uuid, null::uuid, null::uuid,
      null::bigint, null::uuid, null::bigint, null::text, null::bigint,
      null::text, array[]::text[], array[]::text[];
    return;
  end if;

  if resolved_membership.status <> 'active' then
    return query select
      'membership_unavailable'::text, resolved_principal_id,
      null::uuid, null::uuid, null::uuid, null::bigint, null::uuid,
      null::bigint, null::text, null::bigint, null::text,
      array[]::text[], array[]::text[];
    return;
  end if;

  select tenant.*
  into resolved_tenant
  from public.tenants as tenant
  where tenant.id = resolved_membership.tenant_id;

  if not found or resolved_tenant.status <> 'active' then
    return query select
      'tenant_unavailable'::text, resolved_principal_id,
      null::uuid, null::uuid, null::uuid, null::bigint, null::uuid,
      null::bigint, null::text, null::bigint, null::text,
      array[]::text[], array[]::text[];
    return;
  end if;

  select profile.*
  into resolved_profile
  from public.tenant_profiles as profile
  where profile.id = resolved_membership.profile_id
    and profile.tenant_id = resolved_membership.tenant_id;

  if not found or resolved_profile.status <> 'active' then
    return query select
      'profile_unavailable'::text, resolved_principal_id,
      null::uuid, null::uuid, null::uuid, null::bigint, null::uuid,
      null::bigint, null::text, null::bigint, null::text,
      array[]::text[], array[]::text[];
    return;
  end if;

  select state.catalog_revision
  into resolved_catalog_revision
  from private.authorization_catalog_state as state
  where state.singleton;

  if resolved_catalog_revision is null then
    return query select
      'authorization_unavailable'::text, resolved_principal_id,
      null::uuid, null::uuid, null::uuid, null::bigint, null::uuid,
      null::bigint, null::text, null::bigint, null::text,
      array[]::text[], array[]::text[];
    return;
  end if;

  select coalesce(
    pg_catalog.array_agg(permission.code order by permission.code),
    array[]::text[]
  )
  into resolved_permission_codes
  from public.permission_catalog as permission
  where permission.id in (
    select effective_permission.permission_id
    from private.resolve_membership_permission_ids(
      resolved_membership.id,
      resolved_profile.id
    ) as effective_permission(permission_id)
  );

  select coalesce(
    pg_catalog.array_agg(entitlement.module_key order by entitlement.module_key),
    array[]::text[]
  )
  into resolved_entitlements
  from public.tenant_entitlements as entitlement
  where entitlement.tenant_id = resolved_tenant.id
    and entitlement.enabled;

  return query select
    'ready'::text,
    resolved_principal_id,
    resolved_tenant.id,
    resolved_tenant.tenant_ref,
    resolved_membership.id,
    resolved_membership.version,
    resolved_profile.id,
    resolved_profile.version,
    resolved_profile.name,
    resolved_catalog_revision,
    pg_catalog.format(
      'm%s:p%s:c%s',
      resolved_membership.version,
      resolved_profile.version,
      resolved_catalog_revision
    ),
    resolved_permission_codes,
    resolved_entitlements;
end;
$$;

revoke all on function public.resolve_my_authorization()
  from public, anon, authenticated, service_role;
grant execute on function public.resolve_my_authorization() to authenticated;

comment on function public.resolve_my_authorization() is
  'Read-only W2D self projection. Derives auth.uid(), exposes exact effective permission codes and the canonical membership/profile/catalog revision vector only for the current principal.';
