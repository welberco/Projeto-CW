-- CW ERP V2 / W3A: Audit evolution and functional History foundation.

create function private.jsonb_has_forbidden_history_keys(document jsonb)
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

  if pg_catalog.jsonb_typeof(document) = 'object' then
    for key_name, child in
      select entry.key, entry.value
      from pg_catalog.jsonb_each(document) as entry(key, value)
    loop
      if pg_catalog.lower(key_name) = any (array[
        'password', 'password_hash', 'jwt', 'access_token', 'refresh_token',
        'invitation_token', 'raw_invitation_token', 'service_role',
        'service_role_key', 'credential', 'credentials', 'signed_url'
      ]::text[]) then
        return true;
      end if;

      if private.jsonb_has_forbidden_history_keys(child) then
        return true;
      end if;
    end loop;
  elsif pg_catalog.jsonb_typeof(document) = 'array' then
    for child in
      select element.value
      from pg_catalog.jsonb_array_elements(document) as element(value)
    loop
      if private.jsonb_has_forbidden_history_keys(child) then
        return true;
      end if;
    end loop;
  end if;

  return false;
end;
$$;

revoke all on function private.jsonb_has_forbidden_history_keys(jsonb)
  from public, anon, authenticated, service_role;

alter table public.audit_events
  add column event_version integer not null default 1,
  add column command_id uuid,
  add column causation_id uuid,
  add column source text,
  add column actor_ref text,
  add column reason text,
  add column authority_kind text generated always as (
    case actor_kind
      when 'application_user' then 'tenant'
      when 'platform' then 'platform'
      else 'technical'
    end
  ) stored;

alter table public.audit_events
  drop constraint audit_events_actor_kind_check,
  drop constraint audit_events_actor_check,
  add constraint audit_events_actor_kind_check check (
    actor_kind in ('application_user', 'technical', 'system', 'platform')
  ),
  add constraint audit_events_actor_check check (
    (actor_kind = 'application_user' and actor_user_id is not null)
    or actor_kind in ('technical', 'system', 'platform')
  ),
  add constraint audit_events_authority_kind_check check (
    authority_kind in ('tenant', 'technical', 'platform')
  ),
  add constraint audit_events_event_version_check check (event_version > 0),
  add constraint audit_events_source_check check (
    source is null
    or source in (
      'user_command', 'system', 'worker', 'scheduler',
      'integration', 'platform', 'migration'
    )
  ),
  add constraint audit_events_actor_ref_check check (
    actor_ref is null
    or (
      actor_ref = pg_catalog.btrim(actor_ref)
      and pg_catalog.char_length(actor_ref) between 1 and 160
      and actor_ref ~ '^[a-z][a-z0-9_.:-]*$'
    )
  ),
  add constraint audit_events_reason_check check (
    reason is null
    or (
      reason = pg_catalog.btrim(reason)
      and pg_catalog.char_length(reason) between 1 and 500
    )
  ),
  add constraint audit_events_metadata_size_check check (
    pg_catalog.octet_length(metadata::text) <= 65536
  ),
  add constraint audit_events_metadata_forbidden_keys_check check (
    not private.jsonb_has_forbidden_history_keys(metadata)
  );

create index audit_events_correlation_idx
on public.audit_events (correlation_id, occurred_at desc);

create index audit_events_command_idx
on public.audit_events (command_id, occurred_at desc)
where command_id is not null;

create function private.prepare_audit_event()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.actor_kind = 'application_user' then
    if new.actor_user_id is null or new.actor_ref is not null then
      raise exception using errcode = '22023', message = 'INVALID_AUDIT_ACTOR';
    end if;
  elsif new.actor_kind in ('technical', 'system', 'platform') then
    if new.actor_user_id is not null then
      raise exception using errcode = '22023', message = 'INVALID_AUDIT_ACTOR';
    end if;

    -- W1/W2 technical writers predate actor_ref. New rows receive an explicit
    -- compatibility provenance; existing historical rows are not rewritten.
    if new.actor_ref is null then
      new.actor_ref := case new.actor_kind
        when 'platform' then 'platform:legacy-writer'
        when 'system' then 'system:legacy-writer'
        else 'technical:legacy-writer'
      end;
    end if;
  else
    raise exception using errcode = '22023', message = 'INVALID_AUDIT_ACTOR';
  end if;

  if new.source is null then
    new.source := case new.actor_kind
      when 'application_user' then 'user_command'
      when 'platform' then 'platform'
      else 'system'
    end;
  end if;

  return new;
end;
$$;

revoke all on function private.prepare_audit_event()
  from public, anon, authenticated, service_role;

create trigger audit_events_prepare_insert
before insert on public.audit_events
for each row
execute function private.prepare_audit_event();

