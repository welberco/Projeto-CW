begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Physical contract: Audit is evolved in place and History is a distinct envelope.
select has_table('public', 'audit_events', 'W3A preserves the official Audit table');
select has_table('public', 'history_entries', 'W3A creates the functional History envelope');
select has_pk('public', 'history_entries', 'History has a stable internal identity');

select is(
  (
    select count(*)
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'audit_events'
      and column_name in (
        'event_version', 'command_id', 'causation_id', 'source',
        'actor_ref', 'reason', 'authority_kind'
      )
  ),
  7::bigint,
  'Audit has all W3A correlation, actor and source fields'
);

select is(
  (
    select count(*)
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'history_entries'
      and column_name in (
        'id', 'tenant_id', 'aggregate_type', 'aggregate_id',
        'aggregate_version', 'human_code', 'history_type', 'history_version',
        'occurred_at', 'actor_kind', 'actor_user_id', 'actor_ref',
        'command_name', 'command_id', 'correlation_id', 'causation_id',
        'source', 'payload'
      )
  ),
  18::bigint,
  'History has the complete minimum W3A envelope'
);

select is(
  (
    select owner_role.rolname
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace on namespace.oid = relation.relnamespace
    join pg_catalog.pg_roles as owner_role on owner_role.oid = relation.relowner
    where namespace.nspname = 'public' and relation.relname = 'history_entries'
  ),
  'postgres',
  'History has a controlled owner'
);

select is(
  (
    select relation.relrowsecurity
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public' and relation.relname = 'history_entries'
  ),
  true,
  'History has RLS enabled'
);

select is(
  (select count(*) from pg_catalog.pg_policies where schemaname = 'public' and tablename = 'history_entries'),
  0::bigint,
  'History is closed and has no direct client policy'
);

select is(
  (
    select count(*)
    from information_schema.table_privileges
    where table_schema = 'public'
      and table_name = 'history_entries'
      and grantee in ('PUBLIC', 'anon', 'authenticated', 'service_role')
  ),
  0::bigint,
  'History grants no direct privileges to client or service roles'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_indexes
    where schemaname = 'public'
      and tablename = 'history_entries'
      and indexname = 'history_entries_tenant_aggregate_timeline_idx'
  ),
  'History has the tenant aggregate timeline index'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_indexes
    where schemaname = 'public'
      and tablename = 'history_entries'
      and indexname = 'history_entries_command_idx'
  ),
  'History supports command-level trace correlation'
);

select has_function(
  'private', 'append_audit',
  array['uuid', 'text', 'text', 'text', 'uuid', 'text', 'uuid', 'text',
        'uuid', 'uuid', 'uuid', 'integer', 'text', 'jsonb'],
  'the minimum private Audit writer exists'
);
select has_function(
  'private', 'append_history',
  array['uuid', 'text', 'uuid', 'text', 'text', 'text', 'uuid', 'uuid',
        'text', 'bigint', 'text', 'integer', 'uuid', 'text', 'uuid', 'jsonb'],
  'the minimum private History writer exists'
);

select is(
  (
    select count(*)
    from information_schema.routine_privileges
    where specific_schema = 'private'
      and routine_name in (
        'append_audit', 'append_history', 'jsonb_has_forbidden_history_keys',
        'prepare_audit_event', 'reject_history_mutation'
      )
      and grantee in ('PUBLIC', 'anon', 'authenticated', 'service_role')
  ),
  0::bigint,
  'all W3A private helpers are non-callable by clients and service_role'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'private'
      and procedure.proname in (
        'append_audit', 'append_history', 'jsonb_has_forbidden_history_keys',
        'prepare_audit_event', 'reject_history_mutation'
      )
      and procedure.prosecdef
  ),
  0::bigint,
  'W3A introduces no new SECURITY DEFINER helper'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'private'
      and procedure.proname in (
        'append_audit', 'append_history', 'jsonb_has_forbidden_history_keys',
        'prepare_audit_event', 'reject_history_mutation'
      )
      and not exists (
        select 1
        from pg_catalog.unnest(coalesce(procedure.proconfig, array[]::text[])) as setting(value)
        where pg_catalog.split_part(setting.value, '=', 1) = 'search_path'
          and pg_catalog.replace(pg_catalog.split_part(setting.value, '=', 2), '"', '') = ''
      )
  ),
  0::bigint,
  'every W3A helper fixes an empty search_path'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
    join pg_catalog.pg_roles as owner_role on owner_role.oid = procedure.proowner
    where namespace.nspname = 'private'
      and procedure.proname in (
        'append_audit', 'append_history', 'jsonb_has_forbidden_history_keys',
        'prepare_audit_event', 'reject_history_mutation'
      )
      and owner_role.rolname <> 'postgres'
  ),
  0::bigint,
  'every W3A helper has the controlled postgres owner'
);

