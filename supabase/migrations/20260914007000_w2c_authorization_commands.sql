-- CW ERP V2 / W2C / W2-08: authenticated governance commands.

create function private.require_authorization_reason(command_reason text)
returns void
language plpgsql
immutable
set search_path = ''
as $$
begin
  if command_reason is null
     or command_reason <> pg_catalog.btrim(command_reason)
     or pg_catalog.char_length(command_reason) not between 1 and 500 then
    raise exception using errcode = '22023', message = 'INVALID_AUTHORIZATION_REASON';
  end if;
end;
$$;

create function private.lock_authorization_actor(
  required_resource_code text,
  required_action_code text
)
returns table (
  actor_user_id uuid,
  actor_tenant_id uuid,
  actor_membership_id uuid,
  actor_profile_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  principal_id uuid := auth.uid();
  resolved_tenant_id uuid;
begin
  if principal_id is null then
    raise exception using errcode = '28000', message = 'AUTHENTICATION_REQUIRED';
  end if;

  select membership.tenant_id
  into resolved_tenant_id
  from public.tenant_memberships as membership
  where membership.user_id = principal_id
    and membership.status = 'active';

  if resolved_tenant_id is null then
    raise exception using errcode = 'P0001', message = 'AUTHORIZATION_OPERATION_UNAVAILABLE';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(resolved_tenant_id::text, 0)
  );

  return query
  select
    app_user.id,
    tenant.id,
    membership.id,
    profile.id
  from public.tenants as tenant
  join public.tenant_memberships as membership
    on membership.tenant_id = tenant.id
   and membership.user_id = principal_id
   and membership.status = 'active'
  join public.app_users as app_user
    on app_user.id = membership.user_id
   and app_user.status = 'active'
  join public.tenant_profiles as profile
    on profile.id = membership.profile_id
   and profile.tenant_id = membership.tenant_id
   and profile.status = 'active'
  where tenant.id = resolved_tenant_id
    and tenant.status = 'active'
  for update of tenant, membership, app_user, profile;

  if not found then
    raise exception using errcode = 'P0001', message = 'AUTHORIZATION_OPERATION_UNAVAILABLE';
  end if;

  if not private.has_effective_permission(
    required_resource_code,
    required_action_code,
    'ALL_TENANT'::public.authorization_scope
  ) then
    raise exception using errcode = '42501', message = 'AUTHORIZATION_DENIED';
  end if;
end;
$$;

