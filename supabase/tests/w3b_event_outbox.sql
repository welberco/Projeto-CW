begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Physical Event/Outbox contract.
select has_table('private', 'outbox_events', 'W3B creates the private Transactional Outbox');
select has_pk('private', 'outbox_events', 'Outbox event identity is stable and primary');

select is(
  (
    select count(*)
    from information_schema.columns
    where table_schema = 'private'
      and table_name = 'outbox_events'
      and column_name in (
        'event_id', 'event_type', 'event_version', 'occurred_at',
        'scope_kind', 'tenant_id', 'aggregate_type', 'aggregate_id',
        'aggregate_version', 'actor_kind', 'actor_user_id', 'actor_ref',
        'source', 'command_id', 'correlation_id', 'causation_id',
        'payload', 'metadata', 'status', 'attempt_count', 'next_attempt_at'
      )
  ),
  21::bigint,
  'Outbox has the complete W3B event envelope and minimum inert processing state'
);

select is(
  (
    select owner_role.rolname
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace on namespace.oid = relation.relnamespace
    join pg_catalog.pg_roles as owner_role on owner_role.oid = relation.relowner
    where namespace.nspname = 'private' and relation.relname = 'outbox_events'
  ),
  'postgres',
  'Outbox has the controlled postgres owner'
);

select is(
  (
    select relation.relrowsecurity
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'private' and relation.relname = 'outbox_events'
  ),
  true,
  'Outbox has RLS enabled'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'private' and tablename = 'outbox_events'
  ),
  0::bigint,
  'Outbox is fail-closed with no client policy'
);

select is(
  (
    select count(*)
    from information_schema.table_privileges
    where table_schema = 'private'
      and table_name = 'outbox_events'
      and grantee in ('PUBLIC', 'anon', 'authenticated', 'service_role')
  ),
  0::bigint,
  'Outbox grants no direct privilege to client or service roles'
);

select ok(
  exists (
    select 1 from pg_catalog.pg_indexes
    where schemaname = 'private'
      and tablename = 'outbox_events'
      and indexname = 'outbox_events_pending_claim_idx'
      and indexdef like '%WHERE (status = ''pending''::text)%'
  ),
  'Outbox has the planned pending ordering index without implementing claim'
);

select ok(
  exists (
    select 1 from pg_catalog.pg_indexes
    where schemaname = 'private'
      and tablename = 'outbox_events'
      and indexname = 'outbox_events_operability_idx'
  ),
  'Outbox has the minimum operability index'
);

select has_function(
  'private', 'enqueue_event',
  array['uuid', 'text', 'text', 'text', 'uuid', 'uuid', 'text', 'uuid',
        'integer', 'bigint', 'uuid', 'text', 'uuid', 'jsonb', 'jsonb'],
  'the private W3B enqueue boundary exists'
);

select is(
  (
    select count(*)
    from information_schema.routine_privileges
    where specific_schema = 'private'
      and routine_name in (
        'enqueue_event', 'jsonb_has_forbidden_event_keys', 'protect_outbox_event'
      )
      and grantee in ('PUBLIC', 'anon', 'authenticated', 'service_role')
  ),
  0::bigint,
  'all W3B private helpers are non-callable by clients and service_role'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'private'
      and procedure.proname in (
        'enqueue_event', 'jsonb_has_forbidden_event_keys', 'protect_outbox_event'
      )
      and procedure.prosecdef
  ),
  0::bigint,
  'W3B introduces no SECURITY DEFINER helper'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'private'
      and procedure.proname in (
        'enqueue_event', 'jsonb_has_forbidden_event_keys', 'protect_outbox_event'
      )
      and not exists (
        select 1
        from pg_catalog.unnest(coalesce(procedure.proconfig, array[]::text[])) as setting(value)
        where pg_catalog.split_part(setting.value, '=', 1) = 'search_path'
          and pg_catalog.replace(pg_catalog.split_part(setting.value, '=', 2), '"', '') = ''
      )
  ),
  0::bigint,
  'every W3B helper fixes an empty search_path'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
    join pg_catalog.pg_roles as owner_role on owner_role.oid = procedure.proowner
    where namespace.nspname = 'private'
      and procedure.proname in (
        'enqueue_event', 'jsonb_has_forbidden_event_keys', 'protect_outbox_event'
      )
      and owner_role.rolname <> 'postgres'
  ),
  0::bigint,
  'every W3B helper has the controlled postgres owner'
);

