-- CW ERP V2 / W3C: command idempotency and handler receipt contracts.

create function private.semantic_fingerprint(document jsonb)
returns bytea
language sql
immutable
parallel safe
set search_path = ''
as $$
  select extensions.digest(
    pg_catalog.convert_to(coalesce(document, 'null'::jsonb)::text, 'UTF8'),
    'sha256'
  );
$$;

revoke all on function private.semantic_fingerprint(jsonb)
  from public, anon, authenticated, service_role;

create table private.command_idempotency (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  actor_kind text not null,
  actor_user_id uuid references public.app_users (id) on delete restrict,
  actor_ref text,
  actor_scope text not null,
  source text not null,
  command_name text not null,
  idempotency_key_hash bytea not null,
  command_id uuid not null unique,
  request_fingerprint bytea not null,
  status text not null default 'in_progress',
  result_version integer,
  result jsonb,
  created_at timestamptz not null default statement_timestamp(),
  completed_at timestamptz,
  expires_at timestamptz,
  constraint command_idempotency_namespace_uq unique (
    tenant_id, actor_scope, source, command_name, idempotency_key_hash
  ),
  constraint command_idempotency_actor_kind_check check (
    actor_kind in ('application_user', 'technical', 'system')
  ),
  constraint command_idempotency_actor_check check (
    (
      actor_kind = 'application_user'
      and actor_user_id is not null
      and actor_ref is null
      and actor_scope = 'application_user:' || actor_user_id::text
      and source = 'user_command'
    )
    or (
      actor_kind in ('technical', 'system')
      and actor_user_id is null
      and actor_ref is not null
      and actor_scope = actor_kind || ':' || actor_ref
      and source in ('system', 'worker', 'scheduler', 'integration', 'migration')
    )
  ),
  constraint command_idempotency_actor_ref_check check (
    actor_ref is null
    or (
      actor_ref = pg_catalog.btrim(actor_ref)
      and pg_catalog.char_length(actor_ref) between 1 and 160
      and actor_ref ~ '^[a-z][a-z0-9_.:-]*$'
    )
  ),
  constraint command_idempotency_source_check check (
    source in ('user_command', 'system', 'worker', 'scheduler', 'integration', 'migration')
  ),
  constraint command_idempotency_command_name_check check (
    pg_catalog.char_length(command_name) between 3 and 160
    and command_name ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'
  ),
  constraint command_idempotency_key_hash_check check (
    pg_catalog.octet_length(idempotency_key_hash) = 32
  ),
  constraint command_idempotency_fingerprint_check check (
    pg_catalog.octet_length(request_fingerprint) = 32
  ),
  constraint command_idempotency_status_check check (
    status in ('in_progress', 'completed')
  ),
  constraint command_idempotency_result_check check (
    (
      status = 'in_progress'
      and result_version is null
      and result is null
      and completed_at is null
    )
    or (
      status = 'completed'
      and result_version > 0
      and pg_catalog.jsonb_typeof(result) = 'object'
      and completed_at is not null
    )
  ),
  constraint command_idempotency_result_size_check check (
    result is null or pg_catalog.octet_length(result::text) <= 65536
  ),
  constraint command_idempotency_result_keys_check check (
    result is null or not private.jsonb_has_forbidden_event_keys(result)
  ),
  constraint command_idempotency_expiry_check check (
    expires_at is null or expires_at > created_at
  )
);

create index command_idempotency_expires_idx
on private.command_idempotency (expires_at)
where expires_at is not null;

create function private.protect_command_idempotency()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    if old.status <> 'in_progress'
       or new.status <> 'completed'
       or (
         pg_catalog.to_jsonb(new)
           - 'status' - 'result_version' - 'result' - 'completed_at'
       ) is distinct from (
         pg_catalog.to_jsonb(old)
           - 'status' - 'result_version' - 'result' - 'completed_at'
       ) then
      raise exception using
        errcode = '55000',
        message = 'command idempotency identity is immutable';
    end if;

    return new;
  end if;

  raise exception using
    errcode = '55000',
    message = 'command idempotency record cannot be deleted';
end;
$$;

revoke all on function private.protect_command_idempotency()
  from public, anon, authenticated, service_role;

create trigger command_idempotency_protect_update_delete
before update or delete on private.command_idempotency
for each row
execute function private.protect_command_idempotency();

create trigger command_idempotency_reject_truncate
before truncate on private.command_idempotency
for each statement
execute function private.protect_command_idempotency();

