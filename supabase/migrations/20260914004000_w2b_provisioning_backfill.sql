-- W2B / W2-05: idempotent tenant authorization provisioning and safe backfill.

create function private.provision_tenant_authorization(
  target_tenant_id uuid,
  bootstrap_membership_id uuid default null,
  actor_user_id uuid default null,
  correlation_id uuid default pg_catalog.gen_random_uuid()
)
returns table (
  manager_profile_id uuid,
  profiles_created integer,
  grants_created integer,
  bootstrap_membership_assigned boolean
)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  template_record record;
  inserted_profile_id uuid;
  resolved_manager_profile_id uuid;
  inserted_grants integer := 0;
  total_profiles_created integer := 0;
  total_grants_created integer := 0;
  membership_was_assigned boolean := false;
begin
  if target_tenant_id is null then
    raise exception using errcode = '22023', message = 'TENANT_REQUIRED';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(target_tenant_id::text, 2205)
  );

  perform 1
  from public.tenants as tenant
  where tenant.id = target_tenant_id
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'TENANT_NOT_FOUND';
  end if;

  if actor_user_id is not null
     and not exists (
       select 1
       from public.app_users as actor
       where actor.id = actor_user_id
     ) then
    raise exception using errcode = 'P0001', message = 'ACTOR_NOT_FOUND';
  end if;

  for template_record in
    select
      template.id,
      template.template_key,
      template.default_name,
      template.template_version
    from private.authorization_profile_templates as template
    where template.status = 'active'
    order by template.template_key
  loop
    inserted_profile_id := null;

    insert into public.tenant_profiles (
      tenant_id,
      name,
      template_key,
      template_version,
      status,
      created_by,
      updated_by
    ) values (
      target_tenant_id,
      template_record.default_name,
      template_record.template_key,
      template_record.template_version,
      'active',
      actor_user_id,
      actor_user_id
    )
    on conflict (tenant_id, template_key) where template_key is not null
    do nothing
    returning id into inserted_profile_id;

    if inserted_profile_id is not null then
      total_profiles_created := total_profiles_created + 1;

      insert into public.tenant_profile_permissions (
        tenant_id,
        profile_id,
        permission_id,
        created_by
      )
      select
        target_tenant_id,
        inserted_profile_id,
        template_permission.permission_id,
        actor_user_id
      from private.authorization_profile_template_permissions as template_permission
      join public.permission_catalog as permission
        on permission.id = template_permission.permission_id
       and permission.status = 'active'
      where template_permission.template_id = template_record.id
      order by template_permission.permission_id;

      get diagnostics inserted_grants = row_count;
      total_grants_created := total_grants_created + inserted_grants;
    end if;
  end loop;

  select profile.id
  into resolved_manager_profile_id
  from public.tenant_profiles as profile
  where profile.tenant_id = target_tenant_id
    and profile.template_key = 'manager'
    and profile.status = 'active';

  if resolved_manager_profile_id is null then
    raise exception using errcode = 'P0001', message = 'MANAGER_PROFILE_UNAVAILABLE';
  end if;

  if bootstrap_membership_id is not null then
    update public.tenant_memberships as membership
    set profile_id = resolved_manager_profile_id,
        profile_assigned_at = statement_timestamp(),
        profile_assigned_by = actor_user_id
    where membership.id = bootstrap_membership_id
      and membership.tenant_id = target_tenant_id
      and membership.status in ('active', 'blocked')
      and membership.profile_id is null;

    membership_was_assigned := found;

    if not membership_was_assigned
       and not exists (
         select 1
         from public.tenant_memberships as membership
         where membership.id = bootstrap_membership_id
           and membership.tenant_id = target_tenant_id
           and membership.profile_id is not null
       ) then
      raise exception using errcode = 'P0001', message = 'BOOTSTRAP_MEMBERSHIP_UNAVAILABLE';
    end if;
  end if;

  if total_profiles_created > 0 or membership_was_assigned then
    insert into public.audit_events (
      tenant_id,
      actor_user_id,
      actor_kind,
      correlation_id,
      event_type,
      entity_type,
      entity_id,
      metadata
    ) values (
      target_tenant_id,
      actor_user_id,
      case when actor_user_id is null then 'technical' else 'application_user' end,
      correlation_id,
      'authorization.tenant_provisioned',
      'tenant',
      target_tenant_id,
      pg_catalog.jsonb_build_object(
        'profiles_created', total_profiles_created,
        'grants_created', total_grants_created,
        'bootstrap_membership_assigned', membership_was_assigned
      )
    );
  end if;

  return query
  select
    resolved_manager_profile_id,
    total_profiles_created,
    total_grants_created,
    membership_was_assigned;