select is(
  (
    select count(*)
    from information_schema.columns
    where table_schema = 'private'
      and table_name = 'outbox_events'
      and column_name in (
        'event_id', 'event_type', 'event_version', 'occurred_at',
        'scope_kind', 'tenant_id', 'aggregate_type', 'aggregate_id',
        'aggregate_version', 'actor_kind', 'actor_user_id', 'actor_ref',
        'source', 'command_id', 'correlation_id', 'causation_id',
        'payload', 'metadata'
      )
  ),
  18::bigint,
  'all W3B persisted Event fact columns remain present after delivery evolution'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'private'
      and relation.relname = 'outbox_events'
  ),
  1::bigint,
  'the W3B outbox remains the single persisted event record'
);

-- Two tenant actors prove authoritative tenant binding.
insert into auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
values
  ('1b000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'w3b-manager-a@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp()),
  ('1b000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'w3b-manager-b@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp());

create temporary table w3b_tenant_a as
select * from public.bootstrap_initial_tenant(
  '1b000000-0000-4000-8000-000000000001',
  'W3B Tenant A',
  '7b000000-0000-4000-8000-000000000001'
);
grant select on table w3b_tenant_a to authenticated;

insert into public.tenants (id, tenant_ref, display_name, status, created_by)
values (
  '2b000000-0000-4000-8000-000000000002',
  '3b000000-0000-4000-8000-000000000002',
  'W3B Tenant B', 'active',
  '1b000000-0000-4000-8000-000000000002'
);

select * from private.provision_tenant_authorization(
  '2b000000-0000-4000-8000-000000000002', null,
  '1b000000-0000-4000-8000-000000000002',
  '7b000000-0000-4000-8000-000000000002'
);

insert into public.tenant_memberships (
  tenant_id, user_id, status, joined_at, created_by,
  profile_id, profile_assigned_at, profile_assigned_by
)
select
  '2b000000-0000-4000-8000-000000000002',
  '1b000000-0000-4000-8000-000000000002',
  'active', statement_timestamp(), '1b000000-0000-4000-8000-000000000002',
  profile.id, statement_timestamp(), '1b000000-0000-4000-8000-000000000002'
from public.tenant_profiles as profile
where profile.tenant_id = '2b000000-0000-4000-8000-000000000002'
  and profile.template_key = 'manager';

create temporary table w3b_refs (
  key text primary key,
  id uuid not null
);

insert into w3b_refs (key, id)
values (
  'event_a',
  private.enqueue_event(
    (select tenant_id from w3b_tenant_a),
    'authorization.profile.created',
    'application_user',
    'user_command',
    '4b000000-0000-4000-8000-000000000001',
    '5b000000-0000-4000-8000-000000000001',
    'tenant_profile',
    '6b000000-0000-4000-8000-000000000001',
    1,
    1,
    '1b000000-0000-4000-8000-000000000001',
    null,
    null,
    '{"profile_version":1}'::jsonb,
    '{"release":"w3b-test"}'::jsonb
  )
);

select is(
  (select scope_kind from private.outbox_events where event_id = (select id from w3b_refs where key = 'event_a')),
  'tenant',
  'W3B persists only the tenant event scope'
);
select is(
  (select tenant_id from private.outbox_events where event_id = (select id from w3b_refs where key = 'event_a')),
  (select tenant_id from w3b_tenant_a),
  'tenant is authoritative in the envelope rather than payload'
);
select is(
  (select event_type from private.outbox_events where event_id = (select id from w3b_refs where key = 'event_a')),
  'authorization.profile.created',
  'event type follows the three-segment past-tense contract'
);
select is(
  (select event_version from private.outbox_events where event_id = (select id from w3b_refs where key = 'event_a')),
  1,
  'event contract version is persisted'
);
select is(
  (select aggregate_id from private.outbox_events where event_id = (select id from w3b_refs where key = 'event_a')),
  '6b000000-0000-4000-8000-000000000001'::uuid,
  'aggregate identity is carried outside the payload'
);
select is(
  (select actor_user_id from private.outbox_events where event_id = (select id from w3b_refs where key = 'event_a')),
  '1b000000-0000-4000-8000-000000000001'::uuid,
  'human actor identity is persisted explicitly'
);
select is(
  (select command_id from private.outbox_events where event_id = (select id from w3b_refs where key = 'event_a')),
  '4b000000-0000-4000-8000-000000000001'::uuid,
  'command identity is distinct and persisted'
);
select is(
  (select correlation_id from private.outbox_events where event_id = (select id from w3b_refs where key = 'event_a')),
  '5b000000-0000-4000-8000-000000000001'::uuid,
  'correlation identity is persisted'
);
select is(
  (select status from private.outbox_events where event_id = (select id from w3b_refs where key = 'event_a')),
  'pending',
  'new events enter the inert pending state'
);
select is(
  (select attempt_count from private.outbox_events where event_id = (select id from w3b_refs where key = 'event_a')),
  0,
  'W3B does not fabricate processing attempts'
);
select ok(
  (select occurred_at <= statement_timestamp() from private.outbox_events where event_id = (select id from w3b_refs where key = 'event_a')),
  'event time is assigned by the database'
);