create function private.acquire_command_idempotency(
  target_tenant_id uuid,
  command_actor_kind text,
  command_source text,
  target_command_name text,
  command_idempotency_key text,
  command_fingerprint bytea,
  command_actor_user_id uuid default null,
  command_actor_ref text default null,
  command_expires_at timestamptz default null
)
returns table (
  acquired_command_id uuid,
  replayed boolean,
  stored_result_version integer,
  stored_result jsonb
)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  normalized_actor_scope text;
  normalized_key_hash bytea;
  created_command_id uuid := pg_catalog.gen_random_uuid();
  affected_rows integer;
  existing_record record;
begin
  if target_tenant_id is null then
    raise exception using errcode = '22023', message = 'IDEMPOTENCY_TENANT_REQUIRED';
  end if;

  if command_actor_kind = 'application_user' then
    if command_actor_user_id is null
       or command_actor_ref is not null
       or command_source <> 'user_command' then
      raise exception using errcode = '22023', message = 'INVALID_IDEMPOTENCY_ACTOR';
    end if;

    if not exists (
      select 1
      from public.tenant_memberships as membership
      where membership.tenant_id = target_tenant_id
        and membership.user_id = command_actor_user_id
        and membership.status = 'active'
    ) then
      raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_TARGET_UNAVAILABLE';
    end if;

    normalized_actor_scope := 'application_user:' || command_actor_user_id::text;
  elsif command_actor_kind in ('technical', 'system') then
    if command_actor_user_id is not null
       or command_actor_ref is null
       or command_source = 'user_command' then
      raise exception using errcode = '22023', message = 'INVALID_IDEMPOTENCY_ACTOR';
    end if;

    normalized_actor_scope := command_actor_kind || ':' || command_actor_ref;
  else
    raise exception using errcode = '22023', message = 'INVALID_IDEMPOTENCY_ACTOR';
  end if;

  if command_fingerprint is null
     or pg_catalog.octet_length(command_fingerprint) <> 32 then
    raise exception using errcode = '22023', message = 'INVALID_IDEMPOTENCY_FINGERPRINT';
  end if;

  if command_idempotency_key is null
     or command_idempotency_key <> pg_catalog.btrim(command_idempotency_key)
     or pg_catalog.char_length(command_idempotency_key) not between 8 and 200
     or command_idempotency_key !~ '^[A-Za-z0-9][A-Za-z0-9._:-]*$' then
    raise exception using errcode = '22023', message = 'INVALID_IDEMPOTENCY_KEY';
  end if;

  normalized_key_hash := private.semantic_fingerprint(
    pg_catalog.to_jsonb(command_idempotency_key)
  );

  insert into private.command_idempotency (
    tenant_id,
    actor_kind,
    actor_user_id,
    actor_ref,
    actor_scope,
    source,
    command_name,
    idempotency_key_hash,
    command_id,
    request_fingerprint,
    expires_at
  ) values (
    target_tenant_id,
    command_actor_kind,
    command_actor_user_id,
    command_actor_ref,
    normalized_actor_scope,
    command_source,
    target_command_name,
    normalized_key_hash,
    created_command_id,
    command_fingerprint,
    command_expires_at
  )
  on conflict on constraint command_idempotency_namespace_uq do nothing;

  get diagnostics affected_rows = row_count;

  if affected_rows = 1 then
    return query select created_command_id, false, null::integer, null::jsonb;
    return;
  end if;

  select record.* into existing_record
  from private.command_idempotency as record
  where record.tenant_id = target_tenant_id
    and record.actor_scope = normalized_actor_scope
    and record.source = command_source
    and record.command_name = target_command_name
    and record.idempotency_key_hash = normalized_key_hash
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_STATE_UNAVAILABLE';
  end if;

  if existing_record.request_fingerprint <> command_fingerprint then
    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_FINGERPRINT_CONFLICT';
  end if;

  if existing_record.status <> 'completed' then
    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_STATE_UNAVAILABLE';
  end if;

  return query select
    existing_record.command_id,
    true,
    existing_record.result_version,
    existing_record.result;
end;
$$;

revoke all on function private.acquire_command_idempotency(
  uuid, text, text, text, text, bytea, uuid, text, timestamptz
) from public, anon, authenticated, service_role;