-- Two tenants and actors exercise tenant binding without creating a domain model.
insert into auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
values
  ('1a000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'w3a-actor-a@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp()),
  ('1a000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'w3a-actor-b@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp());

insert into public.tenants (id, tenant_ref, display_name, status, created_by)
values
  ('2a000000-0000-4000-8000-000000000001', '3a000000-0000-4000-8000-000000000001', 'W3A Tenant A', 'active', '1a000000-0000-4000-8000-000000000001'),
  ('2a000000-0000-4000-8000-000000000002', '3a000000-0000-4000-8000-000000000002', 'W3A Tenant B', 'active', '1a000000-0000-4000-8000-000000000002');

select * from private.provision_tenant_authorization(
  '2a000000-0000-4000-8000-000000000001', null,
  '1a000000-0000-4000-8000-000000000001',
  '9a000000-0000-4000-8000-000000000001'
);
select * from private.provision_tenant_authorization(
  '2a000000-0000-4000-8000-000000000002', null,
  '1a000000-0000-4000-8000-000000000002',
  '9a000000-0000-4000-8000-000000000002'
);

insert into public.tenant_memberships (
  id, tenant_id, user_id, status, joined_at, created_by,
  profile_id, profile_assigned_at, profile_assigned_by
)
select
  target.membership_id, target.tenant_id, target.user_id, 'active',
  statement_timestamp(), target.user_id, profile.id,
  statement_timestamp(), target.user_id
from (
  values
    ('4a000000-0000-4000-8000-000000000001'::uuid, '2a000000-0000-4000-8000-000000000001'::uuid, '1a000000-0000-4000-8000-000000000001'::uuid),
    ('4a000000-0000-4000-8000-000000000002'::uuid, '2a000000-0000-4000-8000-000000000002'::uuid, '1a000000-0000-4000-8000-000000000002'::uuid)
) as target(membership_id, tenant_id, user_id)
join public.tenant_profiles as profile
  on profile.tenant_id = target.tenant_id and profile.template_key = 'manager';

create temporary table w3a_refs (
  key text primary key,
  id uuid not null
);

insert into w3a_refs (key, id)
values
  ('aggregate_a', '5a000000-0000-4000-8000-000000000001'),
  ('history_a', private.append_history(
    '2a000000-0000-4000-8000-000000000001',
    'probe_record',
    '5a000000-0000-4000-8000-000000000001',
    'probe.record.created',
    'application_user',
    'probe.record.create',
    '6a000000-0000-4000-8000-000000000001',
    '7a000000-0000-4000-8000-000000000001',
    'user_command',
    1,
    'REC-001',
    1,
    '1a000000-0000-4000-8000-000000000001',
    null,
    null,
    jsonb_build_object('from_status', null, 'to_status', 'created')
  ));

select is(
  (select tenant_id from public.history_entries where id = (select id from w3a_refs where key = 'history_a')),
  '2a000000-0000-4000-8000-000000000001'::uuid,
  'History persists the authoritative tenant outside the payload'
);
select is(
  (select actor_user_id from public.history_entries where id = (select id from w3a_refs where key = 'history_a')),
  '1a000000-0000-4000-8000-000000000001'::uuid,
  'History persists the human actor identity'
);
select is(
  (select actor_kind from public.history_entries where id = (select id from w3a_refs where key = 'history_a')),
  'application_user',
  'History distinguishes a human application actor'
);
select is(
  (select command_id from public.history_entries where id = (select id from w3a_refs where key = 'history_a')),
  '6a000000-0000-4000-8000-000000000001'::uuid,
  'History persists command identity'
);
select is(
  (select correlation_id from public.history_entries where id = (select id from w3a_refs where key = 'history_a')),
  '7a000000-0000-4000-8000-000000000001'::uuid,
  'History persists correlation identity'
);
select is(
  (select aggregate_version from public.history_entries where id = (select id from w3a_refs where key = 'history_a')),
  1::bigint,
  'History supports per-aggregate ordering without global ordering'
);
select is(
  (select payload ->> 'to_status' from public.history_entries where id = (select id from w3a_refs where key = 'history_a')),
  'created',
  'History stores a semantic diff instead of a row dump'
);
select ok(
  (select occurred_at <= statement_timestamp() from public.history_entries where id = (select id from w3a_refs where key = 'history_a')),
  'History time is assigned by the database'
);