select lives_ok(
  $$ select private.enqueue_event(
    (select tenant_id from w3b_tenant_a), 'authorization.profile.reconciled',
    'technical', 'integration',
    '4b000000-0000-4000-8000-000000000002',
    '5b000000-0000-4000-8000-000000000002',
    'tenant_profile', pg_catalog.gen_random_uuid(), 1, null,
    null, 'integration:authorization-sync',
    '8b000000-0000-4000-8000-000000000001',
    '{"result":"reconciled"}'::jsonb, '{}'::jsonb
  ) $$,
  'technical actor and causation are represented without fabricating a user'
);

select is(
  (
    select causation_id from private.outbox_events
    where command_id = '4b000000-0000-4000-8000-000000000002'
  ),
  '8b000000-0000-4000-8000-000000000001'::uuid,
  'causation identifies the immediate cause independently from correlation'
);
select is(
  (
    select actor_ref from private.outbox_events
    where command_id = '4b000000-0000-4000-8000-000000000002'
  ),
  'integration:authorization-sync',
  'technical actor provenance is persisted explicitly'
);
select is(
  (
    select source from private.outbox_events
    where command_id = '4b000000-0000-4000-8000-000000000002'
  ),
  'integration',
  'controlled source is persisted outside payload and metadata'
);

select throws_ok(
  $$ select private.enqueue_event(
    null, 'authorization.profile.created', 'technical', 'system',
    pg_catalog.gen_random_uuid(), pg_catalog.gen_random_uuid(),
    null, null, 1, null, null, 'system:test', null, '{}'::jsonb, '{}'::jsonb
  ) $$,
  '22023', 'EVENT_TENANT_REQUIRED',
  'tenant scope requires an authoritative tenant'
);

select throws_ok(
  $$ select private.enqueue_event(
    (select tenant_id from w3b_tenant_a), 'authorization.profile.created',
    'technical', 'system', null, pg_catalog.gen_random_uuid(),
    null, null, 1, null, null, 'system:test', null, '{}'::jsonb, '{}'::jsonb
  ) $$,
  '23502', null,
  'event envelope requires command identity'
);

select throws_ok(
  $$ select private.enqueue_event(
    (select tenant_id from w3b_tenant_a), 'authorization.profile.created',
    'technical', 'system', pg_catalog.gen_random_uuid(), null,
    null, null, 1, null, null, 'system:test', null, '{}'::jsonb, '{}'::jsonb
  ) $$,
  '23502', null,
  'event envelope requires correlation identity'
);

select throws_ok(
  $$ select private.enqueue_event(
    (select tenant_id from w3b_tenant_a), 'authorization.profile.created',
    'technical', 'system', pg_catalog.gen_random_uuid(), pg_catalog.gen_random_uuid(),
    null, null, 1, null, null, null, null, '{}'::jsonb, '{}'::jsonb
  ) $$,
  '22023', 'INVALID_EVENT_ACTOR',
  'technical event actor requires stable provenance'
);

select throws_ok(
  $$ select private.enqueue_event(
    (select tenant_id from w3b_tenant_a), 'authorization.profile.created',
    'application_user', 'user_command', pg_catalog.gen_random_uuid(), pg_catalog.gen_random_uuid(),
    'tenant_profile', pg_catalog.gen_random_uuid(), 1, 1,
    '1b000000-0000-4000-8000-000000000002', null, null, '{}'::jsonb, '{}'::jsonb
  ) $$,
  'P0001', 'EVENT_TARGET_UNAVAILABLE',
  'an actor from Tenant B cannot be attached to a Tenant A event'
);

