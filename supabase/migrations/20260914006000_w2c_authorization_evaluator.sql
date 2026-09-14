-- CW ERP V2 / W2C / W2-07: exact effective authorization evaluator.

create function private.resolve_effective_scopes(
  requested_resource_code text,
  requested_action_code text
)
returns setof public.authorization_scope
language sql
stable
security definer
set search_path = ''
as $$
  select distinct permission.scope
  from public.app_users as app_user
  join public.tenant_memberships as membership
    on membership.user_id = app_user.id
   and membership.status = 'active'
  join public.tenants as tenant
    on tenant.id = membership.tenant_id
   and tenant.status = 'active'
  join public.tenant_profiles as profile
    on profile.id = membership.profile_id
   and profile.tenant_id = membership.tenant_id
   and profile.status = 'active'
  join public.permission_catalog as permission
    on permission.resource_code = requested_resource_code
   and permission.action_code = requested_action_code
   and permission.status = 'active'
  left join public.tenant_profile_permissions as baseline
    on baseline.tenant_id = membership.tenant_id
   and baseline.profile_id = membership.profile_id
   and baseline.permission_id = permission.id
  left join public.tenant_permission_overrides as individual_override
    on individual_override.tenant_id = membership.tenant_id
   and individual_override.membership_id = membership.id
   and individual_override.permission_id = permission.id
  where app_user.id = auth.uid()
    and app_user.status = 'active'
    and (
      individual_override.effect = 'allow'
      or (individual_override.id is null and baseline.permission_id is not null)
    )
    and (
      permission.required_entitlement_key is null
      or exists (
        select 1
        from public.tenant_entitlements as entitlement
        where entitlement.tenant_id = membership.tenant_id
          and entitlement.module_key = permission.required_entitlement_key
          and entitlement.enabled
      )
    )
  order by permission.scope;
$$;

create function private.has_effective_permission(
  requested_resource_code text,
  requested_action_code text,
  requested_scope public.authorization_scope
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from private.resolve_effective_scopes(
      requested_resource_code,
      requested_action_code
    ) as effective_scope(scope)
    where effective_scope.scope = requested_scope
  );
$$;

create function private.resolve_profile_permission_ids(
  target_tenant_id uuid,
  target_profile_id uuid
)
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select permission.id
  from public.tenant_profiles as profile
  join public.tenant_profile_permissions as baseline
    on baseline.tenant_id = profile.tenant_id
   and baseline.profile_id = profile.id
  join public.permission_catalog as permission
    on permission.id = baseline.permission_id
   and permission.status = 'active'
  where profile.id = target_profile_id
    and profile.tenant_id = target_tenant_id
    and profile.status = 'active'
    and (
      permission.required_entitlement_key is null
      or exists (
        select 1
        from public.tenant_entitlements as entitlement
        where entitlement.tenant_id = profile.tenant_id
          and entitlement.module_key = permission.required_entitlement_key
          and entitlement.enabled
      )
    )
  order by permission.id;
$$;

create function private.resolve_membership_permission_ids(
  target_membership_id uuid,
  prospective_profile_id uuid
)
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select permission.id
  from public.tenant_memberships as membership
  join public.tenant_profiles as profile
    on profile.id = prospective_profile_id
   and profile.tenant_id = membership.tenant_id
   and profile.status = 'active'
  join public.permission_catalog as permission
    on permission.status = 'active'
  left join public.tenant_profile_permissions as baseline
    on baseline.tenant_id = membership.tenant_id
   and baseline.profile_id = profile.id
   and baseline.permission_id = permission.id
  left join public.tenant_permission_overrides as individual_override
    on individual_override.tenant_id = membership.tenant_id
   and individual_override.membership_id = membership.id
   and individual_override.permission_id = permission.id
  where membership.id = target_membership_id
    and (
      individual_override.effect = 'allow'
      or (individual_override.id is null and baseline.permission_id is not null)
    )
    and (
      permission.required_entitlement_key is null
      or exists (
        select 1
        from public.tenant_entitlements as entitlement
        where entitlement.tenant_id = membership.tenant_id
          and entitlement.module_key = permission.required_entitlement_key
          and entitlement.enabled
      )
    )
  order by permission.id;
$$;

create function private.can_delegate_permission(target_permission_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select permission.tenant_delegable
      and private.has_effective_permission(
        permission.resource_code,
        permission.action_code,
        permission.scope
      )
    from public.permission_catalog as permission
    where permission.id = target_permission_id
      and permission.status = 'active'
  ), false);
$$;

create function private.tenant_has_authorization_administrator(
  target_tenant_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.tenant_memberships as membership
    join public.app_users as app_user
      on app_user.id = membership.user_id
     and app_user.status = 'active'
    join public.tenants as tenant
      on tenant.id = membership.tenant_id
     and tenant.status = 'active'
    join public.tenant_profiles as profile
      on profile.id = membership.profile_id
     and profile.tenant_id = membership.tenant_id
     and profile.status = 'active'
    where membership.tenant_id = target_tenant_id
      and membership.status = 'active'
      and 11 = (
        select count(*)
        from private.resolve_membership_permission_ids(
          membership.id,
          membership.profile_id
        ) as effective_permission(permission_id)
        join public.permission_catalog as permission
          on permission.id = effective_permission.permission_id
        where permission.code = any (array[
          'core.users.read.all_tenant',
          'core.users.invite.all_tenant',
          'core.users.assign_profile.all_tenant',
          'core.users.manage_overrides.all_tenant',
          'core.users.change_status.all_tenant',
          'core.profiles.read.all_tenant',
          'core.profiles.create.all_tenant',
          'core.profiles.update.all_tenant',
          'core.profiles.activate.all_tenant',
          'core.profiles.inactivate.all_tenant',
          'core.profiles.change_permissions.all_tenant'
        ]::text[])
      )
  );
$$;

revoke all on function private.resolve_effective_scopes(text, text)
  from public, anon, authenticated, service_role;
revoke all on function private.has_effective_permission(text, text, public.authorization_scope)
  from public, anon, authenticated, service_role;
revoke all on function private.resolve_profile_permission_ids(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.resolve_membership_permission_ids(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.can_delegate_permission(uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.tenant_has_authorization_administrator(uuid)
  from public, anon, authenticated, service_role;

comment on function private.resolve_effective_scopes(text, text) is
  'AUTH-01 exact scope evaluator. It derives the principal and current tenant state from auth.uid(); scopes have no hierarchy.';
comment on function private.resolve_membership_permission_ids(uuid, uuid) is
  'Private prospective-set helper for W2C anti-escalation. It does not authorize a resource and is never client-executable.';
comment on function private.tenant_has_authorization_administrator(uuid) is
  'Fail-closed W2C lockout guard: at least one active member must retain the complete current core profiles/users administration set.';