select lives_ok(
  $$ select private.append_history(
    '2a000000-0000-4000-8000-000000000001', 'probe_record',
    '5a000000-0000-4000-8000-000000000002', 'probe.record.reconciled',
    'technical', 'probe.record.reconcile',
    '6a000000-0000-4000-8000-000000000002',
    '7a000000-0000-4000-8000-000000000002', 'worker',
    2, null, 1, null, 'worker:history-reconciler',
    '8a000000-0000-4000-8000-000000000001',
    '{"result":"reconciled"}'::jsonb
  ) $$,
  'History represents a technical actor without pretending it is human'
);

select throws_ok(
  $$ select private.append_history(
    '2a000000-0000-4000-8000-000000000001', 'probe_record',
    '5a000000-0000-4000-8000-000000000003', 'probe.record.created',
    'application_user', 'probe.record.create',
    pg_catalog.gen_random_uuid(), pg_catalog.gen_random_uuid(), 'user_command',
    1, null, 1, '1a000000-0000-4000-8000-000000000002', null, null, '{}'::jsonb
  ) $$,
  'P0001', 'HISTORY_TARGET_UNAVAILABLE',
  'an actor from Tenant B cannot be recorded as the human actor in Tenant A'
);

select throws_ok(
  $$ select private.append_history(
    '2a000000-0000-4000-8000-000000000001', 'probe_record',
    pg_catalog.gen_random_uuid(), 'probe.record.created',
    'application_user', 'probe.record.create',
    pg_catalog.gen_random_uuid(), pg_catalog.gen_random_uuid(), 'user_command',
    1, null, 1, null, null, null, '{}'::jsonb
  ) $$,
  '22023', 'INVALID_HISTORY_ACTOR',
  'a browser-style payload cannot omit the authoritative human actor'
);

select throws_ok(
  $$ select private.append_history(
    '2a000000-0000-4000-8000-000000000001', 'probe_record',
    pg_catalog.gen_random_uuid(), 'probe.record.created',
    'technical', 'probe.record.create',
    pg_catalog.gen_random_uuid(), pg_catalog.gen_random_uuid(), 'worker',
    1, null, 1, '1a000000-0000-4000-8000-000000000001', 'worker:forged', null, '{}'::jsonb
  ) $$,
  '22023', 'INVALID_HISTORY_ACTOR',
  'a technical actor cannot also claim a human identity'
);

select throws_ok(
  $$ select private.append_history(
    '2a000000-0000-4000-8000-000000000001', 'probe_record',
    pg_catalog.gen_random_uuid(), 'probe.record',
    'technical', 'probe.record.create',
    pg_catalog.gen_random_uuid(), pg_catalog.gen_random_uuid(), 'worker',
    1, null, 1, null, 'worker:history', null, '{}'::jsonb
  ) $$,
  '23514', null,
  'History rejects event names outside the three-segment convention'
);

select throws_ok(
  $$ select private.append_history(
    '2a000000-0000-4000-8000-000000000001', 'probe_record',
    pg_catalog.gen_random_uuid(), 'probe.record.created',
    'technical', 'create',
    pg_catalog.gen_random_uuid(), pg_catalog.gen_random_uuid(), 'worker',
    1, null, 1, null, 'worker:history', null, '{}'::jsonb
  ) $$,
  '23514', null,
  'History requires a namespaced source command'
);

select throws_ok(
  $$ select private.append_history(
    '2a000000-0000-4000-8000-000000000001', 'probe_record',
    pg_catalog.gen_random_uuid(), 'probe.record.created',
    'technical', 'probe.record.create',
    pg_catalog.gen_random_uuid(), pg_catalog.gen_random_uuid(), 'browser',
    1, null, 1, null, 'worker:history', null, '{}'::jsonb
  ) $$,
  '23514', null,
  'History rejects an uncontrolled source taxonomy'
);

select throws_ok(
  $$ select private.append_history(
    '2a000000-0000-4000-8000-000000000001', 'probe_record',
    pg_catalog.gen_random_uuid(), 'probe.record.created',
    'technical', 'probe.record.create',
    pg_catalog.gen_random_uuid(), pg_catalog.gen_random_uuid(), 'worker',
    0, null, 1, null, 'worker:history', null, '{}'::jsonb
  ) $$,
  '23514', null,
  'History rejects non-positive aggregate versions'
);