select throws_ok(
  $$ select private.enqueue_event(
    (select tenant_id from w3b_tenant_a), 'authorization.profile.created',
    'platform', 'platform', pg_catalog.gen_random_uuid(), pg_catalog.gen_random_uuid(),
    null, null, 1, null, null, 'platform:operator', null, '{}'::jsonb, '{}'::jsonb
  ) $$,
  '22023', 'INVALID_EVENT_ACTOR',
  'platform event authority remains deferred'
);

select throws_ok(
  $$ select private.enqueue_event(
    (select tenant_id from w3b_tenant_a), 'authorization.profile',
    'technical', 'system', pg_catalog.gen_random_uuid(), pg_catalog.gen_random_uuid(),
    null, null, 1, null, null, 'system:test', null, '{}'::jsonb, '{}'::jsonb
  ) $$,
  '23514', null,
  'event type outside the official three-segment convention is rejected'
);

select throws_ok(
  $$ select private.enqueue_event(
    (select tenant_id from w3b_tenant_a), 'authorization.profile.created',
    'technical', 'system', pg_catalog.gen_random_uuid(), pg_catalog.gen_random_uuid(),
    null, null, 0, null, null, 'system:test', null, '{}'::jsonb, '{}'::jsonb
  ) $$,
  '23514', null,
  'non-positive event versions are rejected'
);

select throws_ok(
  $$ select private.enqueue_event(
    (select tenant_id from w3b_tenant_a), 'authorization.profile.created',
    'technical', 'browser', pg_catalog.gen_random_uuid(), pg_catalog.gen_random_uuid(),
    null, null, 1, null, null, 'system:test', null, '{}'::jsonb, '{}'::jsonb
  ) $$,
  '23514', null,
  'uncontrolled source values are rejected'
);

select throws_ok(
  $$ select private.enqueue_event(
    (select tenant_id from w3b_tenant_a), 'authorization.profile.created',
    'technical', 'system', pg_catalog.gen_random_uuid(), pg_catalog.gen_random_uuid(),
    'tenant_profile', null, 1, null, null, 'system:test', null, '{}'::jsonb, '{}'::jsonb
  ) $$,
  '23514', null,
  'partial aggregate identity is rejected'
);

select throws_ok(
  $$ select private.enqueue_event(
    (select tenant_id from w3b_tenant_a), 'authorization.profile.created',
    'technical', 'system', pg_catalog.gen_random_uuid(), pg_catalog.gen_random_uuid(),
    null, null, 1, null, null, 'system:test', null, '[1]'::jsonb, '{}'::jsonb
  ) $$,
  '23514', null,
  'event payload must be a JSON object'
);

select throws_ok(
  $$ select private.enqueue_event(
    (select tenant_id from w3b_tenant_a), 'authorization.profile.created',
    'technical', 'system', pg_catalog.gen_random_uuid(), pg_catalog.gen_random_uuid(),
    null, null, 1, null, null, 'system:test', null, '{}'::jsonb, '[1]'::jsonb
  ) $$,
  '23514', null,
  'event metadata must be a JSON object'
);

select throws_ok(
  $$ select private.enqueue_event(
    (select tenant_id from w3b_tenant_a), 'authorization.profile.created',
    'technical', 'system', pg_catalog.gen_random_uuid(), pg_catalog.gen_random_uuid(),
    null, null, 1, null, null, 'system:test', null,
    '{"safe":{"access_token":"secret"}}'::jsonb, '{}'::jsonb
  ) $$,
  '23514', null,
  'event payload recursively rejects secret-bearing keys'
);

select throws_ok(
  $$ select private.enqueue_event(
    (select tenant_id from w3b_tenant_a), 'authorization.profile.created',
    'technical', 'system', pg_catalog.gen_random_uuid(), pg_catalog.gen_random_uuid(),
    null, null, 1, null, null, 'system:test', null,
    '{"tenant_id":"2b000000-0000-4000-8000-000000000002"}'::jsonb, '{}'::jsonb
  ) $$,
  '23514', null,
  'payload cannot override the authoritative tenant envelope'
);

select throws_ok(
  $$ select private.enqueue_event(
    (select tenant_id from w3b_tenant_a), 'authorization.profile.created',
    'technical', 'system', pg_catalog.gen_random_uuid(), pg_catalog.gen_random_uuid(),
    null, null, 1, null, null, 'system:test', null,
    '{}'::jsonb, '{"handler_name":"forged"}'::jsonb
  ) $$,
  '23514', null,
  'metadata cannot select a handler'
);