end;
$$;

revoke all on function private.provision_tenant_authorization(uuid, uuid, uuid, uuid)
  from public, anon, authenticated, service_role;

create or replace function public.bootstrap_initial_tenant(
  bootstrap_user_id uuid,
  tenant_display_name text,
  correlation_id uuid default pg_catalog.gen_random_uuid()
)
returns table (tenant_id uuid, tenant_ref uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  created_tenant_id uuid;
  created_tenant_ref uuid;
  created_membership_id uuid;
  manager_profile_id uuid;
begin
  perform pg_catalog.pg_advisory_xact_lock(1129790797, 1);

  if exists (select 1 from private.platform_bootstrap_state) then
    raise exception using errcode = 'P0001', message = 'SYSTEM_ALREADY_INITIALIZED';
  end if;

  if exists (select 1 from public.tenants)
     or exists (select 1 from public.tenant_memberships) then
    raise exception using errcode = 'P0001', message = 'SYSTEM_STATE_NOT_EMPTY';
  end if;

  if tenant_display_name is null
     or pg_catalog.char_length(pg_catalog.btrim(tenant_display_name)) not between 1 and 200
     or tenant_display_name <> pg_catalog.btrim(tenant_display_name) then
    raise exception using errcode = '22023', message = 'INVALID_TENANT_DISPLAY_NAME';
  end if;

  perform 1
  from auth.users as auth_user
  join public.app_users as app_user on app_user.id = auth_user.id
  where auth_user.id = bootstrap_user_id
    and app_user.status = 'active'
  for update of app_user;

  if not found then
    raise exception using errcode = 'P0001', message = 'BOOTSTRAP_IDENTITY_UNAVAILABLE';
  end if;

  insert into public.tenants (
    display_name,
    status,
    suspended_at,
    created_by
  ) values (
    tenant_display_name,
    'suspended',
    statement_timestamp(),
    bootstrap_user_id
  )
  returning id, tenants.tenant_ref into created_tenant_id, created_tenant_ref;

  select provisioned.manager_profile_id
  into manager_profile_id
  from private.provision_tenant_authorization(
    created_tenant_id,
    null,
    bootstrap_user_id,
    correlation_id
  ) as provisioned;

  insert into public.tenant_memberships (
    tenant_id,
    user_id,
    status,
    joined_at,
    created_by,
    profile_id,
    profile_assigned_at,
    profile_assigned_by
  ) values (
    created_tenant_id,
    bootstrap_user_id,
    'active',
    statement_timestamp(),
    bootstrap_user_id,
    manager_profile_id,
    statement_timestamp(),
    bootstrap_user_id
  )
  returning id into created_membership_id;

  insert into public.tenant_entitlements (
    tenant_id,
    module_key,
    enabled,
    created_by
  ) values (
    created_tenant_id,
    'maintenance',
    true,
    bootstrap_user_id
  );

  update public.tenants
  set status = 'active', suspended_at = null
  where id = created_tenant_id;

  insert into public.audit_events (
    tenant_id,
    actor_kind,
    correlation_id,
    event_type,
    entity_type,
    entity_id,
    metadata
  ) values (
    created_tenant_id,
    'technical',
    correlation_id,
    'platform.bootstrap_completed',
    'tenant',
    created_tenant_id,
    pg_catalog.jsonb_build_object(
      'module_key', 'maintenance',
      'membership_id', created_membership_id,
      'manager_profile_id', manager_profile_id
    )
  );

  insert into private.platform_bootstrap_state (
    tenant_id,
    bootstrap_user_id,
    correlation_id
  ) values (
    created_tenant_id,
    bootstrap_user_id,
    correlation_id
  );

  return query select created_tenant_id, created_tenant_ref;
end;
$$;

drop function public.create_tenant_invitation(uuid, text, timestamptz, uuid, uuid);

create function public.create_tenant_invitation(
  target_tenant_id uuid,
  target_profile_id uuid,
  recipient_email text,
  invitation_expires_at timestamptz,
  operator_user_id uuid,
  correlation_id uuid default pg_catalog.gen_random_uuid()
)
returns table (invite_ref uuid, invitation_token text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_email text;
  email_hash text;
  raw_token text;
  raw_token_hash text;
  target_user_id uuid;
  prior_invitation_id uuid;
  created_invitation_id uuid;
  created_invite_ref uuid;
begin
  normalized_email := private.normalize_invitation_email(recipient_email);

  if pg_catalog.char_length(normalized_email) not between 3 and 320
     or pg_catalog.strpos(normalized_email, '@') <= 1 then
    raise exception using errcode = '22023', message = 'INVALID_INVITATION_RECIPIENT';
  end if;

  if invitation_expires_at is null
     or invitation_expires_at <= statement_timestamp() then
    raise exception using errcode = '22023', message = 'INVALID_INVITATION_EXPIRY';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(target_tenant_id::text, 0)
  );

  perform 1
  from public.app_users as operator_user
  join public.tenant_memberships as membership
    on membership.user_id = operator_user.id
   and membership.tenant_id = target_tenant_id
   and membership.status = 'active'
  join public.tenants as tenant
    on tenant.id = membership.tenant_id
   and tenant.status = 'active'
  where operator_user.id = operator_user_id
    and operator_user.status = 'active'
  for update of operator_user, membership, tenant;

  if not found then
    raise exception using errcode = 'P0001', message = 'INVITATION_OPERATION_UNAVAILABLE';
  end if;

  perform 1
  from public.tenant_profiles as profile
  where profile.id = target_profile_id
    and profile.tenant_id = target_tenant_id
    and profile.status = 'active'
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'INVITATION_PROFILE_UNAVAILABLE';
  end if;

  email_hash := private.sha256_hex(normalized_email);

  select app_user.id
  into target_user_id
  from auth.users as auth_user
  join public.app_users as app_user on app_user.id = auth_user.id
  where private.normalize_invitation_email(auth_user.email) = normalized_email
  order by auth_user.created_at, auth_user.id
  limit 1;

  if target_user_id is not null and exists (
    select 1
    from public.tenant_memberships as operational_membership
    where operational_membership.user_id = target_user_id
      and operational_membership.status in ('active', 'blocked')
  ) then
    raise exception using errcode = 'P0001', message = 'INVITATION_OPERATION_UNAVAILABLE';
  end if;

  select invitation.id
  into prior_invitation_id
  from public.tenant_invitations as invitation
  where invitation.tenant_id = target_tenant_id
    and invitation.recipient_email_hash = email_hash
    and invitation.status = 'pending'
  for update;

  if prior_invitation_id is not null then
    update public.tenant_invitations
    set status = 'revoked', revoked_at = statement_timestamp()
    where id = prior_invitation_id;

    insert into public.audit_events (
      tenant_id, actor_user_id, actor_kind, correlation_id,
      event_type, entity_type, entity_id, metadata
    ) values (
      target_tenant_id, operator_user_id, 'application_user', correlation_id,
      'invitation.revoked', 'tenant_invitation', prior_invitation_id,
      pg_catalog.jsonb_build_object('reason', 'replaced')
    );
  end if;

  raw_token := pg_catalog.encode(extensions.gen_random_bytes(32), 'hex');
  raw_token_hash := private.sha256_hex(raw_token);

  insert into public.tenant_invitations (
    tenant_id,
    target_profile_id,
    recipient_email_hash,
    token_hash,
    invited_user_id,
    expires_at,
    created_by
  ) values (
    target_tenant_id,
    target_profile_id,
    email_hash,
    raw_token_hash,
    target_user_id,
    invitation_expires_at,
    operator_user_id
  )
  returning id, tenant_invitations.invite_ref
  into created_invitation_id, created_invite_ref;

  insert into public.audit_events (
    tenant_id, actor_user_id, actor_kind, correlation_id,
    event_type, entity_type, entity_id, metadata
  ) values (
    target_tenant_id, operator_user_id, 'application_user', correlation_id,
    'invitation.created', 'tenant_invitation', created_invitation_id,
    pg_catalog.jsonb_build_object(
      'expires_at', invitation_expires_at,
      'target_profile_id', target_profile_id
    )
  );

  return query select created_invite_ref, raw_token;
end;
$$;

create or replace function public.accept_tenant_invitation(
  invitation_token text,
  correlation_id uuid default pg_catalog.gen_random_uuid()
)
returns table (tenant_ref uuid, membership_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  principal_id uuid;
  principal_email text;
  principal_email_hash text;
  supplied_token_hash text;
  invitation_tenant_id uuid;
  invitation_record public.tenant_invitations%rowtype;
  created_membership_id uuid;
  accepted_tenant_ref uuid;
begin
  principal_id := auth.uid();

  if principal_id is null then
    raise exception using errcode = '28000', message = 'AUTHENTICATION_REQUIRED';
  end if;

  if invitation_token is null
     or invitation_token !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = 'P0001', message = 'INVITATION_UNAVAILABLE';
  end if;

  supplied_token_hash := private.sha256_hex(invitation_token);

  select invitation.tenant_id
  into invitation_tenant_id
  from public.tenant_invitations as invitation
  where invitation.token_hash = supplied_token_hash;

  if invitation_tenant_id is null then
    raise exception using errcode = 'P0001', message = 'INVITATION_UNAVAILABLE';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(invitation_tenant_id::text, 0)
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(principal_id::text, 0)
  );

  select auth_user.email
  into principal_email
  from auth.users as auth_user
  join public.app_users as app_user on app_user.id = auth_user.id
  where auth_user.id = principal_id
    and auth_user.email_confirmed_at is not null
    and app_user.status = 'active'
  for update of app_user;

  if principal_email is null then
    raise exception using errcode = 'P0001', message = 'INVITATION_UNAVAILABLE';
  end if;

  principal_email_hash := private.sha256_hex(
    private.normalize_invitation_email(principal_email)
  );

  select invitation.*
  into invitation_record
  from public.tenant_invitations as invitation
  where invitation.token_hash = supplied_token_hash
  for update;

  if invitation_record.id is null
     or invitation_record.status <> 'pending'
     or invitation_record.expires_at <= statement_timestamp()
     or invitation_record.recipient_email_hash <> principal_email_hash
     or invitation_record.target_profile_id is null
     or (
       invitation_record.invited_user_id is not null
       and invitation_record.invited_user_id <> principal_id
     ) then
    raise exception using errcode = 'P0001', message = 'INVITATION_UNAVAILABLE';
  end if;

  perform 1
  from public.tenant_profiles as profile
  where profile.id = invitation_record.target_profile_id
    and profile.tenant_id = invitation_record.tenant_id
    and profile.status = 'active'
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'INVITATION_UNAVAILABLE';
  end if;

  select tenant.tenant_ref
  into accepted_tenant_ref
  from public.tenants as tenant
  where tenant.id = invitation_record.tenant_id
    and tenant.status = 'active'
  for update;

  if accepted_tenant_ref is null or exists (
    select 1
    from public.tenant_memberships as operational_membership
    where operational_membership.user_id = principal_id
      and operational_membership.status in ('active', 'blocked')
    for update
  ) then
    raise exception using errcode = 'P0001', message = 'INVITATION_UNAVAILABLE';
  end if;

  insert into public.tenant_memberships (
    tenant_id,
    user_id,
    status,
    joined_at,
    created_by,
    profile_id,
    profile_assigned_at,
    profile_assigned_by
  ) values (
    invitation_record.tenant_id,
    principal_id,
    'active',
    statement_timestamp(),
    invitation_record.created_by,
    invitation_record.target_profile_id,
    statement_timestamp(),
    invitation_record.created_by
  )
  returning id into created_membership_id;

  update public.tenant_invitations
  set status = 'accepted',
      accepted_at = statement_timestamp(),
      invited_user_id = principal_id
  where id = invitation_record.id
    and status = 'pending';

  if not found then
    raise exception using errcode = 'P0001', message = 'INVITATION_UNAVAILABLE';
  end if;

  insert into public.audit_events (
    tenant_id, actor_user_id, actor_kind, correlation_id,
    event_type, entity_type, entity_id,
    metadata
  ) values (
    invitation_record.tenant_id, principal_id, 'application_user', correlation_id,
    'invitation.accepted', 'tenant_invitation', invitation_record.id,
    pg_catalog.jsonb_build_object('target_profile_id', invitation_record.target_profile_id)
  );

  return query select accepted_tenant_ref, created_membership_id;
end;
$$;

do $$
declare
  tenant_record record;
  bootstrap_membership_id uuid;
begin
  for tenant_record in
    select tenant.id
    from public.tenants as tenant
    order by tenant.created_at, tenant.id
  loop
    bootstrap_membership_id := null;

    select membership.id
    into bootstrap_membership_id
    from private.platform_bootstrap_state as bootstrap
    join public.tenant_memberships as membership
      on membership.tenant_id = bootstrap.tenant_id
     and membership.user_id = bootstrap.bootstrap_user_id
     and membership.status in ('active', 'blocked')
    where bootstrap.tenant_id = tenant_record.id;

    perform *
    from private.provision_tenant_authorization(
      tenant_record.id,
      bootstrap_membership_id,
      null,
      pg_catalog.gen_random_uuid()
    );
  end loop;

  if exists (
    select 1
    from public.tenant_memberships as membership
    where membership.status in ('active', 'blocked')
      and membership.profile_id is null
  ) then
    raise exception using
      errcode = '23514',
      message = 'W2B_BACKFILL_REQUIRES_EXPLICIT_PROFILE_ASSIGNMENT';
  end if;
end;
$$;

revoke all on function public.bootstrap_initial_tenant(uuid, text, uuid)
  from public, anon, authenticated;
grant execute on function public.bootstrap_initial_tenant(uuid, text, uuid) to service_role;

revoke all on function public.create_tenant_invitation(uuid, uuid, text, timestamptz, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.create_tenant_invitation(uuid, uuid, text, timestamptz, uuid, uuid)
  to service_role;

revoke all on function public.accept_tenant_invitation(text, uuid)
  from public, anon, service_role;
grant execute on function public.accept_tenant_invitation(text, uuid) to authenticated;

comment on function private.provision_tenant_authorization(uuid, uuid, uuid, uuid) is
  'Private idempotent copy-once provisioning command for W2B tenant profiles and initial baseline.';
comment on function public.bootstrap_initial_tenant(uuid, text, uuid) is
  'One-shot ops command. Creates the four tenant profiles before activating the first tenant and assigns Gestor to the bootstrap membership.';
comment on function public.create_tenant_invitation(uuid, uuid, text, timestamptz, uuid, uuid) is
  'Controlled ops command. Requires an explicit active same-tenant target profile and persists only the invitation token hash.';
comment on function public.accept_tenant_invitation(text, uuid) is
  'Authenticated onboarding command. Copies the invitation target profile without name, email, tenant or client-state inference.';