select throws_ok(
  $$ select private.append_history(
    '2a000000-0000-4000-8000-000000000001', 'probe_record',
    pg_catalog.gen_random_uuid(), 'probe.record.created',
    'technical', 'probe.record.create',
    pg_catalog.gen_random_uuid(), pg_catalog.gen_random_uuid(), 'worker',
    1, null, 0, null, 'worker:history', null, '{}'::jsonb
  ) $$,
  '23514', null,
  'History rejects non-positive history schema versions'
);

select throws_ok(
  $$ select private.append_history(
    '2a000000-0000-4000-8000-000000000001', 'probe_record',
    pg_catalog.gen_random_uuid(), 'probe.record.created',
    'technical', 'probe.record.create',
    pg_catalog.gen_random_uuid(), pg_catalog.gen_random_uuid(), 'worker',
    1, null, 1, null, 'worker:history', null, '[1,2]'::jsonb
  ) $$,
  '23514', null,
  'History payload must be an object'
);

select throws_ok(
  $$ select private.append_history(
    '2a000000-0000-4000-8000-000000000001', 'probe_record',
    pg_catalog.gen_random_uuid(), 'probe.record.created',
    'technical', 'probe.record.create',
    pg_catalog.gen_random_uuid(), pg_catalog.gen_random_uuid(), 'worker',
    1, null, 1, null, 'worker:history', null,
    '{"safe":{"refresh_token":"secret"}}'::jsonb
  ) $$,
  '23514', null,
  'History recursively rejects forbidden secret-bearing keys'
);

select lives_ok(
  $$ select private.append_history(
    '2a000000-0000-4000-8000-000000000001', 'probe_record',
    pg_catalog.gen_random_uuid(), 'probe.record.payload_checked',
    'technical', 'probe.record.check_payload',
    pg_catalog.gen_random_uuid(), pg_catalog.gen_random_uuid(), 'worker',
    1, null, 1, null, 'worker:history', null,
    pg_catalog.jsonb_build_object('value', pg_catalog.repeat('a', 65000))
  ) $$,
  'a bounded History payload below 64 KiB is accepted'
);

select throws_ok(
  $$ select private.append_history(
    '2a000000-0000-4000-8000-000000000001', 'probe_record',
    pg_catalog.gen_random_uuid(), 'probe.record.payload_checked',
    'technical', 'probe.record.check_payload',
    pg_catalog.gen_random_uuid(), pg_catalog.gen_random_uuid(), 'worker',
    1, null, 1, null, 'worker:history', null,
    pg_catalog.jsonb_build_object('value', pg_catalog.repeat('a', 65536))
  ) $$,
  '23514', null,
  'a History payload above the 64 KiB serialized limit is rejected'
);

select throws_ok(
  $$ update public.history_entries set human_code = 'FORGED' where id = (select id from w3a_refs where key = 'history_a') $$,
  '55000', 'history_entries is append-only',
  'History facts cannot be updated even by the owner path'
);
select throws_ok(
  $$ delete from public.history_entries where id = (select id from w3a_refs where key = 'history_a') $$,
  '55000', 'history_entries is append-only',
  'History facts cannot be deleted even by the owner path'
);
select throws_ok(
  $$ truncate public.history_entries $$,
  '55000', 'history_entries is append-only',
  'History facts cannot be truncated even by the owner path'
);

-- Audit backwards compatibility and W3A enrichments.
insert into public.audit_events (
  tenant_id, actor_user_id, actor_kind, event_type, entity_type, entity_id
)
values (
  '2a000000-0000-4000-8000-000000000001',
  '1a000000-0000-4000-8000-000000000001',
  'application_user', 'probe.created', 'probe_record',
  '5a000000-0000-4000-8000-000000000001'
);

select is(
  (
    select source
    from public.audit_events
    where event_type = 'probe.created' and entity_id = '5a000000-0000-4000-8000-000000000001'
  ),
  'user_command',
  'legacy-shape Audit inserts receive a safe source for new rows'
);
select is(
  (
    select event_version
    from public.audit_events
    where event_type = 'probe.created' and entity_id = '5a000000-0000-4000-8000-000000000001'
  ),
  1,
  'legacy-shape Audit inserts receive version one'
);