select throws_ok(
  $$ select private.enqueue_event(
    (select tenant_id from w3b_tenant_a), 'authorization.profile.created',
    'technical', 'system', pg_catalog.gen_random_uuid(), pg_catalog.gen_random_uuid(),
    null, null, 1, null, null, 'system:test', null,
    '{"old_row":{"id":"dump"}}'::jsonb, '{}'::jsonb
  ) $$,
  '23514', null,
  'row dumps are rejected structurally'
);

select lives_ok(
  $$ select private.enqueue_event(
    (select tenant_id from w3b_tenant_a), 'authorization.profile.checked',
    'technical', 'system', pg_catalog.gen_random_uuid(), pg_catalog.gen_random_uuid(),
    null, null, 1, null, null, 'system:test', null,
    pg_catalog.jsonb_build_object('value', pg_catalog.repeat('a', 64000)),
    '{"release":"w3b"}'::jsonb
  ) $$,
  'payload plus metadata below the combined 64 KiB limit is accepted'
);

select throws_ok(
  $$ select private.enqueue_event(
    (select tenant_id from w3b_tenant_a), 'authorization.profile.checked',
    'technical', 'system', pg_catalog.gen_random_uuid(), pg_catalog.gen_random_uuid(),
    null, null, 1, null, null, 'system:test', null,
    pg_catalog.jsonb_build_object('value', pg_catalog.repeat('a', 65536)),
    '{}'::jsonb
  ) $$,
  '23514', null,
  'payload plus metadata above the combined 64 KiB limit is rejected'
);

-- Event facts are immutable while technical scheduling remains structurally separate.
select lives_ok(
  $$ update private.outbox_events
     set next_attempt_at = statement_timestamp()
     where event_id = (select id from w3b_refs where key = 'event_a') $$,
  'a technical scheduling field may change through the owner path'
);

select throws_ok(
  $$ update private.outbox_events
     set payload = '{"profile_version":2}'::jsonb
     where event_id = (select id from w3b_refs where key = 'event_a') $$,
  '55000', 'outbox event fact is immutable',
  'event payload cannot be rewritten'
);

select throws_ok(
  $$ update private.outbox_events
     set tenant_id = '2b000000-0000-4000-8000-000000000002'
     where event_id = (select id from w3b_refs where key = 'event_a') $$,
  '55000', 'outbox event fact is immutable',
  'event tenant cannot be rewritten'
);

select throws_ok(
  $$ delete from private.outbox_events
     where event_id = (select id from w3b_refs where key = 'event_a') $$,
  '55000', 'outbox event cannot be deleted',
  'event rows cannot be deleted'
);

select throws_like(
  $$ truncate private.outbox_events $$,
  '%cannot truncate a table referenced in a foreign key constraint%',
  'outbox events remain non-truncatable after W3C receipt integrity is added'
);

-- One real W2 command proves Domain mutation + Audit + Event in one transaction.
set local "request.jwt.claim.sub" = '1b000000-0000-4000-8000-000000000001';
set local role authenticated;

select lives_ok(
  $$ select * from public.create_tenant_profile(
    'W3B Integrated Profile', 'prove transactional outbox',
    '5b000000-0000-4000-8000-000000000030'
  ) $$,
  'authorized profile creation writes its required transactional event'
);

reset role;

select is(
  (
    select count(*) from public.tenant_profiles
    where tenant_id = (select tenant_id from w3b_tenant_a)
      and name = 'W3B Integrated Profile'
  ),
  1::bigint,
  'the real command persists its domain mutation'
);
select is(
  (
    select count(*) from public.audit_events
    where correlation_id = '5b000000-0000-4000-8000-000000000030'
      and event_type = 'authorization.profile_created'
  ),
  1::bigint,
  'the real command persists required Audit separately'
);
select is(
  (
    select count(*) from private.outbox_events
    where correlation_id = '5b000000-0000-4000-8000-000000000030'
      and event_type = 'authorization.profile.created'
  ),
  1::bigint,
  'the real command persists one required Event/Outbox record'
);
select is(
  (
    select audit.command_id
    from public.audit_events as audit
    where audit.correlation_id = '5b000000-0000-4000-8000-000000000030'
  ),
  (
    select event.command_id
    from private.outbox_events as event
    where event.correlation_id = '5b000000-0000-4000-8000-000000000030'
  ),
  'Audit and Event share the same trusted command identity'
);
select is(
  (
    select count(*) from public.history_entries
    where correlation_id = '5b000000-0000-4000-8000-000000000030'
  ),
  0::bigint,
  'History is explicitly N/A for the authorization profile creation effect matrix'
);

