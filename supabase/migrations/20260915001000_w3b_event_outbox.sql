-- CW ERP V2 / W3B: immutable Event Model and Transactional Outbox foundation.

create function private.jsonb_has_forbidden_event_keys(document jsonb)
returns boolean
language plpgsql
immutable
parallel safe
set search_path = ''
as $$
declare
  key_name text;
  child jsonb;
begin
  if document is null then
    return false;
  end if;

  if private.jsonb_has_forbidden_history_keys(document) then
    return true;
  end if;

  if pg_catalog.jsonb_typeof(document) = 'object' then
    for key_name, child in
      select entry.key, entry.value
      from pg_catalog.jsonb_each(document) as entry(key, value)
    loop
      if pg_catalog.lower(key_name) = any (array[
        'event_id', 'event_type', 'event_version', 'occurred_at',
        'scope_kind', 'tenant_id', 'actor_kind', 'actor_user_id', 'actor_ref',
        'authority_kind', 'source', 'command_id', 'correlation_id',
        'causation_id', 'handler', 'handler_name', 'capability', 'capabilities',
        'authorization_context', 'privileged_destination', 'old_row', 'new_row',
        'row_dump', 'record_dump'
      ]::text[]) then
        return true;
      end if;

      if private.jsonb_has_forbidden_event_keys(child) then
        return true;
      end if;
    end loop;
  elsif pg_catalog.jsonb_typeof(document) = 'array' then
    for child in
      select element.value
      from pg_catalog.jsonb_array_elements(document) as element(value)
    loop
      if private.jsonb_has_forbidden_event_keys(child) then
        return true;
      end if;
    end loop;
  end if;

  return false;
end;
$$;

revoke all on function private.jsonb_has_forbidden_event_keys(jsonb)
  from public, anon, authenticated, service_role;

create table private.outbox_events (
  event_id uuid primary key default pg_catalog.gen_random_uuid(),
  event_type text not null,
  event_version integer not null default 1,
  occurred_at timestamptz not null default statement_timestamp(),
  scope_kind text not null default 'tenant',
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  aggregate_type text,
  aggregate_id uuid,
  aggregate_version bigint,
  actor_kind text not null,
  actor_user_id uuid references public.app_users (id) on delete restrict,
  actor_ref text,
  source text not null,
  command_id uuid not null,
  correlation_id uuid not null,
  causation_id uuid,
  payload jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  status text not null default 'pending',
  attempt_count integer not null default 0,
  next_attempt_at timestamptz not null default statement_timestamp(),
  constraint outbox_events_event_type_check check (
    pg_catalog.char_length(event_type) between 5 and 160
    and event_type ~ '^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$'
  ),
  constraint outbox_events_event_version_check check (event_version > 0),
  constraint outbox_events_scope_check check (
    scope_kind = 'tenant' and tenant_id is not null
  ),
  constraint outbox_events_aggregate_check check (
    (
      aggregate_type is null
      and aggregate_id is null
      and aggregate_version is null
    )
    or (
      aggregate_type is not null
      and aggregate_id is not null
      and pg_catalog.char_length(aggregate_type) between 1 and 80
      and aggregate_type ~ '^[a-z][a-z0-9_]*$'
      and (aggregate_version is null or aggregate_version > 0)
    )
  ),
  constraint outbox_events_actor_kind_check check (
    actor_kind in ('application_user', 'technical', 'system')
  ),
  constraint outbox_events_actor_check check (
    (
      actor_kind = 'application_user'
      and actor_user_id is not null
      and actor_ref is null
    )
    or (
      actor_kind in ('technical', 'system')
      and actor_user_id is null
      and actor_ref is not null
    )
  ),
  constraint outbox_events_actor_ref_check check (
    actor_ref is null
    or (
      actor_ref = pg_catalog.btrim(actor_ref)
      and pg_catalog.char_length(actor_ref) between 1 and 160
      and actor_ref ~ '^[a-z][a-z0-9_.:-]*$'
    )
  ),
  constraint outbox_events_source_check check (
    source in (
      'user_command', 'system', 'worker', 'scheduler',
      'integration', 'platform', 'migration'
    )
  ),
  constraint outbox_events_payload_object_check check (
    pg_catalog.jsonb_typeof(payload) = 'object'
  ),
  constraint outbox_events_metadata_object_check check (
    pg_catalog.jsonb_typeof(metadata) = 'object'
  ),
  constraint outbox_events_envelope_size_check check (
    pg_catalog.octet_length(payload::text)
      + pg_catalog.octet_length(metadata::text) <= 65536
  ),
  constraint outbox_events_payload_keys_check check (
    not private.jsonb_has_forbidden_event_keys(payload)
  ),
  constraint outbox_events_metadata_keys_check check (
    not private.jsonb_has_forbidden_event_keys(metadata)
  ),
  constraint outbox_events_status_check check (
    status in ('pending', 'processing', 'processed', 'dead_letter')
  ),
  constraint outbox_events_attempt_count_check check (attempt_count >= 0)
);

create index outbox_events_pending_claim_idx
on private.outbox_events (next_attempt_at, occurred_at, event_id)
where status = 'pending';

create index outbox_events_operability_idx
on private.outbox_events (status, event_type, occurred_at);

create function private.protect_outbox_event()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    if (
      pg_catalog.to_jsonb(new)
        - 'status' - 'attempt_count' - 'next_attempt_at'
    ) is distinct from (
      pg_catalog.to_jsonb(old)
        - 'status' - 'attempt_count' - 'next_attempt_at'
    ) then
      raise exception using
        errcode = '55000',
        message = 'outbox event fact is immutable';
    end if;

    return new;
  end if;

  raise exception using
    errcode = '55000',
    message = 'outbox event cannot be deleted';