create function private.assert_tenant_has_authorization_administrator(
  target_tenant_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.tenant_has_authorization_administrator(target_tenant_id) then
    raise exception using errcode = '23514', message = 'LAST_AUTHORIZATION_ADMIN_REQUIRED';
  end if;
end;
$$;

create function private.write_authorization_audit(
  target_tenant_id uuid,
  actor_user_id uuid,
  command_correlation_id uuid,
  command_event_type text,
  target_entity_type text,
  target_entity_id uuid,
  command_reason text,
  command_metadata jsonb default '{}'::jsonb
)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.audit_events (
    tenant_id, actor_user_id, actor_kind, correlation_id,
    event_type, entity_type, entity_id, metadata
  ) values (
    target_tenant_id, actor_user_id, 'application_user', command_correlation_id,
    command_event_type, target_entity_type, target_entity_id,
    pg_catalog.jsonb_build_object('reason', command_reason) || command_metadata
  );
$$;

create function public.create_tenant_profile(
  profile_name text,
  command_reason text,
  correlation_id uuid default pg_catalog.gen_random_uuid()
)
returns table (profile_id uuid, profile_version bigint, command_correlation_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor record;
  created_profile_id uuid;
  created_profile_version bigint;
begin
  perform private.require_authorization_reason(command_reason);
  if correlation_id is null then
    raise exception using errcode = '22023', message = 'CORRELATION_ID_REQUIRED';
  end if;
  if profile_name is null
     or profile_name <> pg_catalog.btrim(profile_name)
     or pg_catalog.char_length(profile_name) not between 1 and 120 then
    raise exception using errcode = '22023', message = 'INVALID_PROFILE_NAME';
  end if;

  select * into actor from private.lock_authorization_actor('profiles', 'create');

  insert into public.tenant_profiles (
    tenant_id, name, status, created_by, updated_by
  ) values (
    actor.actor_tenant_id, profile_name, 'active',
    actor.actor_user_id, actor.actor_user_id
  )
  returning id, version into created_profile_id, created_profile_version;

  perform private.write_authorization_audit(
    actor.actor_tenant_id, actor.actor_user_id, correlation_id,
    'authorization.profile_created', 'tenant_profile', created_profile_id,
    command_reason,
    pg_catalog.jsonb_build_object('profile_version', created_profile_version)
  );

  return query select created_profile_id, created_profile_version, correlation_id;
exception
  when unique_violation then
    raise exception using errcode = 'P0001', message = 'AUTHORIZATION_OPERATION_UNAVAILABLE';
end;
$$;

create function public.update_tenant_profile(
  target_profile_id uuid,
  expected_profile_version bigint,
  profile_name text,
  command_reason text,
  correlation_id uuid default pg_catalog.gen_random_uuid()
)
returns table (profile_id uuid, profile_version bigint, command_correlation_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor record;
  current_profile public.tenant_profiles%rowtype;
  resulting_version bigint;
begin
  perform private.require_authorization_reason(command_reason);
  if correlation_id is null or expected_profile_version is null or expected_profile_version < 1 then
    raise exception using errcode = '22023', message = 'INVALID_COMMAND_VERSION';
  end if;
  if profile_name is null
     or profile_name <> pg_catalog.btrim(profile_name)
     or pg_catalog.char_length(profile_name) not between 1 and 120 then
    raise exception using errcode = '22023', message = 'INVALID_PROFILE_NAME';
  end if;

  select * into actor from private.lock_authorization_actor('profiles', 'update');

  select profile.* into current_profile
  from public.tenant_profiles as profile
  where profile.id = target_profile_id
    and profile.tenant_id = actor.actor_tenant_id
  for update;

  if current_profile.id is null then
    raise exception using errcode = 'P0001', message = 'AUTHORIZATION_OPERATION_UNAVAILABLE';
  end if;
  if current_profile.version <> expected_profile_version then
    raise exception using errcode = '40001', message = 'AUTHORIZATION_VERSION_CONFLICT';
  end if;

  update public.tenant_profiles as profile
  set name = profile_name,
      updated_by = actor.actor_user_id
  where profile.id = current_profile.id
  returning profile.version into resulting_version;

  perform private.write_authorization_audit(
    actor.actor_tenant_id, actor.actor_user_id, correlation_id,
    'authorization.profile_updated', 'tenant_profile', current_profile.id,
    command_reason,
    pg_catalog.jsonb_build_object(
      'previous_name', current_profile.name,
      'new_name', profile_name,
      'previous_version', current_profile.version,
      'profile_version', resulting_version
    )
  );

  return query select current_profile.id, resulting_version, correlation_id;
exception
  when unique_violation then
    raise exception using errcode = 'P0001', message = 'AUTHORIZATION_OPERATION_UNAVAILABLE';
end;
$$;

create function public.change_tenant_profile_status(
  target_profile_id uuid,
  expected_profile_version bigint,
  target_status text,
  command_reason text,
  correlation_id uuid default pg_catalog.gen_random_uuid()
)
returns table (profile_id uuid, profile_status text, profile_version bigint, command_correlation_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor record;
  current_profile public.tenant_profiles%rowtype;
  resulting_version bigint;
begin
  perform private.require_authorization_reason(command_reason);
  if correlation_id is null or expected_profile_version is null or expected_profile_version < 1 then
    raise exception using errcode = '22023', message = 'INVALID_COMMAND_VERSION';
  end if;
  if target_status not in ('active', 'inactive') then
    raise exception using errcode = '22023', message = 'INVALID_PROFILE_STATUS';
  end if;

  select * into actor
  from private.lock_authorization_actor(
    'profiles', case when target_status = 'active' then 'activate' else 'inactivate' end
  );

  select profile.* into current_profile
  from public.tenant_profiles as profile
  where profile.id = target_profile_id
    and profile.tenant_id = actor.actor_tenant_id
  for update;

  if current_profile.id is null or current_profile.status = target_status then
    raise exception using errcode = 'P0001', message = 'AUTHORIZATION_OPERATION_UNAVAILABLE';
  end if;
  if current_profile.version <> expected_profile_version then
    raise exception using errcode = '40001', message = 'AUTHORIZATION_VERSION_CONFLICT';
  end if;

  update public.tenant_profiles as profile
  set status = target_status,
      inactivated_at = case when target_status = 'inactive' then statement_timestamp() else null end,
      updated_by = actor.actor_user_id
  where profile.id = current_profile.id
  returning profile.version into resulting_version;

  if target_status = 'inactive' then
    perform private.assert_tenant_has_authorization_administrator(actor.actor_tenant_id);
  end if;

  perform private.write_authorization_audit(
    actor.actor_tenant_id, actor.actor_user_id, correlation_id,
    'authorization.profile_status_changed', 'tenant_profile', current_profile.id,
    command_reason,
    pg_catalog.jsonb_build_object(
      'previous_status', current_profile.status,
      'new_status', target_status,
      'previous_version', current_profile.version,
      'profile_version', resulting_version
    )
  );

  return query select current_profile.id, target_status, resulting_version, correlation_id;
exception
  when unique_violation then
    raise exception using errcode = 'P0001', message = 'AUTHORIZATION_OPERATION_UNAVAILABLE';
end;
$$;

create function public.set_tenant_profile_permission(
  target_profile_id uuid,
  target_permission_id uuid,
  target_allowed boolean,
  expected_profile_version bigint,
  command_reason text,
  correlation_id uuid default pg_catalog.gen_random_uuid()
)
returns table (profile_id uuid, permission_id uuid, allowed boolean, profile_version bigint, command_correlation_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor record;
  current_profile public.tenant_profiles%rowtype;
  permission_exists boolean;
  baseline_exists boolean;
  resulting_version bigint;
begin
  perform private.require_authorization_reason(command_reason);
  if correlation_id is null or expected_profile_version is null or expected_profile_version < 1
     or target_allowed is null then
    raise exception using errcode = '22023', message = 'INVALID_COMMAND_VERSION';
  end if;

  select * into actor
  from private.lock_authorization_actor('profiles', 'change_permissions');

  select profile.* into current_profile
  from public.tenant_profiles as profile
  where profile.id = target_profile_id
    and profile.tenant_id = actor.actor_tenant_id
    and profile.status = 'active'
  for update;

  if current_profile.id is null then
    raise exception using errcode = 'P0001', message = 'AUTHORIZATION_OPERATION_UNAVAILABLE';
  end if;
  if current_profile.version <> expected_profile_version then
    raise exception using errcode = '40001', message = 'AUTHORIZATION_VERSION_CONFLICT';
  end if;

  select true into permission_exists
  from public.permission_catalog as permission
  where permission.id = target_permission_id
    and permission.status = 'active'
  for share;

  if not coalesce(permission_exists, false) then
    raise exception using errcode = 'P0001', message = 'AUTHORIZATION_OPERATION_UNAVAILABLE';
  end if;

  select exists (
    select 1
    from public.tenant_profile_permissions as baseline
    where baseline.tenant_id = actor.actor_tenant_id
      and baseline.profile_id = current_profile.id
      and baseline.permission_id = target_permission_id
  ) into baseline_exists;

  if baseline_exists = target_allowed then
    raise exception using errcode = 'P0001', message = 'AUTHORIZATION_OPERATION_UNAVAILABLE';
  end if;

  if target_allowed and not private.can_delegate_permission(target_permission_id) then
    raise exception using errcode = '42501', message = 'AUTHORIZATION_DELEGATION_DENIED';
  end if;

  if target_allowed then
    insert into public.tenant_profile_permissions (
      tenant_id, profile_id, permission_id, created_by
    ) values (
      actor.actor_tenant_id, current_profile.id, target_permission_id, actor.actor_user_id
    );
  else
    delete from public.tenant_profile_permissions as baseline
    where baseline.tenant_id = actor.actor_tenant_id
      and baseline.profile_id = current_profile.id
      and baseline.permission_id = target_permission_id;

    perform private.assert_tenant_has_authorization_administrator(actor.actor_tenant_id);
  end if;

  select profile.version into resulting_version
  from public.tenant_profiles as profile
  where profile.id = current_profile.id;

  perform private.write_authorization_audit(
    actor.actor_tenant_id, actor.actor_user_id, correlation_id,
    'authorization.profile_permission_changed', 'tenant_profile', current_profile.id,
    command_reason,
    pg_catalog.jsonb_build_object(
      'permission_id', target_permission_id,
      'allowed', target_allowed,
      'previous_version', current_profile.version,
      'profile_version', resulting_version
    )
  );

  return query
  select current_profile.id, target_permission_id, target_allowed, resulting_version, correlation_id;
end;
$$;

create function public.assign_tenant_membership_profile(
  target_membership_id uuid,
  target_profile_id uuid,
  expected_membership_version bigint,
  command_reason text,
  correlation_id uuid default pg_catalog.gen_random_uuid()
)
returns table (membership_id uuid, profile_id uuid, membership_version bigint, command_correlation_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor record;
  current_membership public.tenant_memberships%rowtype;
  target_profile public.tenant_profiles%rowtype;
  elevated_permission_id uuid;
  resulting_version bigint;
begin
  perform private.require_authorization_reason(command_reason);
  if correlation_id is null or expected_membership_version is null or expected_membership_version < 1 then
    raise exception using errcode = '22023', message = 'INVALID_COMMAND_VERSION';
  end if;

  select * into actor
  from private.lock_authorization_actor('users', 'assign_profile');

  select membership.* into current_membership
  from public.tenant_memberships as membership
  where membership.id = target_membership_id
    and membership.tenant_id = actor.actor_tenant_id
    and membership.status in ('active', 'blocked')
  for update;

  if current_membership.id is null or current_membership.profile_id = target_profile_id then
    raise exception using errcode = 'P0001', message = 'AUTHORIZATION_OPERATION_UNAVAILABLE';
  end if;
  if current_membership.version <> expected_membership_version then
    raise exception using errcode = '40001', message = 'AUTHORIZATION_VERSION_CONFLICT';
  end if;

  select profile.* into target_profile
  from public.tenant_profiles as profile
  where profile.id = target_profile_id
    and profile.tenant_id = actor.actor_tenant_id
    and profile.status = 'active'
  for update;

  if target_profile.id is null then
    raise exception using errcode = 'P0001', message = 'AUTHORIZATION_OPERATION_UNAVAILABLE';
  end if;

  select prospective.permission_id into elevated_permission_id
  from private.resolve_membership_permission_ids(
    current_membership.id,
    target_profile.id
  ) as prospective(permission_id)
  where not exists (
    select 1
    from private.resolve_membership_permission_ids(
      current_membership.id,
      current_membership.profile_id
    ) as current_authority(permission_id)
    where current_authority.permission_id = prospective.permission_id
  )
    and not private.can_delegate_permission(prospective.permission_id)
  limit 1;

  if elevated_permission_id is not null then
    raise exception using errcode = '42501', message = 'AUTHORIZATION_DELEGATION_DENIED';
  end if;

  update public.tenant_memberships as membership
  set profile_id = target_profile.id,
      profile_assigned_at = statement_timestamp(),
      profile_assigned_by = actor.actor_user_id
  where membership.id = current_membership.id
  returning membership.version into resulting_version;

  perform private.assert_tenant_has_authorization_administrator(actor.actor_tenant_id);

  perform private.write_authorization_audit(
    actor.actor_tenant_id, actor.actor_user_id, correlation_id,
    'authorization.membership_profile_assigned', 'tenant_membership', current_membership.id,
    command_reason,
    pg_catalog.jsonb_build_object(
      'previous_profile_id', current_membership.profile_id,
      'profile_id', target_profile.id,
      'previous_version', current_membership.version,
      'membership_version', resulting_version
    )
  );

  return query select current_membership.id, target_profile.id, resulting_version, correlation_id;
end;
$$;

create function public.set_tenant_permission_override(
  target_membership_id uuid,
  target_permission_id uuid,
  target_effect text,
  expected_membership_version bigint,
  command_reason text,
  expected_override_version bigint default null,
  correlation_id uuid default pg_catalog.gen_random_uuid()
)
returns table (override_id uuid, override_version bigint, membership_version bigint, command_correlation_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor record;
  current_membership public.tenant_memberships%rowtype;
  current_override public.tenant_permission_overrides%rowtype;
  current_allowed boolean;
  resulting_allowed boolean;
  resulting_override_id uuid;
  resulting_override_version bigint;
  resulting_membership_version bigint;
begin
  perform private.require_authorization_reason(command_reason);
  if correlation_id is null or expected_membership_version is null or expected_membership_version < 1
     or target_effect not in ('allow', 'deny') then
    raise exception using errcode = '22023', message = 'INVALID_OVERRIDE_COMMAND';
  end if;

  select * into actor
  from private.lock_authorization_actor('users', 'manage_overrides');

  select membership.* into current_membership
  from public.tenant_memberships as membership
  where membership.id = target_membership_id
    and membership.tenant_id = actor.actor_tenant_id
    and membership.status in ('active', 'blocked')
  for update;

  if current_membership.id is null or current_membership.version <> expected_membership_version then
    if current_membership.id is null then
      raise exception using errcode = 'P0001', message = 'AUTHORIZATION_OPERATION_UNAVAILABLE';
    end if;
    raise exception using errcode = '40001', message = 'AUTHORIZATION_VERSION_CONFLICT';
  end if;

  perform 1
  from public.permission_catalog as permission
  where permission.id = target_permission_id
    and permission.status = 'active'
  for share;
  if not found then
    raise exception using errcode = 'P0001', message = 'AUTHORIZATION_OPERATION_UNAVAILABLE';
  end if;

  select individual_override.* into current_override
  from public.tenant_permission_overrides as individual_override
  where individual_override.tenant_id = actor.actor_tenant_id
    and individual_override.membership_id = current_membership.id
    and individual_override.permission_id = target_permission_id
  for update;

  if current_override.id is null then
    if expected_override_version is not null then
      raise exception using errcode = '40001', message = 'AUTHORIZATION_VERSION_CONFLICT';
    end if;
  elsif expected_override_version is null
        or current_override.version <> expected_override_version then
    raise exception using errcode = '40001', message = 'AUTHORIZATION_VERSION_CONFLICT';
  elsif current_override.effect = target_effect then
    raise exception using errcode = 'P0001', message = 'AUTHORIZATION_OPERATION_UNAVAILABLE';
  end if;

  select exists (
    select 1
    from private.resolve_membership_permission_ids(
      current_membership.id,
      current_membership.profile_id
    ) as effective_permission(permission_id)
    where effective_permission.permission_id = target_permission_id
  ) into current_allowed;

  resulting_allowed := target_effect = 'allow';
  if not current_allowed and resulting_allowed
     and not private.can_delegate_permission(target_permission_id) then
    raise exception using errcode = '42501', message = 'AUTHORIZATION_DELEGATION_DENIED';
  end if;

  if current_override.id is null then
    insert into public.tenant_permission_overrides (
      tenant_id, membership_id, permission_id, effect, created_by, updated_by
    ) values (
      actor.actor_tenant_id, current_membership.id, target_permission_id,
      target_effect, actor.actor_user_id, actor.actor_user_id
    )
    returning id, version into resulting_override_id, resulting_override_version;
  else
    update public.tenant_permission_overrides as individual_override
    set effect = target_effect,
        updated_by = actor.actor_user_id
    where individual_override.id = current_override.id
    returning individual_override.id, individual_override.version
    into resulting_override_id, resulting_override_version;
  end if;

  select membership.version into resulting_membership_version
  from public.tenant_memberships as membership
  where membership.id = current_membership.id;

  perform private.assert_tenant_has_authorization_administrator(actor.actor_tenant_id);

  perform private.write_authorization_audit(
    actor.actor_tenant_id, actor.actor_user_id, correlation_id,
    'authorization.membership_override_set', 'tenant_permission_override', resulting_override_id,
    command_reason,
    pg_catalog.jsonb_build_object(
      'membership_id', current_membership.id,
      'permission_id', target_permission_id,
      'previous_effect', current_override.effect,
      'effect', target_effect,
      'previous_membership_version', current_membership.version,
      'membership_version', resulting_membership_version,
      'override_version', resulting_override_version
    )
  );

  return query
  select resulting_override_id, resulting_override_version, resulting_membership_version, correlation_id;
end;
$$;

create function public.delete_tenant_permission_override(
  target_override_id uuid,
  expected_membership_version bigint,
  expected_override_version bigint,
  command_reason text,
  correlation_id uuid default pg_catalog.gen_random_uuid()
)
returns table (deleted_override_id uuid, membership_version bigint, command_correlation_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor record;
  current_membership public.tenant_memberships%rowtype;
  current_override public.tenant_permission_overrides%rowtype;
  baseline_allows boolean;
  resulting_membership_version bigint;
begin
  perform private.require_authorization_reason(command_reason);
  if correlation_id is null
     or expected_membership_version is null or expected_membership_version < 1
     or expected_override_version is null or expected_override_version < 1 then
    raise exception using errcode = '22023', message = 'INVALID_OVERRIDE_COMMAND';
  end if;

  select * into actor
  from private.lock_authorization_actor('users', 'manage_overrides');

  select individual_override.* into current_override
  from public.tenant_permission_overrides as individual_override
  where individual_override.id = target_override_id
    and individual_override.tenant_id = actor.actor_tenant_id;

  if current_override.id is null then
    raise exception using errcode = 'P0001', message = 'AUTHORIZATION_OPERATION_UNAVAILABLE';
  end if;

  select membership.* into current_membership
  from public.tenant_memberships as membership
  where membership.id = current_override.membership_id
    and membership.tenant_id = actor.actor_tenant_id
    and membership.status in ('active', 'blocked')
  for update;

  select individual_override.* into current_override
  from public.tenant_permission_overrides as individual_override
  where individual_override.id = target_override_id
    and individual_override.tenant_id = actor.actor_tenant_id
  for update;

  if current_membership.id is null or current_override.id is null then
    raise exception using errcode = 'P0001', message = 'AUTHORIZATION_OPERATION_UNAVAILABLE';
  end if;
  if current_membership.version <> expected_membership_version
     or current_override.version <> expected_override_version then
    raise exception using errcode = '40001', message = 'AUTHORIZATION_VERSION_CONFLICT';
  end if;

  select exists (
    select 1
    from public.tenant_profile_permissions as baseline
    join public.permission_catalog as permission
      on permission.id = baseline.permission_id
     and permission.status = 'active'
    where baseline.tenant_id = actor.actor_tenant_id
      and baseline.profile_id = current_membership.profile_id
      and baseline.permission_id = current_override.permission_id
      and (
        permission.required_entitlement_key is null
        or exists (
          select 1
          from public.tenant_entitlements as entitlement
          where entitlement.tenant_id = actor.actor_tenant_id
            and entitlement.module_key = permission.required_entitlement_key
            and entitlement.enabled
        )
      )
  ) into baseline_allows;

  if current_override.effect = 'deny'
     and baseline_allows
     and not private.can_delegate_permission(current_override.permission_id) then
    raise exception using errcode = '42501', message = 'AUTHORIZATION_DELEGATION_DENIED';
  end if;

  delete from public.tenant_permission_overrides as individual_override
  where individual_override.id = current_override.id;

  select membership.version into resulting_membership_version
  from public.tenant_memberships as membership
  where membership.id = current_membership.id;

  perform private.assert_tenant_has_authorization_administrator(actor.actor_tenant_id);

  perform private.write_authorization_audit(
    actor.actor_tenant_id, actor.actor_user_id, correlation_id,
    'authorization.membership_override_deleted', 'tenant_permission_override', current_override.id,
    command_reason,
    pg_catalog.jsonb_build_object(
      'membership_id', current_membership.id,
      'permission_id', current_override.permission_id,
      'previous_effect', current_override.effect,
      'previous_override_version', current_override.version,
      'previous_membership_version', current_membership.version,
      'membership_version', resulting_membership_version
    )
  );

  return query select current_override.id, resulting_membership_version, correlation_id;
end;
$$;

create function public.change_tenant_membership_status(
  target_membership_id uuid,
  expected_membership_version bigint,
  target_status text,
  command_reason text,
  correlation_id uuid default pg_catalog.gen_random_uuid()
)
returns table (membership_id uuid, membership_status text, membership_version bigint, command_correlation_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor record;
  current_membership public.tenant_memberships%rowtype;
  elevated_permission_id uuid;
  resulting_version bigint;
begin
  perform private.require_authorization_reason(command_reason);
  if correlation_id is null or expected_membership_version is null or expected_membership_version < 1 then
    raise exception using errcode = '22023', message = 'INVALID_COMMAND_VERSION';
  end if;
  if target_status not in ('active', 'blocked', 'revoked') then
    raise exception using errcode = '22023', message = 'INVALID_MEMBERSHIP_STATUS';
  end if;

  select * into actor
  from private.lock_authorization_actor('users', 'change_status');

  select membership.* into current_membership
  from public.tenant_memberships as membership
  where membership.id = target_membership_id
    and membership.tenant_id = actor.actor_tenant_id
    and membership.status in ('active', 'blocked')
  for update;

  if current_membership.id is null or current_membership.status = target_status
     or (current_membership.status = 'revoked') then
    raise exception using errcode = 'P0001', message = 'AUTHORIZATION_OPERATION_UNAVAILABLE';
  end if;
  if current_membership.version <> expected_membership_version then
    raise exception using errcode = '40001', message = 'AUTHORIZATION_VERSION_CONFLICT';
  end if;

  if current_membership.status = 'blocked' and target_status = 'active' then
    select prospective.permission_id into elevated_permission_id
    from private.resolve_membership_permission_ids(
      current_membership.id,
      current_membership.profile_id
    ) as prospective(permission_id)
    where not private.can_delegate_permission(prospective.permission_id)
    limit 1;

    if elevated_permission_id is not null then
      raise exception using errcode = '42501', message = 'AUTHORIZATION_DELEGATION_DENIED';
    end if;
  end if;

  update public.tenant_memberships as membership
  set status = target_status,
      blocked_at = case when target_status = 'blocked' then statement_timestamp() else null end,
      revoked_at = case when target_status = 'revoked' then statement_timestamp() else null end
  where membership.id = current_membership.id
  returning membership.version into resulting_version;

  perform private.assert_tenant_has_authorization_administrator(actor.actor_tenant_id);

  perform private.write_authorization_audit(
    actor.actor_tenant_id, actor.actor_user_id, correlation_id,
    'authorization.membership_status_changed', 'tenant_membership', current_membership.id,
    command_reason,
    pg_catalog.jsonb_build_object(
      'previous_status', current_membership.status,
      'new_status', target_status,
      'previous_version', current_membership.version,
      'membership_version', resulting_version
    )
  );

  return query select current_membership.id, target_status, resulting_version, correlation_id;
end;
$$;

create function public.invite_tenant_user(
  target_profile_id uuid,
  expected_profile_version bigint,
  recipient_email text,
  invitation_expires_at timestamptz,
  command_reason text,
  correlation_id uuid default pg_catalog.gen_random_uuid()
)
returns table (invite_ref uuid, invitation_token text, command_correlation_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor record;
  target_profile public.tenant_profiles%rowtype;
  forbidden_permission_id uuid;
  created_invite_ref uuid;
  created_invitation_token text;
begin
  perform private.require_authorization_reason(command_reason);
  if correlation_id is null or expected_profile_version is null or expected_profile_version < 1 then
    raise exception using errcode = '22023', message = 'INVALID_COMMAND_VERSION';
  end if;

  select * into actor
  from private.lock_authorization_actor('users', 'invite');

  select profile.* into target_profile
  from public.tenant_profiles as profile
  where profile.id = target_profile_id
    and profile.tenant_id = actor.actor_tenant_id
    and profile.status = 'active'
  for update;

  if target_profile.id is null then
    raise exception using errcode = 'P0001', message = 'AUTHORIZATION_OPERATION_UNAVAILABLE';
  end if;
  if target_profile.version <> expected_profile_version then
    raise exception using errcode = '40001', message = 'AUTHORIZATION_VERSION_CONFLICT';
  end if;

  select prospective.permission_id into forbidden_permission_id
  from private.resolve_profile_permission_ids(
    actor.actor_tenant_id,
    target_profile.id
  ) as prospective(permission_id)
  where not private.can_delegate_permission(prospective.permission_id)
  limit 1;

  if forbidden_permission_id is not null then
    raise exception using errcode = '42501', message = 'AUTHORIZATION_DELEGATION_DENIED';
  end if;

  select created.invite_ref, created.invitation_token
  into created_invite_ref, created_invitation_token
  from public.create_tenant_invitation(
    actor.actor_tenant_id,
    target_profile.id,
    recipient_email,
    invitation_expires_at,
    actor.actor_user_id,
    correlation_id
  ) as created;

  perform private.write_authorization_audit(
    actor.actor_tenant_id, actor.actor_user_id, correlation_id,
    'authorization.invitation_commanded', 'tenant_invitation',
    (
      select invitation.id
      from public.tenant_invitations as invitation
      where invitation.invite_ref = created_invite_ref
    ),
    command_reason,
    pg_catalog.jsonb_build_object('target_profile_id', target_profile.id)
  );

  return query select created_invite_ref, created_invitation_token, correlation_id;
end;
$$;

create function public.revoke_tenant_invitation_authenticated(
  target_invite_ref uuid,
  expected_invitation_version bigint,
  command_reason text,
  correlation_id uuid default pg_catalog.gen_random_uuid()
)
returns table (invite_ref uuid, invitation_status text, invitation_version bigint, command_correlation_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor record;
  current_invitation public.tenant_invitations%rowtype;
  resulting_version bigint;
begin
  perform private.require_authorization_reason(command_reason);
  if correlation_id is null or expected_invitation_version is null or expected_invitation_version < 1 then
    raise exception using errcode = '22023', message = 'INVALID_COMMAND_VERSION';
  end if;

  select * into actor
  from private.lock_authorization_actor('users', 'invite');

  select invitation.* into current_invitation
  from public.tenant_invitations as invitation
  where invitation.invite_ref = target_invite_ref
    and invitation.tenant_id = actor.actor_tenant_id
  for update;

  if current_invitation.id is null or current_invitation.status <> 'pending' then
    raise exception using errcode = 'P0001', message = 'AUTHORIZATION_OPERATION_UNAVAILABLE';
  end if;
  if current_invitation.version <> expected_invitation_version then
    raise exception using errcode = '40001', message = 'AUTHORIZATION_VERSION_CONFLICT';
  end if;

  perform public.revoke_tenant_invitation(
    current_invitation.invite_ref,
    actor.actor_user_id,
    correlation_id
  );

  select invitation.version into resulting_version
  from public.tenant_invitations as invitation
  where invitation.id = current_invitation.id;

  perform private.write_authorization_audit(
    actor.actor_tenant_id, actor.actor_user_id, correlation_id,
    'authorization.invitation_revoke_commanded', 'tenant_invitation', current_invitation.id,
    command_reason,
    pg_catalog.jsonb_build_object(
      'previous_version', current_invitation.version,
      'invitation_version', resulting_version
    )
  );

  return query select current_invitation.invite_ref, 'revoked'::text, resulting_version, correlation_id;
end;
$$;

create function public.expire_tenant_invitation_authenticated(
  target_invite_ref uuid,
  expected_invitation_version bigint,
  command_reason text,
  correlation_id uuid default pg_catalog.gen_random_uuid()
)
returns table (invite_ref uuid, invitation_status text, invitation_version bigint, command_correlation_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor record;
  current_invitation public.tenant_invitations%rowtype;
  resulting_version bigint;
begin
  perform private.require_authorization_reason(command_reason);
  if correlation_id is null or expected_invitation_version is null or expected_invitation_version < 1 then
    raise exception using errcode = '22023', message = 'INVALID_COMMAND_VERSION';
  end if;

  select * into actor
  from private.lock_authorization_actor('users', 'invite');

  select invitation.* into current_invitation
  from public.tenant_invitations as invitation
  where invitation.invite_ref = target_invite_ref
    and invitation.tenant_id = actor.actor_tenant_id
  for update;

  if current_invitation.id is null
     or current_invitation.status <> 'pending'
     or current_invitation.expires_at > statement_timestamp() then
    raise exception using errcode = 'P0001', message = 'AUTHORIZATION_OPERATION_UNAVAILABLE';
  end if;
  if current_invitation.version <> expected_invitation_version then
    raise exception using errcode = '40001', message = 'AUTHORIZATION_VERSION_CONFLICT';
  end if;

  perform public.expire_tenant_invitation(
    current_invitation.invite_ref,
    actor.actor_user_id,
    correlation_id
  );

  select invitation.version into resulting_version
  from public.tenant_invitations as invitation
  where invitation.id = current_invitation.id;

  perform private.write_authorization_audit(
    actor.actor_tenant_id, actor.actor_user_id, correlation_id,
    'authorization.invitation_expire_commanded', 'tenant_invitation', current_invitation.id,
    command_reason,
    pg_catalog.jsonb_build_object(
      'previous_version', current_invitation.version,
      'invitation_version', resulting_version
    )
  );

  return query select current_invitation.invite_ref, 'expired'::text, resulting_version, correlation_id;
end;
$$;

revoke all on function private.require_authorization_reason(text)
  from public, anon, authenticated, service_role;
revoke all on function private.lock_authorization_actor(text, text)
  from public, anon, authenticated, service_role;
revoke all on function private.assert_tenant_has_authorization_administrator(uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.write_authorization_audit(uuid, uuid, uuid, text, text, uuid, text, jsonb)
  from public, anon, authenticated, service_role;

revoke all on function public.create_tenant_profile(text, text, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.create_tenant_profile(text, text, uuid) to authenticated;

revoke all on function public.update_tenant_profile(uuid, bigint, text, text, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.update_tenant_profile(uuid, bigint, text, text, uuid) to authenticated;

revoke all on function public.change_tenant_profile_status(uuid, bigint, text, text, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.change_tenant_profile_status(uuid, bigint, text, text, uuid) to authenticated;

revoke all on function public.set_tenant_profile_permission(uuid, uuid, boolean, bigint, text, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.set_tenant_profile_permission(uuid, uuid, boolean, bigint, text, uuid) to authenticated;

revoke all on function public.assign_tenant_membership_profile(uuid, uuid, bigint, text, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.assign_tenant_membership_profile(uuid, uuid, bigint, text, uuid) to authenticated;

revoke all on function public.set_tenant_permission_override(uuid, uuid, text, bigint, text, bigint, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.set_tenant_permission_override(uuid, uuid, text, bigint, text, bigint, uuid) to authenticated;

revoke all on function public.delete_tenant_permission_override(uuid, bigint, bigint, text, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.delete_tenant_permission_override(uuid, bigint, bigint, text, uuid) to authenticated;

revoke all on function public.change_tenant_membership_status(uuid, bigint, text, text, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.change_tenant_membership_status(uuid, bigint, text, text, uuid) to authenticated;

revoke all on function public.invite_tenant_user(uuid, bigint, text, timestamptz, text, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.invite_tenant_user(uuid, bigint, text, timestamptz, text, uuid) to authenticated;

revoke all on function public.revoke_tenant_invitation_authenticated(uuid, bigint, text, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.revoke_tenant_invitation_authenticated(uuid, bigint, text, uuid) to authenticated;

revoke all on function public.expire_tenant_invitation_authenticated(uuid, bigint, text, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.expire_tenant_invitation_authenticated(uuid, bigint, text, uuid) to authenticated;

comment on function public.set_tenant_profile_permission(uuid, uuid, boolean, bigint, text, uuid) is
  'Authenticated W2C profile baseline command with exact same-permission tenant delegation and optimistic concurrency.';
comment on function public.assign_tenant_membership_profile(uuid, uuid, bigint, text, uuid) is
  'Authenticated W2C assignment command. Only newly effective exact permissions are subject to anti-escalation.';
comment on function public.set_tenant_permission_override(uuid, uuid, text, bigint, text, bigint, uuid) is
  'Authenticated W2C sparse override command. An exact DENY-to-ALLOW transition requires the actor to hold and be able to delegate that same permission.';
comment on function public.invite_tenant_user(uuid, bigint, text, timestamptz, text, uuid) is
  'Authenticated W2C invitation boundary. Tenant and actor derive from auth.uid(); the plaintext token is returned once and never audited.';