create function private.append_audit(
  audit_tenant_id uuid,
  audit_actor_kind text,
  audit_event_type text,
  audit_entity_type text,
  audit_correlation_id uuid,
  audit_source text,
  audit_actor_user_id uuid default null,
  audit_actor_ref text default null,
  audit_entity_id uuid default null,
  audit_command_id uuid default null,
  audit_causation_id uuid default null,
  audit_event_version integer default 1,
  audit_reason text default null,
  audit_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  created_audit_id uuid;
  normalized_metadata jsonb := coalesce(audit_metadata, '{}'::jsonb);
begin
  if audit_actor_kind = 'application_user' then
    if audit_actor_user_id is null or audit_actor_ref is not null then
      raise exception using errcode = '22023', message = 'INVALID_AUDIT_ACTOR';
    end if;
  elsif audit_actor_kind in ('technical', 'system', 'platform') then
    if audit_actor_user_id is not null or audit_actor_ref is null then
      raise exception using errcode = '22023', message = 'INVALID_AUDIT_ACTOR';
    end if;
  else
    raise exception using errcode = '22023', message = 'INVALID_AUDIT_ACTOR';
  end if;

  if audit_reason is not null then
    normalized_metadata := normalized_metadata
      || pg_catalog.jsonb_build_object('reason', audit_reason);
  end if;

  insert into public.audit_events (
    tenant_id,
    actor_user_id,
    actor_kind,
    actor_ref,
    correlation_id,
    command_id,
    causation_id,
    source,
    event_type,
    event_version,
    entity_type,
    entity_id,
    reason,
    metadata
  ) values (
    audit_tenant_id,
    audit_actor_user_id,
    audit_actor_kind,
    audit_actor_ref,
    audit_correlation_id,
    audit_command_id,
    audit_causation_id,
    audit_source,
    audit_event_type,
    audit_event_version,
    audit_entity_type,
    audit_entity_id,
    audit_reason,
    normalized_metadata
  )
  returning id into created_audit_id;

  return created_audit_id;
end;
$$;

revoke all on function private.append_audit(
  uuid, text, text, text, uuid, text, uuid, text, uuid, uuid, uuid,
  integer, text, jsonb
) from public, anon, authenticated, service_role;

create table public.history_entries (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  aggregate_type text not null,
  aggregate_id uuid not null,
  aggregate_version bigint,
  human_code text,
  history_type text not null,
  history_version integer not null default 1,
  occurred_at timestamptz not null default statement_timestamp(),
  actor_kind text not null,
  actor_user_id uuid references public.app_users (id) on delete restrict,
  actor_ref text,
  command_name text not null,
  command_id uuid not null,
  correlation_id uuid not null,
  causation_id uuid,
  source text not null,
  payload jsonb not null default '{}'::jsonb,
  constraint history_entries_aggregate_type_check check (
    pg_catalog.char_length(aggregate_type) between 1 and 80
    and aggregate_type ~ '^[a-z][a-z0-9_]*$'
  ),
  constraint history_entries_aggregate_version_check check (
    aggregate_version is null or aggregate_version > 0
  ),
  constraint history_entries_human_code_check check (
    human_code is null
    or (
      human_code = pg_catalog.btrim(human_code)
      and pg_catalog.char_length(human_code) between 1 and 120
    )
  ),
  constraint history_entries_history_type_check check (
    pg_catalog.char_length(history_type) between 5 and 160
    and history_type ~ '^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$'
  ),
  constraint history_entries_history_version_check check (history_version > 0),
  constraint history_entries_actor_kind_check check (
    actor_kind in ('application_user', 'technical', 'system', 'platform')
  ),
  constraint history_entries_actor_check check (
    (
      actor_kind = 'application_user'
      and actor_user_id is not null
      and actor_ref is null
    )
    or (
      actor_kind in ('technical', 'system', 'platform')
      and actor_user_id is null
      and actor_ref is not null
    )
  ),
  constraint history_entries_actor_ref_check check (
    actor_ref is null
    or (
      actor_ref = pg_catalog.btrim(actor_ref)
      and pg_catalog.char_length(actor_ref) between 1 and 160
      and actor_ref ~ '^[a-z][a-z0-9_.:-]*$'
    )
  ),
  constraint history_entries_command_name_check check (
    pg_catalog.char_length(command_name) between 3 and 160
    and command_name ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'
  ),
  constraint history_entries_source_check check (
    source in (
      'user_command', 'system', 'worker', 'scheduler',
      'integration', 'platform', 'migration'
    )
  ),
  constraint history_entries_payload_object_check check (
    pg_catalog.jsonb_typeof(payload) = 'object'
  ),
  constraint history_entries_payload_size_check check (
    pg_catalog.octet_length(payload::text) <= 65536
  ),
  constraint history_entries_payload_forbidden_keys_check check (
    not private.jsonb_has_forbidden_history_keys(payload)
  )
);

create index history_entries_tenant_aggregate_timeline_idx
on public.history_entries (
  tenant_id,
  aggregate_type,
  aggregate_id,
  occurred_at desc,
  id desc
);

create index history_entries_command_idx
on public.history_entries (command_id, occurred_at desc);

create function private.reject_history_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using
    errcode = '55000',
    message = 'history_entries is append-only';
end;
$$;

revoke all on function private.reject_history_mutation()
  from public, anon, authenticated, service_role;

create trigger history_entries_reject_update_delete
before update or delete on public.history_entries
for each row
execute function private.reject_history_mutation();

create trigger history_entries_reject_truncate
before truncate on public.history_entries
for each statement
execute function private.reject_history_mutation();

create function private.append_history(
  target_tenant_id uuid,
  target_aggregate_type text,
  target_aggregate_id uuid,
  target_history_type text,
  history_actor_kind text,
  history_command_name text,
  history_command_id uuid,
  history_correlation_id uuid,
  history_source text,
  target_aggregate_version bigint default null,
  target_human_code text default null,
  target_history_version integer default 1,
  history_actor_user_id uuid default null,
  history_actor_ref text default null,
  history_causation_id uuid default null,
  history_payload jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  created_history_id uuid;
begin
  if history_actor_kind = 'application_user' then
    if history_actor_user_id is null or history_actor_ref is not null then
      raise exception using errcode = '22023', message = 'INVALID_HISTORY_ACTOR';
    end if;

    if not exists (
      select 1
      from public.tenant_memberships as membership
      where membership.tenant_id = target_tenant_id
        and membership.user_id = history_actor_user_id
    ) then
      raise exception using errcode = 'P0001', message = 'HISTORY_TARGET_UNAVAILABLE';
    end if;
  elsif history_actor_kind in ('technical', 'system', 'platform') then
    if history_actor_user_id is not null or history_actor_ref is null then
      raise exception using errcode = '22023', message = 'INVALID_HISTORY_ACTOR';
    end if;
  else
    raise exception using errcode = '22023', message = 'INVALID_HISTORY_ACTOR';
  end if;

  insert into public.history_entries (
    tenant_id,
    aggregate_type,
    aggregate_id,
    aggregate_version,
    human_code,
    history_type,
    history_version,
    actor_kind,
    actor_user_id,
    actor_ref,
    command_name,
    command_id,
    correlation_id,
    causation_id,
    source,
    payload
  ) values (
    target_tenant_id,
    target_aggregate_type,
    target_aggregate_id,
    target_aggregate_version,
    target_human_code,
    target_history_type,
    target_history_version,
    history_actor_kind,
    history_actor_user_id,
    history_actor_ref,
    history_command_name,
    history_command_id,
    history_correlation_id,
    history_causation_id,
    history_source,
    coalesce(history_payload, '{}'::jsonb)
  )
  returning id into created_history_id;

  return created_history_id;
end;
$$;

revoke all on function private.append_history(
  uuid, text, uuid, text, text, text, uuid, uuid, text, bigint, text,
  integer, uuid, text, uuid, jsonb
) from public, anon, authenticated, service_role;

create or replace function private.write_authorization_audit(
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
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.append_audit(
    target_tenant_id,
    'application_user',
    command_event_type,
    target_entity_type,
    command_correlation_id,
    'user_command',
    actor_user_id,
    null,
    target_entity_id,
    pg_catalog.gen_random_uuid(),
    null,
    1,
    command_reason,
    command_metadata
  );
end;
$$;

revoke all on function private.write_authorization_audit(
  uuid, uuid, uuid, text, text, uuid, text, jsonb
) from public, anon, authenticated, service_role;

alter table public.history_entries enable row level security;

revoke all privileges on table public.history_entries from public;
revoke all privileges on table public.history_entries from anon;
revoke all privileges on table public.history_entries from authenticated;
revoke all privileges on table public.history_entries from service_role;

alter table public.history_entries owner to postgres;
alter function private.jsonb_has_forbidden_history_keys(jsonb) owner to postgres;
alter function private.prepare_audit_event() owner to postgres;
alter function private.append_audit(
  uuid, text, text, text, uuid, text, uuid, text, uuid, uuid, uuid,
  integer, text, jsonb
) owner to postgres;
alter function private.reject_history_mutation() owner to postgres;
alter function private.append_history(
  uuid, text, uuid, text, text, text, uuid, uuid, text, bigint, text,
  integer, uuid, text, uuid, jsonb
) owner to postgres;
alter function private.write_authorization_audit(
  uuid, uuid, uuid, text, text, uuid, text, jsonb
) owner to postgres;

comment on table public.history_entries is
  'Append-only tenant functional History envelope. Domain projections remain deferred to domain waves.';
comment on function private.append_audit(
  uuid, text, text, text, uuid, text, uuid, text, uuid, uuid, uuid,
  integer, text, jsonb
) is 'Private W3A Audit writer for trusted transactional commands.';
comment on function private.append_history(
  uuid, text, uuid, text, text, text, uuid, uuid, text, bigint, text,
  integer, uuid, text, uuid, jsonb
) is 'Private W3A functional History writer. Tenant, actor and aggregate facts are supplied only by trusted commands.';
