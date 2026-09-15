-- CW ERP V2 / W3D: local delivery runtime with lease, fencing, retry and dead-letter.

do $$
begin
  if not exists (select 1 from pg_catalog.pg_roles where rolname = 'cw_worker') then
    create role cw_worker nologin noinherit;
  end if;
end;
$$;

-- The local runner connects as the controlled database owner and explicitly
-- assumes the no-login worker role before invoking any delivery boundary.
grant cw_worker to postgres;

create table private.worker_handler_controls (
  event_type text not null,
  event_version integer not null,
  consumer_name text not null,
  handler_name text not null,
  handler_version integer not null,
  enabled boolean not null default true,
  lease_seconds integer not null default 30,
  max_attempts integer not null default 3,
  backoff_base_seconds integer not null default 1,
  backoff_max_seconds integer not null default 60,
  jitter_percent integer not null default 20,
  updated_at timestamptz not null default statement_timestamp(),
  primary key (event_type, event_version),
  constraint worker_handler_controls_event_type_check check (
    pg_catalog.char_length(event_type) between 5 and 160
    and event_type ~ '^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$'
  ),
  constraint worker_handler_controls_event_version_check check (event_version > 0),
  constraint worker_handler_controls_consumer_check check (
    pg_catalog.char_length(consumer_name) between 3 and 160
    and consumer_name ~ '^[a-z][a-z0-9_.:-]*$'
  ),
  constraint worker_handler_controls_handler_check check (
    pg_catalog.char_length(handler_name) between 3 and 160
    and handler_name ~ '^[a-z][a-z0-9_.:-]*$'
    and handler_version > 0
  ),
  constraint worker_handler_controls_lease_check check (lease_seconds between 1 and 3600),
  constraint worker_handler_controls_attempts_check check (max_attempts between 1 and 100),
  constraint worker_handler_controls_backoff_check check (
    backoff_base_seconds between 1 and 86400
    and backoff_max_seconds between backoff_base_seconds and 604800
  ),
  constraint worker_handler_controls_jitter_check check (jitter_percent between 0 and 100)
);

insert into private.worker_handler_controls (
  event_type, event_version, consumer_name, handler_name, handler_version,
  enabled, lease_seconds, max_attempts,
  backoff_base_seconds, backoff_max_seconds, jitter_percent
) values (
  'authorization.profile.created', 1,
  'cw.authorization.profile_projection',
  'authorization_profile_created_v1', 1,
  true, 30, 3, 1, 60, 20
);

alter table private.outbox_events
  add column claimed_by text,
  add column claimed_at timestamptz,
  add column lease_expires_at timestamptz,
  add column lease_token uuid,
  add column fencing_token bigint not null default 0,
  add column processed_at timestamptz,
  add column last_failed_at timestamptz,
  add column dead_lettered_at timestamptz,
  add column last_error_class text,
  add column last_error_code text,
  add column last_error_message text,
  add column requeue_count integer not null default 0,
  add constraint outbox_events_claim_identity_check check (
    claimed_by is null
    or (
      claimed_by = pg_catalog.btrim(claimed_by)
      and pg_catalog.char_length(claimed_by) between 3 and 160
      and claimed_by ~ '^[a-z][a-z0-9_.:-]*$'
    )
  ),
  add constraint outbox_events_fencing_check check (fencing_token >= 0),
  add constraint outbox_events_requeue_count_check check (requeue_count >= 0),
  add constraint outbox_events_error_class_check check (
    last_error_class is null
    or last_error_class in (
      'retryable', 'non_retryable', 'poison_event',
      'unsupported_event', 'attempts_exhausted'
    )
  ),
  add constraint outbox_events_error_code_check check (
    last_error_code is null
    or (
      pg_catalog.char_length(last_error_code) between 3 and 64
      and last_error_code ~ '^[A-Z][A-Z0-9_]*$'
    )
  ),
  add constraint outbox_events_error_message_check check (
    last_error_message is null
    or pg_catalog.char_length(last_error_message) between 1 and 500
  ),
  add constraint outbox_events_delivery_state_check check (
    (
      status = 'pending'
      and claimed_by is null and claimed_at is null
      and lease_expires_at is null and lease_token is null
      and processed_at is null and dead_lettered_at is null
    )
    or (
      status = 'processing'
      and claimed_by is not null and claimed_at is not null
      and lease_expires_at is not null and lease_token is not null
      and lease_expires_at > claimed_at
      and processed_at is null and dead_lettered_at is null
    )
    or (
      status = 'processed'
      and claimed_by is null and claimed_at is null
      and lease_expires_at is null and lease_token is null
      and processed_at is not null and dead_lettered_at is null
    )
    or (
      status = 'dead_letter'
      and claimed_by is null and claimed_at is null
      and lease_expires_at is null and lease_token is null
      and processed_at is null and dead_lettered_at is not null
      and last_error_class is not null and last_error_code is not null
    )
  );

