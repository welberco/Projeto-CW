-- CW ERP V2 / W1B: one-shot bootstrap and controlled invitation commands.

create table private.platform_bootstrap_state (
  singleton boolean primary key default true,
  completed_at timestamptz not null default statement_timestamp(),
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  bootstrap_user_id uuid not null references public.app_users (id) on delete restrict,
  correlation_id uuid not null,
  constraint platform_bootstrap_state_singleton_check check (singleton)
);

revoke all privileges on table private.platform_bootstrap_state from public;
revoke all privileges on table private.platform_bootstrap_state from anon;
revoke all privileges on table private.platform_bootstrap_state from authenticated;

alter table public.tenant_invitations
add column token_hash text;

alter table public.tenant_invitations
add constraint tenant_invitations_token_hash_check check (
  token_hash is null or token_hash ~ '^[0-9a-f]{64}$'
);

create unique index tenant_invitations_token_hash_uidx
on public.tenant_invitations (token_hash)
where token_hash is not null;

comment on column public.tenant_invitations.token_hash is
  'SHA-256 of a 256-bit invitation token. Raw tokens are returned once and never persisted.';

create function private.normalize_invitation_email(candidate text)
returns text
language sql
immutable
strict
set search_path = ''
as $$
  select pg_catalog.lower(pg_catalog.btrim(candidate));
$$;

create function private.sha256_hex(candidate text)
returns text
language sql
immutable
strict
set search_path = ''
as $$
  select pg_catalog.encode(
    extensions.digest(pg_catalog.convert_to(candidate, 'UTF8'), 'sha256'),
    'hex'
  );
$$;

revoke all on function private.normalize_invitation_email(text) from public;
revoke all on function private.normalize_invitation_email(text) from anon;
revoke all on function private.normalize_invitation_email(text) from authenticated;
revoke all on function private.sha256_hex(text) from public;
revoke all on function private.sha256_hex(text) from anon;
revoke all on function private.sha256_hex(text) from authenticated;