insert into public.audit_events (
  tenant_id, actor_kind, event_type, entity_type, entity_id
)
values (
  '2a000000-0000-4000-8000-000000000001',
  'technical', 'probe.migrated', 'probe_record',
  '5a000000-0000-4000-8000-000000000001'
);

select is(
  (
    select actor_ref
    from public.audit_events
    where event_type = 'probe.migrated' and entity_id = '5a000000-0000-4000-8000-000000000001'
  ),
  'technical:legacy-writer',
  'new events from pre-W3 technical writers receive explicit compatibility provenance'
);
select is(
  (
    select source
    from public.audit_events
    where event_type = 'probe.migrated' and entity_id = '5a000000-0000-4000-8000-000000000001'
  ),
  'system',
  'new events from pre-W3 technical writers receive the controlled system source'
);
select is(
  (
    select authority_kind
    from public.audit_events
    where event_type = 'probe.created' and entity_id = '5a000000-0000-4000-8000-000000000001'
  ),
  'tenant',
  'application Audit actors are classified as tenant authority'
);

select lives_ok(
  $$ select private.append_audit(
    '2a000000-0000-4000-8000-000000000001', 'technical',
    'probe.reconciled', 'probe_record',
    '7a000000-0000-4000-8000-000000000010', 'worker',
    null, 'worker:audit-reconciler',
    '5a000000-0000-4000-8000-000000000001',
    '6a000000-0000-4000-8000-000000000010',
    '8a000000-0000-4000-8000-000000000010', 1, null,
    '{"result":"ok"}'::jsonb
  ) $$,
  'Audit represents a technical actor explicitly'
);

select is(
  (
    select authority_kind
    from public.audit_events
    where command_id = '6a000000-0000-4000-8000-000000000010'
  ),
  'technical',
  'technical Audit actors are not misrepresented as tenant users'
);
select is(
  (
    select causation_id
    from public.audit_events
    where command_id = '6a000000-0000-4000-8000-000000000010'
  ),
  '8a000000-0000-4000-8000-000000000010'::uuid,
  'Audit persists causation separately from correlation'
);

select lives_ok(
  $$ select private.write_authorization_audit(
    '2a000000-0000-4000-8000-000000000001',
    '1a000000-0000-4000-8000-000000000001',
    '7a000000-0000-4000-8000-000000000020',
    'authorization.probe.updated', 'probe_record',
    '5a000000-0000-4000-8000-000000000001', 'approved change',
    '{"version":2}'::jsonb
  ) $$,
  'the W2 authorization Audit helper remains compatible'
);
select is(
  (
    select reason
    from public.audit_events
    where correlation_id = '7a000000-0000-4000-8000-000000000020'
  ),
  'approved change',
  'the compatibility writer promotes reason to the W3A column'
);
select is(
  (
    select metadata ->> 'reason'
    from public.audit_events
    where correlation_id = '7a000000-0000-4000-8000-000000000020'
  ),
  'approved change',
  'the compatibility writer preserves the W2 metadata contract'
);
select ok(
  (
    select command_id is not null
    from public.audit_events
    where correlation_id = '7a000000-0000-4000-8000-000000000020'
  ),
  'the compatibility writer assigns a command identity'
);

select throws_ok(
  $$ select private.append_audit(
    '2a000000-0000-4000-8000-000000000001', 'application_user',
    'probe.invalid', 'probe_record', pg_catalog.gen_random_uuid(), 'user_command',
    null, null, pg_catalog.gen_random_uuid(), pg_catalog.gen_random_uuid(),
    null, 1, null, '{}'::jsonb
  ) $$,
  '22023', 'INVALID_AUDIT_ACTOR',
  'Audit rejects a missing human actor'
);
select throws_ok(
  $$ select private.append_audit(
    '2a000000-0000-4000-8000-000000000001', 'technical',
    'probe.invalid', 'probe_record', pg_catalog.gen_random_uuid(), 'worker',
    null, 'worker:audit', pg_catalog.gen_random_uuid(), pg_catalog.gen_random_uuid(),
    null, 1, null, '{"jwt":"secret"}'::jsonb
  ) $$,
  '23514', null,
  'Audit rejects forbidden secret-bearing metadata'
);
select throws_ok(
  $$ select private.append_audit(
    '2a000000-0000-4000-8000-000000000001', 'technical',
    'probe.invalid', 'probe_record', pg_catalog.gen_random_uuid(), 'browser',
    null, 'worker:audit', pg_catalog.gen_random_uuid(), pg_catalog.gen_random_uuid(),
    null, 1, null, '{}'::jsonb
  ) $$,
  '23514', null,
  'Audit rejects an uncontrolled source taxonomy'
);