-- Failure injection proves a mandatory Event failure rolls back Domain and Audit.
create function pg_temp.fail_w3b_outbox_insert()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.correlation_id = '5b000000-0000-4000-8000-000000000031'::uuid then
    raise exception using
      errcode = 'P0001',
      message = 'EVENT_PERSISTENCE_INJECTED_FAILURE';
  end if;
  return new;
end;
$$;

create trigger w3b_fail_outbox_insert
before insert on private.outbox_events
for each row
execute function pg_temp.fail_w3b_outbox_insert();

set local role authenticated;
select throws_ok(
  $$ select * from public.create_tenant_profile(
    'W3B Must Roll Back', 'inject event failure',
    '5b000000-0000-4000-8000-000000000031'
  ) $$,
  'P0001', 'EVENT_PERSISTENCE_INJECTED_FAILURE',
  'failure of the required Event aborts the real command'
);
reset role;

select is(
  (
    select count(*) from public.tenant_profiles
    where tenant_id = (select tenant_id from w3b_tenant_a)
      and name = 'W3B Must Roll Back'
  ),
  0::bigint,
  'domain mutation rolls back when mandatory Event persistence fails'
);
select is(
  (
    select count(*) from public.audit_events
    where correlation_id = '5b000000-0000-4000-8000-000000000031'
  ),
  0::bigint,
  'Audit rolls back with the failed Event'
);
select is(
  (
    select count(*) from private.outbox_events
    where correlation_id = '5b000000-0000-4000-8000-000000000031'
  ),
  0::bigint,
  'failed Event leaves no partial Outbox row'
);

-- A failing domain mutation never produces Audit or Event for its command.
set local role authenticated;
select throws_ok(
  $$ select * from public.create_tenant_profile(
    'W3B Integrated Profile', 'duplicate mutation must fail',
    '5b000000-0000-4000-8000-000000000032'
  ) $$,
  'P0001', 'AUTHORIZATION_OPERATION_UNAVAILABLE',
  'failed domain mutation aborts before Event persistence'
);
reset role;

select is(
  (
    select count(*) from public.audit_events
    where correlation_id = '5b000000-0000-4000-8000-000000000032'
  ),
  0::bigint,
  'failed domain mutation leaves no Audit side effect'
);
select is(
  (
    select count(*) from private.outbox_events
    where correlation_id = '5b000000-0000-4000-8000-000000000032'
  ),
  0::bigint,
  'failed domain mutation leaves no Event side effect'
);

-- Runtime access checks for all bypass-relevant client/service roles.
set local role authenticated;
select throws_ok(
  $$ select * from private.outbox_events $$,
  '42501', null,
  'authenticated cannot read the private Outbox'
);
select throws_ok(
  $$ select private.enqueue_event(
    '2b000000-0000-4000-8000-000000000002', 'authorization.profile.created',
    'application_user', 'user_command', pg_catalog.gen_random_uuid(), pg_catalog.gen_random_uuid(),
    null, null, 1, null, '1b000000-0000-4000-8000-000000000001', null,
    null, '{}'::jsonb, '{}'::jsonb
  ) $$,
  '42501', null,
  'authenticated cannot invoke the private enqueue boundary'
);
reset role;

set local role anon;
select throws_ok(
  $$ select * from private.outbox_events $$,
  '42501', null,
  'anon cannot read the private Outbox'
);
reset role;

set local role service_role;
select throws_ok(
  $$ select * from private.outbox_events $$,
  '42501', null,
  'service_role bypass capability receives no Outbox table grant'
);
select throws_ok(
  $$ select private.enqueue_event(
    '2b000000-0000-4000-8000-000000000002', 'authorization.profile.created',
    'technical', 'system', pg_catalog.gen_random_uuid(), pg_catalog.gen_random_uuid(),
    null, null, 1, null, null, 'system:forged', null, '{}'::jsonb, '{}'::jsonb
  ) $$,
  '42501', null,
  'service_role receives no enqueue shortcut'
);
reset role;

select * from finish();
rollback;