create function private.complete_command_idempotency(
  target_command_id uuid,
  command_result_version integer,
  command_result jsonb
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  affected_rows integer;
begin
  if command_result_version is null or command_result_version <= 0 then
    raise exception using errcode = '22023', message = 'INVALID_IDEMPOTENCY_RESULT_VERSION';
  end if;

  if command_result is null or pg_catalog.jsonb_typeof(command_result) <> 'object' then
    raise exception using errcode = '22023', message = 'INVALID_IDEMPOTENCY_RESULT';
  end if;

  update private.command_idempotency as record
  set
    status = 'completed',
    result_version = command_result_version,
    result = command_result,
    completed_at = statement_timestamp()
  where record.command_id = target_command_id
    and record.status = 'in_progress';

  get diagnostics affected_rows = row_count;

  if affected_rows <> 1 then
    raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_COMPLETION_UNAVAILABLE';
  end if;
end;
$$;

revoke all on function private.complete_command_idempotency(uuid, integer, jsonb)
  from public, anon, authenticated, service_role;

alter table private.outbox_events
  add constraint outbox_events_event_tenant_uq unique (event_id, tenant_id);

create table private.event_handler_receipts (
  receipt_id uuid primary key default pg_catalog.gen_random_uuid(),
  consumer_name text not null,
  event_id uuid not null,
  tenant_id uuid not null,
  event_type text not null,
  event_version integer not null,
  handler_name text not null,
  handler_version integer not null,
  result_version integer not null,
  result jsonb not null default '{}'::jsonb,
  completed_at timestamptz not null default statement_timestamp(),
  constraint event_handler_receipts_consumer_event_uq unique (consumer_name, event_id),
  constraint event_handler_receipts_origin_fk
    foreign key (event_id, tenant_id)
    references private.outbox_events (event_id, tenant_id)
    on delete restrict,
  constraint event_handler_receipts_consumer_check check (
    pg_catalog.char_length(consumer_name) between 3 and 160
    and consumer_name ~ '^[a-z][a-z0-9_.:-]*$'
  ),
  constraint event_handler_receipts_event_type_check check (
    pg_catalog.char_length(event_type) between 5 and 160
    and event_type ~ '^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$'
  ),
  constraint event_handler_receipts_event_version_check check (event_version > 0),
  constraint event_handler_receipts_handler_check check (
    pg_catalog.char_length(handler_name) between 3 and 160
    and handler_name ~ '^[a-z][a-z0-9_.:-]*$'
    and handler_version > 0
  ),
  constraint event_handler_receipts_result_check check (
    result_version > 0 and pg_catalog.jsonb_typeof(result) = 'object'
  ),
  constraint event_handler_receipts_result_size_check check (
    pg_catalog.octet_length(result::text) <= 65536
  ),
  constraint event_handler_receipts_result_keys_check check (
    not private.jsonb_has_forbidden_event_keys(result)
  )
);

create index event_handler_receipts_tenant_completed_idx
on private.event_handler_receipts (tenant_id, completed_at desc);

create function private.reject_event_handler_receipt_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using
    errcode = '55000',
    message = 'event handler receipt is immutable';
end;
$$;

revoke all on function private.reject_event_handler_receipt_mutation()
  from public, anon, authenticated, service_role;

create trigger event_handler_receipts_reject_update_delete
before update or delete on private.event_handler_receipts
for each row
execute function private.reject_event_handler_receipt_mutation();

create trigger event_handler_receipts_reject_truncate
before truncate on private.event_handler_receipts
for each statement
execute function private.reject_event_handler_receipt_mutation();

create function private.record_event_handler_receipt(
  target_consumer_name text,
  target_event_id uuid,
  target_handler_name text,
  target_handler_version integer,
  target_result_version integer,
  target_result jsonb default '{}'::jsonb
)
returns table (
  stored_receipt_id uuid,
  replayed boolean,
  stored_result_version integer,
  stored_result jsonb
)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  origin_event record;
  created_receipt_id uuid;
  affected_rows integer;
  existing_receipt record;
begin
  select
    event.tenant_id,
    event.event_type,
    event.event_version
  into origin_event
  from private.outbox_events as event
  where event.event_id = target_event_id;

  if not found then
    raise exception using errcode = 'P0001', message = 'HANDLER_EVENT_UNAVAILABLE';
  end if;

  created_receipt_id := pg_catalog.gen_random_uuid();

  insert into private.event_handler_receipts (
    receipt_id,
    consumer_name,
    event_id,
    tenant_id,
    event_type,
    event_version,
    handler_name,
    handler_version,
    result_version,
    result
  ) values (
    created_receipt_id,
    target_consumer_name,
    target_event_id,
    origin_event.tenant_id,
    origin_event.event_type,
    origin_event.event_version,
    target_handler_name,
    target_handler_version,
    target_result_version,
    coalesce(target_result, '{}'::jsonb)
  )
  on conflict on constraint event_handler_receipts_consumer_event_uq do nothing;

  get diagnostics affected_rows = row_count;

  if affected_rows = 1 then
    return query select created_receipt_id, false, target_result_version, coalesce(target_result, '{}'::jsonb);
    return;
  end if;

  select receipt.* into existing_receipt
  from private.event_handler_receipts as receipt
  where receipt.consumer_name = target_consumer_name
    and receipt.event_id = target_event_id;

  if existing_receipt.handler_name <> target_handler_name
     or existing_receipt.handler_version <> target_handler_version then
    raise exception using errcode = 'P0001', message = 'HANDLER_RECEIPT_CONFLICT';
  end if;

  return query select
    existing_receipt.receipt_id,
    true,
    existing_receipt.result_version,
    existing_receipt.result;
end;
$$;

revoke all on function private.record_event_handler_receipt(
  text, uuid, text, integer, integer, jsonb
) from public, anon, authenticated, service_role;

-- Compatibility is preserved by retaining the W3B three-argument signature and
-- adding a four-argument overload with the existing correlation position intact.
create function public.create_tenant_profile(
  profile_name text,
  command_reason text,
  correlation_id uuid,
  command_idempotency_key text
)
returns table (profile_id uuid, profile_version bigint, command_correlation_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor record;
  idempotency record;
  semantic_fingerprint bytea;
  created_profile_id uuid;
  created_profile_version bigint;
  stable_result jsonb;
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

  semantic_fingerprint := private.semantic_fingerprint(
    pg_catalog.jsonb_build_object(
      'command_name', 'authorization.create_tenant_profile',
      'profile_name', profile_name,
      'command_reason', command_reason
    )
  );

  select * into idempotency
  from private.acquire_command_idempotency(
    actor.actor_tenant_id,
    'application_user',
    'user_command',
    'authorization.create_tenant_profile',
    command_idempotency_key,
    semantic_fingerprint,
    actor.actor_user_id,
    null,
    null
  );

  if idempotency.replayed then
    return query select
      (idempotency.stored_result ->> 'profile_id')::uuid,
      (idempotency.stored_result ->> 'profile_version')::bigint,
      (idempotency.stored_result ->> 'command_correlation_id')::uuid;
    return;
  end if;

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
    idempotency.acquired_command_id,
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
    idempotency.acquired_command_id,
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

  stable_result := pg_catalog.jsonb_build_object(
    'profile_id', created_profile_id,
    'profile_version', created_profile_version,
    'command_correlation_id', correlation_id
  );

  perform private.complete_command_idempotency(
    idempotency.acquired_command_id,
    1,
    stable_result
  );

  return query select created_profile_id, created_profile_version, correlation_id;
exception
  when unique_violation then
    raise exception using errcode = 'P0001', message = 'AUTHORIZATION_OPERATION_UNAVAILABLE';
end;
$$;

alter table private.command_idempotency enable row level security;
alter table private.event_handler_receipts enable row level security;

revoke all privileges on table private.command_idempotency from public;
revoke all privileges on table private.command_idempotency from anon;
revoke all privileges on table private.command_idempotency from authenticated;
revoke all privileges on table private.command_idempotency from service_role;
revoke all privileges on table private.event_handler_receipts from public;
revoke all privileges on table private.event_handler_receipts from anon;
revoke all privileges on table private.event_handler_receipts from authenticated;
revoke all privileges on table private.event_handler_receipts from service_role;

revoke all on function public.create_tenant_profile(text, text, uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.create_tenant_profile(text, text, uuid, text)
  to authenticated;

alter table private.command_idempotency owner to postgres;
alter table private.event_handler_receipts owner to postgres;
alter function private.semantic_fingerprint(jsonb) owner to postgres;
alter function private.protect_command_idempotency() owner to postgres;
alter function private.acquire_command_idempotency(
  uuid, text, text, text, text, bytea, uuid, text, timestamptz
) owner to postgres;
alter function private.complete_command_idempotency(uuid, integer, jsonb) owner to postgres;
alter function private.reject_event_handler_receipt_mutation() owner to postgres;
alter function private.record_event_handler_receipt(
  text, uuid, text, integer, integer, jsonb
) owner to postgres;
alter function public.create_tenant_profile(text, text, uuid, text) owner to postgres;

comment on table private.command_idempotency is
  'W3C command replay store scoped by tenant, actor/source, command and opaque key.';
comment on table private.event_handler_receipts is
  'W3C immutable evidence of completed consumer processing, unique by consumer and event.';
comment on function private.semantic_fingerprint(jsonb) is
  'Canonical JSONB SHA-256 fingerprint for trusted semantic command input.';
comment on function public.create_tenant_profile(text, text, uuid, text) is
  'W3C idempotent overload. Existing W3B signature remains available for compatible callers.';