create function public.bootstrap_initial_tenant(
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

  insert into public.tenant_memberships (
    tenant_id,
    user_id,
    status,
    joined_at,
    created_by
  ) values (
    created_tenant_id,
    bootstrap_user_id,
    'active',
    statement_timestamp(),
    bootstrap_user_id
  );

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
    pg_catalog.jsonb_build_object('module_key', 'maintenance')
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

create function public.create_tenant_invitation(
  target_tenant_id uuid,
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
    recipient_email_hash,
    token_hash,
    invited_user_id,
    expires_at,
    created_by
  ) values (
    target_tenant_id,
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
    pg_catalog.jsonb_build_object('expires_at', invitation_expires_at)
  );

  return query select created_invite_ref, raw_token;
end;
$$;

create function public.revoke_tenant_invitation(
  target_invite_ref uuid,
  operator_user_id uuid,
  correlation_id uuid default pg_catalog.gen_random_uuid()
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  invitation_record public.tenant_invitations%rowtype;
  invitation_tenant_id uuid;
begin
  select invitation.tenant_id
  into invitation_tenant_id
  from public.tenant_invitations as invitation
  where invitation.invite_ref = target_invite_ref;

  if invitation_tenant_id is null then
    raise exception using errcode = 'P0001', message = 'INVITATION_OPERATION_UNAVAILABLE';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(invitation_tenant_id::text, 0)
  );

  perform 1
  from public.app_users as operator_user
  join public.tenant_memberships as membership
    on membership.user_id = operator_user.id
   and membership.tenant_id = invitation_tenant_id
   and membership.status = 'active'
  where operator_user.id = operator_user_id
    and operator_user.status = 'active'
  for update of operator_user, membership;

  if not found then
    raise exception using errcode = 'P0001', message = 'INVITATION_OPERATION_UNAVAILABLE';
  end if;

  select invitation.*
  into invitation_record
  from public.tenant_invitations as invitation
  where invitation.invite_ref = target_invite_ref
  for update;

  if invitation_record.id is null or invitation_record.status <> 'pending' then
    raise exception using errcode = 'P0001', message = 'INVITATION_OPERATION_UNAVAILABLE';
  end if;

  update public.tenant_invitations
  set status = 'revoked', revoked_at = statement_timestamp()
  where id = invitation_record.id;

  insert into public.audit_events (
    tenant_id, actor_user_id, actor_kind, correlation_id,
    event_type, entity_type, entity_id
  ) values (
    invitation_record.tenant_id, operator_user_id, 'application_user', correlation_id,
    'invitation.revoked', 'tenant_invitation', invitation_record.id
  );
end;
$$;

create function public.expire_tenant_invitation(
  target_invite_ref uuid,
  operator_user_id uuid,
  correlation_id uuid default pg_catalog.gen_random_uuid()
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  invitation_record public.tenant_invitations%rowtype;
  invitation_tenant_id uuid;
begin
  select invitation.tenant_id
  into invitation_tenant_id
  from public.tenant_invitations as invitation
  where invitation.invite_ref = target_invite_ref;

  if invitation_tenant_id is null then
    raise exception using errcode = 'P0001', message = 'INVITATION_OPERATION_UNAVAILABLE';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(invitation_tenant_id::text, 0)
  );

  perform 1
  from public.app_users as operator_user
  join public.tenant_memberships as membership
    on membership.user_id = operator_user.id
   and membership.tenant_id = invitation_tenant_id
   and membership.status = 'active'
  where operator_user.id = operator_user_id
    and operator_user.status = 'active'
  for update of operator_user, membership;

  if not found then
    raise exception using errcode = 'P0001', message = 'INVITATION_OPERATION_UNAVAILABLE';
  end if;

  select invitation.*
  into invitation_record
  from public.tenant_invitations as invitation
  where invitation.invite_ref = target_invite_ref
  for update;

  if invitation_record.id is null
     or invitation_record.status <> 'pending'
     or invitation_record.expires_at > statement_timestamp() then
    raise exception using errcode = 'P0001', message = 'INVITATION_OPERATION_UNAVAILABLE';
  end if;

  update public.tenant_invitations
  set status = 'expired'
  where id = invitation_record.id;

  insert into public.audit_events (
    tenant_id, actor_user_id, actor_kind, correlation_id,
    event_type, entity_type, entity_id
  ) values (
    invitation_record.tenant_id, operator_user_id, 'application_user', correlation_id,
    'invitation.expired', 'tenant_invitation', invitation_record.id
  );
end;
$$;

create function public.accept_tenant_invitation(
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
     or (
       invitation_record.invited_user_id is not null
       and invitation_record.invited_user_id <> principal_id
     ) then
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
    tenant_id, user_id, status, joined_at, created_by
  ) values (
    invitation_record.tenant_id,
    principal_id,
    'active',
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
    event_type, entity_type, entity_id
  ) values (
    invitation_record.tenant_id, principal_id, 'application_user', correlation_id,
    'invitation.accepted', 'tenant_invitation', invitation_record.id
  );

  return query select accepted_tenant_ref, created_membership_id;
end;
$$;

revoke all on function public.bootstrap_initial_tenant(uuid, text, uuid) from public;
revoke all on function public.bootstrap_initial_tenant(uuid, text, uuid) from anon;
revoke all on function public.bootstrap_initial_tenant(uuid, text, uuid) from authenticated;
grant execute on function public.bootstrap_initial_tenant(uuid, text, uuid) to service_role;

revoke all on function public.create_tenant_invitation(uuid, text, timestamptz, uuid, uuid) from public;
revoke all on function public.create_tenant_invitation(uuid, text, timestamptz, uuid, uuid) from anon;
revoke all on function public.create_tenant_invitation(uuid, text, timestamptz, uuid, uuid) from authenticated;
grant execute on function public.create_tenant_invitation(uuid, text, timestamptz, uuid, uuid) to service_role;

revoke all on function public.revoke_tenant_invitation(uuid, uuid, uuid) from public;
revoke all on function public.revoke_tenant_invitation(uuid, uuid, uuid) from anon;
revoke all on function public.revoke_tenant_invitation(uuid, uuid, uuid) from authenticated;
grant execute on function public.revoke_tenant_invitation(uuid, uuid, uuid) to service_role;

revoke all on function public.expire_tenant_invitation(uuid, uuid, uuid) from public;
revoke all on function public.expire_tenant_invitation(uuid, uuid, uuid) from anon;
revoke all on function public.expire_tenant_invitation(uuid, uuid, uuid) from authenticated;
grant execute on function public.expire_tenant_invitation(uuid, uuid, uuid) to service_role;

revoke all on function public.accept_tenant_invitation(text, uuid) from public;
revoke all on function public.accept_tenant_invitation(text, uuid) from anon;
revoke all on function public.accept_tenant_invitation(text, uuid) from service_role;
grant execute on function public.accept_tenant_invitation(text, uuid) to authenticated;

comment on function public.bootstrap_initial_tenant(uuid, text, uuid) is
  'One-shot ops command. Not callable by anon or authenticated clients.';
comment on function public.create_tenant_invitation(uuid, text, timestamptz, uuid, uuid) is
  'Controlled ops command. Returns the raw token once and persists only its SHA-256 hash.';
comment on function public.accept_tenant_invitation(text, uuid) is
  'Authenticated onboarding command. Tenant and user are derived from invitation and auth.uid().';