select throws_ok(
  $$ update public.audit_events set reason = 'forged' where event_type = 'probe.created' $$,
  '55000', 'audit_events is append-only',
  'evolved Audit facts remain immutable'
);

-- Failure of mandatory audit/history must roll back the command statement.
create temporary table w3a_atomic_probe (id uuid primary key);

select throws_ok(
  $$ do $atomic$
  begin
    insert into w3a_atomic_probe values ('9a000000-0000-4000-8000-000000000001');
    perform private.append_history(
      '2a000000-0000-4000-8000-000000000001', 'probe_record',
      pg_catalog.gen_random_uuid(), 'invalid', 'technical', 'probe.record.create',
      pg_catalog.gen_random_uuid(), pg_catalog.gen_random_uuid(), 'worker',
      1, null, 1, null, 'worker:history', null, '{}'::jsonb
    );
  end
  $atomic$ $$,
  '23514', null,
  'a mandatory History failure aborts the containing command statement'
);
select is(
  (select count(*) from w3a_atomic_probe where id = '9a000000-0000-4000-8000-000000000001'),
  0::bigint,
  'the mutation is absent after mandatory History failure'
);

select throws_ok(
  $$ do $atomic$
  begin
    insert into w3a_atomic_probe values ('9a000000-0000-4000-8000-000000000002');
    perform private.append_audit(
      '2a000000-0000-4000-8000-000000000001', 'technical',
      'probe.invalid', 'probe_record', pg_catalog.gen_random_uuid(), 'worker',
      null, 'worker:audit', pg_catalog.gen_random_uuid(), pg_catalog.gen_random_uuid(),
      null, 1, null, '{"password":"secret"}'::jsonb
    );
  end
  $atomic$ $$,
  '23514', null,
  'a mandatory Audit failure aborts the containing command statement'
);
select is(
  (select count(*) from w3a_atomic_probe where id = '9a000000-0000-4000-8000-000000000002'),
  0::bigint,
  'the mutation is absent after mandatory Audit failure'
);

-- Client roles cannot read, write or invoke the server-side boundaries.
set local "request.jwt.claim.sub" = '1a000000-0000-4000-8000-000000000001';
set local role authenticated;

select throws_ok(
  $$ select * from public.history_entries $$,
  '42501', null,
  'authenticated cannot read History directly'
);
select throws_ok(
  $$ insert into public.history_entries (
    tenant_id, aggregate_type, aggregate_id, history_type, actor_kind,
    actor_user_id, command_name, command_id, correlation_id, source
  ) values (
    '2a000000-0000-4000-8000-000000000001', 'probe_record',
    pg_catalog.gen_random_uuid(), 'probe.record.forged', 'application_user',
    '1a000000-0000-4000-8000-000000000001', 'probe.record.forge',
    pg_catalog.gen_random_uuid(), pg_catalog.gen_random_uuid(), 'user_command'
  ) $$,
  '42501', null,
  'authenticated cannot forge a History row'
);
select throws_ok(
  $$ update public.history_entries set payload = '{"admin":true}'::jsonb $$,
  '42501', null,
  'authenticated cannot mutate History directly'
);
select throws_ok(
  $$ delete from public.history_entries $$,
  '42501', null,
  'authenticated cannot delete History directly'
);
select throws_ok(
  $$ select private.append_history(
    '2a000000-0000-4000-8000-000000000001', 'probe_record',
    pg_catalog.gen_random_uuid(), 'probe.record.forged', 'application_user',
    'probe.record.forge', pg_catalog.gen_random_uuid(), pg_catalog.gen_random_uuid(),
    'user_command', 1, null, 1,
    '1a000000-0000-4000-8000-000000000001', null, null,
    '{"tenant_id":"2a000000-0000-4000-8000-000000000002"}'::jsonb
  ) $$,
  '42501', null,
  'authenticated cannot call the private writer or spoof tenant through payload'
);
select throws_ok(
  $$ insert into public.audit_events (
    tenant_id, actor_user_id, actor_kind, event_type, entity_type
  ) values (
    '2a000000-0000-4000-8000-000000000002',
    '1a000000-0000-4000-8000-000000000001',
    'application_user', 'probe.forged', 'probe_record'
  ) $$,
  '42501', null,
  'authenticated cannot forge cross-tenant Audit directly'
);

reset role;

select * from finish();
rollback;