end;
$$;

revoke all on function private.protect_outbox_event()
  from public, anon, authenticated, service_role;

create trigger outbox_events_protect_update_delete
before update or delete on private.outbox_events
for each row
execute function private.protect_outbox_event();

create trigger outbox_events_reject_truncate
before truncate on private.outbox_events
for each statement
execute function private.protect_outbox_event();

create function private.enqueue_event(
  target_tenant_id uuid,
  target_event_type text,
  event_actor_kind text,
  event_source text,
  event_command_id uuid,
  event_correlation_id uuid,
  target_aggregate_type text default null,
  target_aggregate_id uuid default null,
  target_event_version integer default 1,
  target_aggregate_version bigint default null,
  event_actor_user_id uuid default null,
  event_actor_ref text default null,
  event_causation_id uuid default null,
  event_payload jsonb default '{}'::jsonb,
  event_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  created_event_id uuid;
begin
  if target_tenant_id is null then
    raise exception using errcode = '22023', message = 'EVENT_TENANT_REQUIRED';
  end if;

  if event_actor_kind = 'application_user' then
    if event_actor_user_id is null or event_actor_ref is not null then
      raise exception using errcode = '22023', message = 'INVALID_EVENT_ACTOR';
    end if;

    if not exists (
      select 1
      from public.tenant_memberships as membership
      where membership.tenant_id = target_tenant_id
        and membership.user_id = event_actor_user_id
    ) then
      raise exception using errcode = 'P0001', message = 'EVENT_TARGET_UNAVAILABLE';
    end if;
  elsif event_actor_kind in ('technical', 'system') then
    if event_actor_user_id is not null or event_actor_ref is null then
      raise exception using errcode = '22023', message = 'INVALID_EVENT_ACTOR';
    end if;
  else
    raise exception using errcode = '22023', message = 'INVALID_EVENT_ACTOR';
  end if;

  insert into private.outbox_events (
    event_type,
    event_version,
    scope_kind,
    tenant_id,
    aggregate_type,
    aggregate_id,
    aggregate_version,
    actor_kind,
    actor_user_id,
    actor_ref,
    source,
    command_id,
    correlation_id,
    causation_id,
    payload,
    metadata
  ) values (
    target_event_type,
    target_event_version,
    'tenant',
    target_tenant_id,
    target_aggregate_type,
    target_aggregate_id,
    target_aggregate_version,
    event_actor_kind,
    event_actor_user_id,
    event_actor_ref,
    event_source,
    event_command_id,
    event_correlation_id,
    event_causation_id,
    coalesce(event_payload, '{}'::jsonb),
    coalesce(event_metadata, '{}'::jsonb)
  )
  returning event_id into created_event_id;

  return created_event_id;
end;
$$;

revoke all on function private.enqueue_event(
  uuid, text, text, text, uuid, uuid, text, uuid, integer, bigint,
  uuid, text, uuid, jsonb, jsonb
) from public, anon, authenticated, service_role;

-- W3B integrates one real W2 command. Its effect matrix is:
-- Audit required; History N/A; Event authorization.profile.created required.
create or replace function public.create_tenant_profile(
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
  event_command_id uuid := pg_catalog.gen_random_uuid();
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

  perform private.append_audit(
    actor.actor_tenant_id,
    'application_user',
    'authorization.profile_created',
    'tenant_profile',
    correlation_id,
    'user_command',
    actor.actor_user_id,
    null,
    created_profile_id,
    event_command_id,
    null,
    1,
    command_reason,
    pg_catalog.jsonb_build_object('profile_version', created_profile_version)
  );

  perform private.enqueue_event(
    actor.actor_tenant_id,
    'authorization.profile.created',
    'application_user',
    'user_command',
    event_command_id,
    correlation_id,
    'tenant_profile',
    created_profile_id,
    1,
    created_profile_version,
    actor.actor_user_id,
    null,
    null,
    pg_catalog.jsonb_build_object('profile_version', created_profile_version),
    '{}'::jsonb
  );

  return query select created_profile_id, created_profile_version, correlation_id;
exception
  when unique_violation then
    raise exception using errcode = 'P0001', message = 'AUTHORIZATION_OPERATION_UNAVAILABLE';
end;
$$;

alter table private.outbox_events enable row level security;

revoke all privileges on table private.outbox_events from public;
revoke all privileges on table private.outbox_events from anon;
revoke all privileges on table private.outbox_events from authenticated;
revoke all privileges on table private.outbox_events from service_role;

revoke all on function public.create_tenant_profile(text, text, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.create_tenant_profile(text, text, uuid)
  to authenticated;

alter table private.outbox_events owner to postgres;
alter function private.jsonb_has_forbidden_event_keys(jsonb) owner to postgres;
alter function private.protect_outbox_event() owner to postgres;
alter function private.enqueue_event(
  uuid, text, text, text, uuid, uuid, text, uuid, integer, bigint,
  uuid, text, uuid, jsonb, jsonb
) owner to postgres;
alter function public.create_tenant_profile(text, text, uuid) owner to postgres;

comment on table private.outbox_events is
  'W3B persisted Event Model and Transactional Outbox. Event facts are immutable; processing runtime is deferred.';
comment on function private.enqueue_event(
  uuid, text, text, text, uuid, uuid, text, uuid, integer, bigint,
  uuid, text, uuid, jsonb, jsonb
) is 'Private W3B tenant Event writer for trusted transactional commands.';