create index outbox_events_processing_lease_idx
on private.outbox_events (lease_expires_at, occurred_at, event_id)
where status = 'processing';

create or replace function private.protect_outbox_event()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    if (
      pg_catalog.to_jsonb(new)
        - 'status' - 'attempt_count' - 'next_attempt_at'
        - 'claimed_by' - 'claimed_at' - 'lease_expires_at' - 'lease_token'
        - 'fencing_token' - 'processed_at' - 'last_failed_at'
        - 'dead_lettered_at' - 'last_error_class' - 'last_error_code'
        - 'last_error_message' - 'requeue_count'
    ) is distinct from (
      pg_catalog.to_jsonb(old)
        - 'status' - 'attempt_count' - 'next_attempt_at'
        - 'claimed_by' - 'claimed_at' - 'lease_expires_at' - 'lease_token'
        - 'fencing_token' - 'processed_at' - 'last_failed_at'
        - 'dead_lettered_at' - 'last_error_class' - 'last_error_code'
        - 'last_error_message' - 'requeue_count'
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

create function private.assert_current_outbox_lease(
  target_event_id uuid,
  worker_identity text,
  current_lease_token uuid,
  current_fencing_token bigint,
  check_enabled boolean default false
)
returns private.outbox_events
language plpgsql
security invoker
set search_path = ''
as $$
declare
  claimed_event private.outbox_events;
begin
  select event.* into claimed_event
  from private.outbox_events as event
  where event.event_id = target_event_id
  for update;

  if not found
     or claimed_event.status <> 'processing'
     or claimed_event.claimed_by is distinct from worker_identity
     or claimed_event.lease_token is distinct from current_lease_token
     or claimed_event.fencing_token is distinct from current_fencing_token
     or claimed_event.lease_expires_at <= pg_catalog.clock_timestamp() then
    raise exception using errcode = 'P0001', message = 'OUTBOX_LEASE_STALE';
  end if;

  if check_enabled and not exists (
    select 1
    from private.worker_handler_controls as control
    where control.event_type = claimed_event.event_type
      and control.event_version = claimed_event.event_version
      and control.enabled
  ) then
    raise exception using errcode = 'P0001', message = 'OUTBOX_HANDLER_DISABLED';
  end if;

  return claimed_event;
end;
$$;

create function private.sanitize_worker_error(error_message text)
returns text
language plpgsql
immutable
parallel safe
security invoker
set search_path = ''
as $$
declare
  normalized text := pg_catalog.regexp_replace(
    pg_catalog.btrim(error_message), '[\r\n\t]+', ' ', 'g'
  );
begin
  if normalized is null
     or pg_catalog.char_length(normalized) not between 1 and 500 then
    raise exception using errcode = '22023', message = 'UNSAFE_WORKER_ERROR';
  end if;

  if normalized ~* '(^|[[:space:]:=])bearer[[:space:]]+[a-z0-9._~+/-]+'
     or normalized ~* '(^|[^a-z0-9_-])eyj[a-z0-9_-]{4,}\.[a-z0-9_-]{4,}\.[a-z0-9_-]{4,}($|[^a-z0-9_-])'
     or normalized ~* '(^|[?&;[:space:],])(x[-_](amz|goog)[-_])?(access[_-]?token|refresh[_-]?token|id[_-]?token|api[_-]?key|apikey|authorization|credential|token|signature|sig|secret|password|passwd)[[:space:]]*[:=]'
     or normalized ~* '(service[_-]?role[[:space:]]*[:=]|postgres(ql)?://|stack[[:space:]_-]?trace)' then
    return 'Sensitive worker error details were redacted.';
  end if;

  return normalized;
end;
$$;

create function public.claim_outbox_batch(
  worker_identity text,
  batch_size integer default 10
)
returns table (
  event_id uuid,
  event_type text,
  event_version integer,
  occurred_at timestamptz,
  scope_kind text,
  tenant_id uuid,
  aggregate_type text,
  aggregate_id uuid,
  aggregate_version bigint,
  actor_kind text,
  actor_user_id uuid,
  actor_ref text,
  source text,
  command_id uuid,
  correlation_id uuid,
  causation_id uuid,
  payload jsonb,
  metadata jsonb,
  attempt_count integer,
  claimed_by text,
  lease_expires_at timestamptz,
  lease_token uuid,
  fencing_token bigint,
  consumer_name text,
  handler_name text,
  handler_version integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  claim_time timestamptz := pg_catalog.clock_timestamp();
begin
  if worker_identity is null
     or worker_identity <> pg_catalog.btrim(worker_identity)
     or pg_catalog.char_length(worker_identity) not between 3 and 160
     or worker_identity !~ '^[a-z][a-z0-9_.:-]*$' then
    raise exception using errcode = '22023', message = 'INVALID_WORKER_IDENTITY';
  end if;

  if batch_size is null or batch_size not between 1 and 100 then
    raise exception using errcode = '22023', message = 'INVALID_OUTBOX_BATCH_SIZE';
  end if;

  update private.outbox_events as unsupported
  set
    status = 'dead_letter',
    claimed_by = null,
    claimed_at = null,
    lease_expires_at = null,
    lease_token = null,
    dead_lettered_at = claim_time,
    last_failed_at = claim_time,
    last_error_class = 'unsupported_event',
    last_error_code = 'EVENT_CONTRACT_UNSUPPORTED',
    last_error_message = 'Event contract is not allowlisted.'
  where unsupported.status in ('pending', 'processing')
    and (unsupported.status = 'pending' or unsupported.lease_expires_at <= claim_time)
    and not exists (
      select 1
      from private.worker_handler_controls as known_control
      where known_control.event_type = unsupported.event_type
        and known_control.event_version = unsupported.event_version
    );

  update private.outbox_events as exhausted
  set
    status = 'dead_letter',
    claimed_by = null,
    claimed_at = null,
    lease_expires_at = null,
    lease_token = null,
    dead_lettered_at = claim_time,
    last_failed_at = claim_time,
    last_error_class = 'attempts_exhausted',
    last_error_code = 'DELIVERY_ATTEMPTS_EXHAUSTED',
    last_error_message = 'Delivery attempt limit exhausted.'
  from private.worker_handler_controls as control
  where control.event_type = exhausted.event_type
    and control.event_version = exhausted.event_version
    and exhausted.status in ('pending', 'processing')
    and (exhausted.status = 'pending' or exhausted.lease_expires_at <= claim_time)
    and exhausted.attempt_count >= control.max_attempts * (exhausted.requeue_count + 1);

  return query
  with candidates as (
    select candidate.event_id
    from private.outbox_events as candidate
    join private.worker_handler_controls as control
      on control.event_type = candidate.event_type
     and control.event_version = candidate.event_version
    where control.enabled
      and candidate.attempt_count < control.max_attempts * (candidate.requeue_count + 1)
      and (
        (candidate.status = 'pending' and candidate.next_attempt_at <= claim_time)
        or (candidate.status = 'processing' and candidate.lease_expires_at <= claim_time)
      )
    order by candidate.next_attempt_at, candidate.occurred_at, candidate.event_id
    for update of candidate skip locked
    limit batch_size
  ), claimed as (
    update private.outbox_events as event
    set
      status = 'processing',
      attempt_count = event.attempt_count + 1,
      claimed_by = worker_identity,
      claimed_at = claim_time,
      lease_expires_at = claim_time + pg_catalog.make_interval(secs => control.lease_seconds),
      lease_token = pg_catalog.gen_random_uuid(),
      fencing_token = event.fencing_token + 1
    from candidates, private.worker_handler_controls as control
    where event.event_id = candidates.event_id
      and control.event_type = event.event_type
      and control.event_version = event.event_version
    returning event.*, control.consumer_name, control.handler_name, control.handler_version
  )
  select
    claimed.event_id, claimed.event_type, claimed.event_version,
    claimed.occurred_at, claimed.scope_kind, claimed.tenant_id,
    claimed.aggregate_type, claimed.aggregate_id, claimed.aggregate_version,
    claimed.actor_kind, claimed.actor_user_id, claimed.actor_ref,
    claimed.source, claimed.command_id, claimed.correlation_id,
    claimed.causation_id, claimed.payload, claimed.metadata,
    claimed.attempt_count, claimed.claimed_by, claimed.lease_expires_at,
    claimed.lease_token, claimed.fencing_token,
    claimed.consumer_name, claimed.handler_name, claimed.handler_version
  from claimed
  order by claimed.next_attempt_at, claimed.occurred_at, claimed.event_id;
end;
$$;

create function public.read_profile_created_origin(
  target_event_id uuid,
  worker_identity text,
  current_lease_token uuid,
  current_fencing_token bigint
)
returns table (
  authoritative_tenant_id uuid,
  authoritative_profile_id uuid,
  authoritative_profile_version bigint,
  authoritative_profile_status text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  claimed_event private.outbox_events;
begin
  claimed_event := private.assert_current_outbox_lease(
    target_event_id, worker_identity, current_lease_token, current_fencing_token, true
  );

  if claimed_event.event_type <> 'authorization.profile.created'
     or claimed_event.event_version <> 1
     or claimed_event.aggregate_type <> 'tenant_profile'
     or claimed_event.aggregate_id is null
     or claimed_event.aggregate_version is null then
    raise exception using errcode = 'P0001', message = 'OUTBOX_ORIGIN_CONTRACT_MISMATCH';
  end if;

  return query
  select profile.tenant_id, profile.id, profile.version, profile.status
  from public.tenant_profiles as profile
  where profile.id = claimed_event.aggregate_id
    and profile.tenant_id = claimed_event.tenant_id;

  if not found then
    raise exception using errcode = 'P0001', message = 'OUTBOX_ORIGIN_UNAVAILABLE';
  end if;
end;
$$;

create function public.complete_outbox_event(
  target_event_id uuid,
  worker_identity text,
  current_lease_token uuid,
  current_fencing_token bigint,
  handler_result_version integer,
  handler_result jsonb default '{}'::jsonb
)
returns table (receipt_id uuid, receipt_replayed boolean)
language plpgsql
security definer
set search_path = ''
as $$
declare
  claimed_event private.outbox_events;
  control private.worker_handler_controls;
  receipt record;
begin
  claimed_event := private.assert_current_outbox_lease(
    target_event_id, worker_identity, current_lease_token, current_fencing_token, true
  );

  select setting.* into control
  from private.worker_handler_controls as setting
  where setting.event_type = claimed_event.event_type
    and setting.event_version = claimed_event.event_version
    and setting.enabled;

  if not found then
    raise exception using errcode = 'P0001', message = 'OUTBOX_HANDLER_DISABLED';
  end if;

  select * into receipt
  from private.record_event_handler_receipt(
    control.consumer_name,
    claimed_event.event_id,
    control.handler_name,
    control.handler_version,
    handler_result_version,
    coalesce(handler_result, '{}'::jsonb)
  );

  update private.outbox_events as event
  set
    status = 'processed',
    claimed_by = null,
    claimed_at = null,
    lease_expires_at = null,
    lease_token = null,
    processed_at = pg_catalog.clock_timestamp()
  where event.event_id = claimed_event.event_id
    and event.status = 'processing'
    and event.claimed_by = worker_identity
    and event.lease_token = current_lease_token
    and event.fencing_token = current_fencing_token;

  if not found then
    raise exception using errcode = 'P0001', message = 'OUTBOX_LEASE_STALE';
  end if;

  return query select receipt.stored_receipt_id, receipt.replayed;
end;
$$;

create function public.fail_outbox_event(
  target_event_id uuid,
  worker_identity text,
  current_lease_token uuid,
  current_fencing_token bigint,
  failure_class text,
  failure_code text,
  failure_message text
)
returns table (
  delivery_status text,
  next_eligible_at timestamptz,
  applied_backoff_seconds numeric
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  claimed_event private.outbox_events;
  control private.worker_handler_controls;
  safe_message text;
  terminal boolean;
  exponent integer;
  base_delay numeric;
  jitter_unit numeric;
  jitter_factor numeric;
  delay_seconds numeric;
  transition_time timestamptz := pg_catalog.clock_timestamp();
begin
  claimed_event := private.assert_current_outbox_lease(
    target_event_id, worker_identity, current_lease_token, current_fencing_token, false
  );

  select setting.* into control
  from private.worker_handler_controls as setting
  where setting.event_type = claimed_event.event_type
    and setting.event_version = claimed_event.event_version;

  if not found then
    raise exception using errcode = 'P0001', message = 'OUTBOX_HANDLER_UNAVAILABLE';
  end if;

  if failure_class not in ('retryable', 'non_retryable', 'poison_event', 'unsupported_event') then
    raise exception using errcode = '22023', message = 'INVALID_DELIVERY_FAILURE_CLASS';
  end if;
  if failure_code is null
     or pg_catalog.char_length(failure_code) not between 3 and 64
     or failure_code !~ '^[A-Z][A-Z0-9_]*$' then
    raise exception using errcode = '22023', message = 'INVALID_DELIVERY_FAILURE_CODE';
  end if;

  safe_message := private.sanitize_worker_error(failure_message);
  terminal := failure_class <> 'retryable'
    or claimed_event.attempt_count >= control.max_attempts * (claimed_event.requeue_count + 1);

  if terminal then
    update private.outbox_events as event
    set
      status = 'dead_letter',
      claimed_by = null,
      claimed_at = null,
      lease_expires_at = null,
      lease_token = null,
      dead_lettered_at = transition_time,
      last_failed_at = transition_time,
      last_error_class = case
        when failure_class = 'retryable' then 'attempts_exhausted'
        else failure_class
      end,
      last_error_code = case
        when failure_class = 'retryable' then 'DELIVERY_ATTEMPTS_EXHAUSTED'
        else failure_code
      end,
      last_error_message = safe_message
    where event.event_id = claimed_event.event_id
      and event.status = 'processing'
      and event.claimed_by = worker_identity
      and event.lease_token = current_lease_token
      and event.fencing_token = current_fencing_token;

    return query select 'dead_letter'::text, null::timestamptz, null::numeric;
    return;
  end if;

  exponent := greatest(
    0,
    claimed_event.attempt_count - (control.max_attempts * claimed_event.requeue_count) - 1
  );
  base_delay := least(
    control.backoff_max_seconds::numeric,
    control.backoff_base_seconds::numeric * pg_catalog.power(2::numeric, exponent)
  );
  jitter_unit := (
    (pg_catalog.hashtextextended(
      claimed_event.event_id::text || ':' || claimed_event.fencing_token::text,
      0
    ) & 2147483647)::numeric / 2147483647::numeric
  );
  jitter_factor := 1 + ((control.jitter_percent::numeric / 100) * ((2 * jitter_unit) - 1));
  delay_seconds := greatest(0, base_delay * jitter_factor);

  update private.outbox_events as event
  set
    status = 'pending',
    claimed_by = null,
    claimed_at = null,
    lease_expires_at = null,
    lease_token = null,
    next_attempt_at = transition_time + pg_catalog.make_interval(secs => delay_seconds::double precision),
    last_failed_at = transition_time,
    last_error_class = failure_class,
    last_error_code = failure_code,
    last_error_message = safe_message
  where event.event_id = claimed_event.event_id
    and event.status = 'processing'
    and event.claimed_by = worker_identity
    and event.lease_token = current_lease_token
    and event.fencing_token = current_fencing_token;

  return query select 'pending'::text, transition_time + pg_catalog.make_interval(secs => delay_seconds::double precision), delay_seconds;
end;
$$;

create function private.requeue_dead_letter(
  target_event_id uuid,
  technical_actor_ref text,
  requeue_reason text,
  requeue_correlation_id uuid
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  target_event private.outbox_events;
begin
  if technical_actor_ref is null
     or technical_actor_ref <> pg_catalog.btrim(technical_actor_ref)
     or pg_catalog.char_length(technical_actor_ref) not between 3 and 160
     or technical_actor_ref !~ '^[a-z][a-z0-9_.:-]*$' then
    raise exception using errcode = '22023', message = 'INVALID_REQUEUE_ACTOR';
  end if;
  if requeue_reason is null
     or requeue_reason <> pg_catalog.btrim(requeue_reason)
     or pg_catalog.char_length(requeue_reason) not between 8 and 500 then
    raise exception using errcode = '22023', message = 'INVALID_REQUEUE_REASON';
  end if;
  if requeue_correlation_id is null then
    raise exception using errcode = '22023', message = 'REQUEUE_CORRELATION_REQUIRED';
  end if;

  select event.* into target_event
  from private.outbox_events as event
  where event.event_id = target_event_id
  for update;

  if not found or target_event.status <> 'dead_letter' then
    raise exception using errcode = 'P0001', message = 'OUTBOX_REQUEUE_UNAVAILABLE';
  end if;
  if not exists (
    select 1 from private.worker_handler_controls as control
    where control.event_type = target_event.event_type
      and control.event_version = target_event.event_version
      and control.enabled
  ) then
    raise exception using errcode = 'P0001', message = 'OUTBOX_HANDLER_DISABLED';
  end if;

  perform private.append_audit(
    target_event.tenant_id,
    'technical',
    'infrastructure.outbox.requeued',
    'outbox_event',
    requeue_correlation_id,
    'worker',
    null,
    technical_actor_ref,
    target_event.event_id,
    pg_catalog.gen_random_uuid(),
    target_event.event_id,
    1,
    requeue_reason,
    pg_catalog.jsonb_build_object(
      'previous_attempt_count', target_event.attempt_count,
      'requeue_number', target_event.requeue_count + 1,
      'previous_failure_class', target_event.last_error_class,
      'previous_failure_code', target_event.last_error_code
    )
  );

  update private.outbox_events as event
  set
    status = 'pending',
    next_attempt_at = pg_catalog.clock_timestamp(),
    dead_lettered_at = null,
    requeue_count = event.requeue_count + 1
  where event.event_id = target_event.event_id;
end;
$$;

revoke all privileges on table private.worker_handler_controls
  from public, anon, authenticated, service_role, cw_worker;

revoke all on function private.assert_current_outbox_lease(uuid, text, uuid, bigint, boolean)
  from public, anon, authenticated, service_role, cw_worker;
revoke all on function private.sanitize_worker_error(text)
  from public, anon, authenticated, service_role, cw_worker;
revoke all on function private.requeue_dead_letter(uuid, text, text, uuid)
  from public, anon, authenticated, service_role, cw_worker;

revoke all on function public.claim_outbox_batch(text, integer)
  from public, anon, authenticated, service_role;
revoke all on function public.read_profile_created_origin(uuid, text, uuid, bigint)
  from public, anon, authenticated, service_role;
revoke all on function public.complete_outbox_event(uuid, text, uuid, bigint, integer, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.fail_outbox_event(uuid, text, uuid, bigint, text, text, text)
  from public, anon, authenticated, service_role;

grant usage on schema public to cw_worker;
grant execute on function public.claim_outbox_batch(text, integer) to cw_worker;
grant execute on function public.read_profile_created_origin(uuid, text, uuid, bigint) to cw_worker;
grant execute on function public.complete_outbox_event(uuid, text, uuid, bigint, integer, jsonb) to cw_worker;
grant execute on function public.fail_outbox_event(uuid, text, uuid, bigint, text, text, text) to cw_worker;

-- Migration/test administration can exercise the same narrow boundaries without
-- role membership; this does not expose tables or any client-facing role.
grant execute on function public.claim_outbox_batch(text, integer) to supabase_admin;
grant execute on function public.read_profile_created_origin(uuid, text, uuid, bigint) to supabase_admin;
grant execute on function public.complete_outbox_event(uuid, text, uuid, bigint, integer, jsonb) to supabase_admin;
grant execute on function public.fail_outbox_event(uuid, text, uuid, bigint, text, text, text) to supabase_admin;

alter table private.worker_handler_controls owner to postgres;
alter function private.assert_current_outbox_lease(uuid, text, uuid, bigint, boolean) owner to postgres;
alter function private.sanitize_worker_error(text) owner to postgres;
alter function public.claim_outbox_batch(text, integer) owner to postgres;
alter function public.read_profile_created_origin(uuid, text, uuid, bigint) owner to postgres;
alter function public.complete_outbox_event(uuid, text, uuid, bigint, integer, jsonb) owner to postgres;
alter function public.fail_outbox_event(uuid, text, uuid, bigint, text, text, text) owner to postgres;
alter function private.requeue_dead_letter(uuid, text, text, uuid) owner to postgres;

comment on table private.worker_handler_controls is
  'W3D kill switch and bounded delivery configuration for handlers compiled into the worker.';
comment on function public.claim_outbox_batch(text, integer) is
  'W3D technical claim boundary using ordered FOR UPDATE SKIP LOCKED, lease and monotonic fencing.';
comment on function public.complete_outbox_event(uuid, text, uuid, bigint, integer, jsonb) is
  'W3D fenced receipt plus acknowledgement boundary for the current worker lease.';
comment on function public.fail_outbox_event(uuid, text, uuid, bigint, text, text, text) is
  'W3D fenced retry/dead-letter transition with bounded exponential backoff and deterministic jitter.';
comment on function private.requeue_dead_letter(uuid, text, text, uuid) is
  'W3D controlled, reasoned and audited dead-letter reprocessing boundary.';
