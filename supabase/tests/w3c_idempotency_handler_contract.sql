begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Physical stores and closed access surface.
select has_table('private', 'command_idempotency', 'W3C creates the command idempotency store');
select has_table('private', 'event_handler_receipts', 'W3C creates the handler receipt store');
select has_pk('private', 'command_idempotency', 'command idempotency rows have stable identity');
select has_pk('private', 'event_handler_receipts', 'handler receipts have stable identity');

select is(
  (
    select count(*)
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'private'
      and relation.relname in ('command_idempotency', 'event_handler_receipts')
      and relation.relrowsecurity
  ),
  2::bigint,
  'both W3C stores have RLS enabled'
);

select is(
  (
    select count(*) from pg_catalog.pg_policies
    where schemaname = 'private'
      and tablename in ('command_idempotency', 'event_handler_receipts')
  ),
  0::bigint,
  'W3C stores are fail-closed with no policies'
);

select is(
  (
    select count(*) from information_schema.table_privileges
    where table_schema = 'private'
      and table_name in ('command_idempotency', 'event_handler_receipts')
      and grantee in ('PUBLIC', 'anon', 'authenticated', 'service_role')
  ),
  0::bigint,
  'clients and service_role have no direct W3C table grants'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace on namespace.oid = relation.relnamespace
    join pg_catalog.pg_roles as owner_role on owner_role.oid = relation.relowner
    where namespace.nspname = 'private'
      and relation.relname in ('command_idempotency', 'event_handler_receipts')
      and owner_role.rolname = 'postgres'
  ),
  2::bigint,
  'both W3C stores have the controlled postgres owner'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_constraint as constraint_record
    join pg_catalog.pg_class as relation on relation.oid = constraint_record.conrelid
    join pg_catalog.pg_namespace as namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'private'
      and relation.relname = 'command_idempotency'
      and constraint_record.conname = 'command_idempotency_namespace_uq'
      and constraint_record.contype = 'u'
  ),
  'command idempotency has a database-enforced namespace unique constraint'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_constraint as constraint_record
    join pg_catalog.pg_class as relation on relation.oid = constraint_record.conrelid
    join pg_catalog.pg_namespace as namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'private'
      and relation.relname = 'event_handler_receipts'
      and constraint_record.conname = 'event_handler_receipts_consumer_event_uq'
      and constraint_record.contype = 'u'
  ),
  'handler receipts are unique by consumer and event'
);

select ok(
  exists (
    select 1 from pg_catalog.pg_indexes
    where schemaname = 'private'
      and tablename = 'command_idempotency'
      and indexname = 'command_idempotency_expires_idx'
  ),
  'command idempotency has the planned expiry-oriented index'
);

select has_column(
  'private', 'command_idempotency', 'idempotency_key_hash',
  'only the opaque key digest is persisted'
);
select hasnt_column(
  'private', 'command_idempotency', 'idempotency_key',
  'raw idempotency keys and accidental tokens are not persisted'
);

select has_function('private', 'semantic_fingerprint', array['jsonb'], 'canonical SHA-256 helper exists');
select has_function(
  'private', 'acquire_command_idempotency',
  array['uuid', 'text', 'text', 'text', 'text', 'bytea', 'uuid', 'text', 'timestamp with time zone'],
  'command idempotency acquisition boundary exists'
);
select has_function(
  'private', 'complete_command_idempotency', array['uuid', 'integer', 'jsonb'],
  'command idempotency completion boundary exists'
);
select has_function(
  'private', 'record_event_handler_receipt',
  array['text', 'uuid', 'text', 'integer', 'integer', 'jsonb'],
  'handler receipt boundary exists'
);
select has_function(
  'public', 'create_tenant_profile', array['text', 'text', 'uuid'],
  'the original W3B create profile signature remains available'
);
select has_function(
  'public', 'create_tenant_profile', array['text', 'text', 'uuid', 'text'],
  'the explicit idempotent create profile overload exists'
);

select is(
  (
    select count(*)
    from information_schema.routine_privileges
    where specific_schema = 'private'
      and routine_name in (
        'semantic_fingerprint', 'protect_command_idempotency',
        'acquire_command_idempotency', 'complete_command_idempotency',
        'reject_event_handler_receipt_mutation', 'record_event_handler_receipt'
      )
      and grantee in ('PUBLIC', 'anon', 'authenticated', 'service_role')
  ),
  0::bigint,
  'all private W3C helpers deny clients and service_role'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'private'
      and procedure.proname in (
        'semantic_fingerprint', 'protect_command_idempotency',
        'acquire_command_idempotency', 'complete_command_idempotency',
        'reject_event_handler_receipt_mutation', 'record_event_handler_receipt'
      )
      and procedure.prosecdef
  ),
  0::bigint,
  'W3C private helpers remain SECURITY INVOKER'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
    join pg_catalog.pg_roles as owner_role on owner_role.oid = procedure.proowner
    where namespace.nspname = 'private'
      and procedure.proname in (
        'semantic_fingerprint', 'protect_command_idempotency',
        'acquire_command_idempotency', 'complete_command_idempotency',
        'reject_event_handler_receipt_mutation', 'record_event_handler_receipt'
      )
      and (
        owner_role.rolname <> 'postgres'
        or not exists (
          select 1
          from pg_catalog.unnest(coalesce(procedure.proconfig, array[]::text[])) as setting(value)
          where setting.value = 'search_path=""'
        )
      )
  ),
  0::bigint,
  'every W3C helper has controlled owner and empty search_path'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
    join pg_catalog.pg_roles as owner_role on owner_role.oid = procedure.proowner
    where namespace.nspname = 'public'
      and procedure.proname = 'create_tenant_profile'
      and procedure.pronargs = 4
      and procedure.prosecdef
      and owner_role.rolname = 'postgres'
      and exists (
        select 1
        from pg_catalog.unnest(coalesce(procedure.proconfig, array[]::text[])) as setting(value)
        where setting.value = 'search_path=""'
      )
  ),
  1::bigint,
  'the idempotent RPC is a controlled SECURITY DEFINER boundary'
);
select is(
  pg_catalog.has_function_privilege(
    'authenticated', 'public.create_tenant_profile(text,text,uuid,text)', 'EXECUTE'
  ),
  true,
  'authenticated receives only the explicit idempotent command boundary'
);
select is(
  (
    select count(*)
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
    cross join lateral pg_catalog.aclexplode(
      coalesce(procedure.proacl, pg_catalog.acldefault('f', procedure.proowner))
    ) as privilege
    left join pg_catalog.pg_roles as grantee on grantee.oid = privilege.grantee
    where namespace.nspname = 'public'
      and procedure.proname = 'create_tenant_profile'
      and procedure.pronargs = 4
      and privilege.privilege_type = 'EXECUTE'
      and coalesce(grantee.rolname, 'PUBLIC') in ('PUBLIC', 'anon', 'service_role')
  ),
  0::bigint,
  'PUBLIC anon and service_role cannot invoke the idempotent command'
);

select is(
  pg_catalog.octet_length(private.semantic_fingerprint('{"a":1}'::jsonb)),
  32,
  'semantic fingerprint is a 32-byte SHA-256 digest'
);
select is(
  pg_catalog.encode(private.semantic_fingerprint('{"b":2,"a":{"y":2,"x":1}}'::jsonb), 'hex'),
  pg_catalog.encode(private.semantic_fingerprint('{"a":{"x":1,"y":2},"b":2}'::jsonb), 'hex'),
  'JSON object key order does not affect the canonical fingerprint'
);
select isnt(
  pg_catalog.encode(private.semantic_fingerprint('{"name":"Manager"}'::jsonb), 'hex'),
  pg_catalog.encode(private.semantic_fingerprint('{"name":"Supervisor"}'::jsonb), 'hex'),
  'semantic input changes produce a different fingerprint'
);

-- Two tenants establish authoritative namespace isolation.
insert into auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
values
  ('1c000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'w3c-manager-a@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp()),
  ('1c000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'w3c-manager-b@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp());

create temporary table w3c_tenant_a as
select * from public.bootstrap_initial_tenant(
  '1c000000-0000-4000-8000-000000000001',
  'W3C Tenant A',
  '7c000000-0000-4000-8000-000000000001'
);
grant select on table w3c_tenant_a to authenticated;

insert into public.tenants (id, tenant_ref, display_name, status, created_by)
values (
  '2c000000-0000-4000-8000-000000000002',
  '3c000000-0000-4000-8000-000000000002',
  'W3C Tenant B', 'active',
  '1c000000-0000-4000-8000-000000000002'
);

select * from private.provision_tenant_authorization(
  '2c000000-0000-4000-8000-000000000002', null,
  '1c000000-0000-4000-8000-000000000002',
  '7c000000-0000-4000-8000-000000000002'
);

insert into public.tenant_memberships (
  tenant_id, user_id, status, joined_at, created_by,
  profile_id, profile_assigned_at, profile_assigned_by
)
select
  '2c000000-0000-4000-8000-000000000002',
  '1c000000-0000-4000-8000-000000000002',
  'active', statement_timestamp(), '1c000000-0000-4000-8000-000000000002',
  profile.id, statement_timestamp(), '1c000000-0000-4000-8000-000000000002'
from public.tenant_profiles as profile
where profile.tenant_id = '2c000000-0000-4000-8000-000000000002'
  and profile.template_key = 'manager';

create temporary table w3c_first_result (
  profile_id uuid,
  profile_version bigint,
  command_correlation_id uuid
);
create temporary table w3c_replay_result (
  profile_id uuid,
  profile_version bigint,
  command_correlation_id uuid
);
grant insert, select on table w3c_first_result, w3c_replay_result to authenticated;

set local "request.jwt.claim.sub" = '1c000000-0000-4000-8000-000000000001';
set local role authenticated;
insert into w3c_first_result
select * from public.create_tenant_profile(
  'W3C Idempotent Profile',
  'prove command idempotency',
  '5c000000-0000-4000-8000-000000000001',
  'w3c-command-key-0001'
);
reset role;

select is((select count(*) from w3c_first_result), 1::bigint, 'first execution returns one stable result');
select is(
  (
    select count(*) from private.command_idempotency
    where tenant_id = (select tenant_id from w3c_tenant_a)
      and actor_scope = 'application_user:1c000000-0000-4000-8000-000000000001'
      and source = 'user_command'
      and command_name = 'authorization.create_tenant_profile'
      and idempotency_key_hash = private.semantic_fingerprint(pg_catalog.to_jsonb('w3c-command-key-0001'::text))
      and status = 'completed'
  ),
  1::bigint,
  'first execution completes one row in the full tenant actor/source command namespace'
);
select is(
  (
    select pg_catalog.octet_length(request_fingerprint)
    from private.command_idempotency
    where idempotency_key_hash = private.semantic_fingerprint(pg_catalog.to_jsonb('w3c-command-key-0001'::text))
  ),
  32,
  'the integrated command stores its SHA-256 fingerprint'
);

set local role authenticated;
insert into w3c_replay_result
select * from public.create_tenant_profile(
  'W3C Idempotent Profile',
  'prove command idempotency',
  '5c000000-0000-4000-8000-000000000099',
  'w3c-command-key-0001'
);
reset role;

select is(
  (select row(first_result.*)::text from w3c_first_result as first_result),
  (select row(replay_result.*)::text from w3c_replay_result as replay_result),
  'compatible replay returns the exact stable result including original correlation'
);
select is(
  (
    select count(*) from public.tenant_profiles
    where tenant_id = (select tenant_id from w3c_tenant_a)
      and name = 'W3C Idempotent Profile'
  ),
  1::bigint,
  'compatible replay does not duplicate the domain mutation'
);
select is(
  (
    select count(*) from public.audit_events
    where command_id = (
      select command_id from private.command_idempotency
      where idempotency_key_hash = private.semantic_fingerprint(pg_catalog.to_jsonb('w3c-command-key-0001'::text))
    )
  ),
  1::bigint,
  'compatible replay does not duplicate Audit'
);
select is(
  (
    select count(*) from private.outbox_events
    where command_id = (
      select command_id from private.command_idempotency
      where idempotency_key_hash = private.semantic_fingerprint(pg_catalog.to_jsonb('w3c-command-key-0001'::text))
    )
  ),
  1::bigint,
  'compatible replay does not duplicate Event/Outbox'
);
select is(
  (
    select count(*) from public.history_entries
    where command_id = (
      select command_id from private.command_idempotency
      where idempotency_key_hash = private.semantic_fingerprint(pg_catalog.to_jsonb('w3c-command-key-0001'::text))
    )
  ),
  0::bigint,
  'History remains explicitly N/A for profile creation'
);

set local role authenticated;
select throws_ok(
  $$ select * from public.create_tenant_profile(
    'W3C Conflicting Profile', 'prove command idempotency',
    '5c000000-0000-4000-8000-000000000002', 'w3c-command-key-0001'
  ) $$,
  'P0001', 'IDEMPOTENCY_FINGERPRINT_CONFLICT',
  'same namespace with a different semantic fingerprint fails closed'
);
reset role;

select is(
  (
    select count(*) from public.tenant_profiles
    where tenant_id = (select tenant_id from w3c_tenant_a)
      and name = 'W3C Conflicting Profile'
  ),
  0::bigint,
  'fingerprint conflict performs no new mutation'
);

-- The same opaque key in another tenant is a distinct namespace.
set local "request.jwt.claim.sub" = '1c000000-0000-4000-8000-000000000002';
set local role authenticated;
select lives_ok(
  $$ select * from public.create_tenant_profile(
    'W3C Tenant B Profile', 'prove tenant namespace',
    '5c000000-0000-4000-8000-000000000003', 'w3c-command-key-0001'
  ) $$,
  'the same key is independently usable in another authoritative tenant'
);
reset role;

select is(
  (
    select count(*) from private.command_idempotency
    where idempotency_key_hash = private.semantic_fingerprint(pg_catalog.to_jsonb('w3c-command-key-0001'::text))
  ),
  2::bigint,
  'idempotency key is not accidentally global across tenants'
);

select lives_ok(
  $$ select * from private.acquire_command_idempotency(
    (select tenant_id from w3c_tenant_a), 'system', 'system',
    'authorization.reconcile_profile', 'w3c-scope-key-0001',
    private.semantic_fingerprint('{"operation":"reconcile"}'::jsonb),
    null, 'system:reconciler-a', null
  ) $$,
  'a controlled system actor can acquire its own namespaced command identity'
);
select lives_ok(
  $$ select * from private.acquire_command_idempotency(
    (select tenant_id from w3c_tenant_a), 'system', 'scheduler',
    'authorization.reconcile_profile', 'w3c-scope-key-0001',
    private.semantic_fingerprint('{"operation":"reconcile"}'::jsonb),
    null, 'system:reconciler-a', null
  ) $$,
  'source participates in the namespace independently of the opaque key'
);
select lives_ok(
  $$ select * from private.acquire_command_idempotency(
    (select tenant_id from w3c_tenant_a), 'system', 'system',
    'authorization.reconcile_profile', 'w3c-scope-key-0001',
    private.semantic_fingerprint('{"operation":"reconcile"}'::jsonb),
    null, 'system:reconciler-b', null
  ) $$,
  'actor scope participates in the namespace independently of the opaque key'
);
select is(
  (
    select count(*) from private.command_idempotency
    where idempotency_key_hash = private.semantic_fingerprint(pg_catalog.to_jsonb('w3c-scope-key-0001'::text))
  ),
  3::bigint,
  'tenant actor source command and key jointly define the namespace'
);

create temporary table w3c_unsafe_result_command as
select * from private.acquire_command_idempotency(
  (select tenant_id from w3c_tenant_a), 'system', 'system',
  'authorization.reconcile_profile', 'w3c-unsafe-result-0001',
  private.semantic_fingerprint('{"operation":"unsafe-result-probe"}'::jsonb),
  null, 'system:reconciler-a', null
);
select throws_ok(
  $$ select private.complete_command_idempotency(
    (select acquired_command_id from w3c_unsafe_result_command),
    1, '{"access_token":"must-not-persist"}'::jsonb
  ) $$,
  '23514', null,
  'command replay result rejects secret-bearing keys'
);
select is(
  (
    select status from private.command_idempotency
    where command_id = (select acquired_command_id from w3c_unsafe_result_command)
  ),
  'in_progress',
  'rejected unsafe result never marks the command completed'
);

-- A key cannot supply tenant or actor authority, and helpers are not client-callable.
set local role authenticated;
select throws_ok(
  $$ select * from private.acquire_command_idempotency(
    '2c000000-0000-4000-8000-000000000002', 'application_user', 'user_command',
    'authorization.create_tenant_profile', 'w3c-forged-key-0001',
    private.semantic_fingerprint('{"name":"forged"}'::jsonb),
    '1c000000-0000-4000-8000-000000000001', null, null
  ) $$,
  '42501', null,
  'authenticated cannot forge tenant or actor through the private helper'
);
reset role;

-- A failed mutation rolls the initially acquired idempotency row back.
set local "request.jwt.claim.sub" = '1c000000-0000-4000-8000-000000000001';
set local role authenticated;
select throws_ok(
  $$ select * from public.create_tenant_profile(
    'W3C Idempotent Profile', 'duplicate mutation',
    '5c000000-0000-4000-8000-000000000010', 'w3c-mutation-failure-0001'
  ) $$,
  'P0001', 'AUTHORIZATION_OPERATION_UNAVAILABLE',
  'failed domain mutation aborts the idempotent command'
);
reset role;
select is(
  (select count(*) from private.command_idempotency where idempotency_key_hash = private.semantic_fingerprint(pg_catalog.to_jsonb('w3c-mutation-failure-0001'::text))),
  0::bigint,
  'failed mutation leaves no false idempotency success or in-progress row'
);

-- Audit and Event failures both roll back mutation and idempotency state.
create function pg_temp.fail_w3c_audit_insert()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.correlation_id = '5c000000-0000-4000-8000-000000000011'::uuid then
    raise exception using errcode = 'P0001', message = 'AUDIT_PERSISTENCE_INJECTED_FAILURE';
  end if;
  return new;
end;
$$;
create trigger w3c_fail_audit_insert
before insert on public.audit_events
for each row execute function pg_temp.fail_w3c_audit_insert();

set local role authenticated;
select throws_ok(
  $$ select * from public.create_tenant_profile(
    'W3C Audit Rollback', 'inject Audit failure',
    '5c000000-0000-4000-8000-000000000011', 'w3c-audit-failure-0001'
  ) $$,
  'P0001', 'AUDIT_PERSISTENCE_INJECTED_FAILURE',
  'required Audit failure aborts the idempotent command'
);
reset role;
select is((select count(*) from private.command_idempotency where idempotency_key_hash = private.semantic_fingerprint(pg_catalog.to_jsonb('w3c-audit-failure-0001'::text))), 0::bigint, 'Audit failure rolls idempotency back');
select is((select count(*) from public.tenant_profiles where name = 'W3C Audit Rollback'), 0::bigint, 'Audit failure rolls mutation back');
select is((select count(*) from private.outbox_events where correlation_id = '5c000000-0000-4000-8000-000000000011'), 0::bigint, 'Audit failure leaves no Event');

create function pg_temp.fail_w3c_outbox_insert()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.correlation_id = '5c000000-0000-4000-8000-000000000012'::uuid then
    raise exception using errcode = 'P0001', message = 'EVENT_PERSISTENCE_INJECTED_FAILURE';
  end if;
  return new;
end;
$$;
create trigger w3c_fail_outbox_insert
before insert on private.outbox_events
for each row execute function pg_temp.fail_w3c_outbox_insert();

set local role authenticated;
select throws_ok(
  $$ select * from public.create_tenant_profile(
    'W3C Event Rollback', 'inject Event failure',
    '5c000000-0000-4000-8000-000000000012', 'w3c-event-failure-0001'
  ) $$,
  'P0001', 'EVENT_PERSISTENCE_INJECTED_FAILURE',
  'required Event failure aborts the idempotent command'
);
reset role;
select is((select count(*) from private.command_idempotency where idempotency_key_hash = private.semantic_fingerprint(pg_catalog.to_jsonb('w3c-event-failure-0001'::text))), 0::bigint, 'Event failure rolls idempotency back');
select is((select count(*) from public.tenant_profiles where name = 'W3C Event Rollback'), 0::bigint, 'Event failure rolls mutation back');
select is((select count(*) from public.audit_events where correlation_id = '5c000000-0000-4000-8000-000000000012'), 0::bigint, 'Event failure rolls Audit back');

-- Handler receipt evidence is separate from command idempotency and delivery state.
create temporary table w3c_receipt_first as
select * from private.record_event_handler_receipt(
  'w3c.contract_probe',
  (
    select event_id from private.outbox_events
    where command_id = (
      select command_id from private.command_idempotency
      where idempotency_key_hash = private.semantic_fingerprint(pg_catalog.to_jsonb('w3c-command-key-0001'::text))
        and tenant_id = (select tenant_id from w3c_tenant_a)
    )
  ),
  'w3c_profile_created_probe', 1, 1, '{"observed":true}'::jsonb
);

create temporary table w3c_receipt_replay as
select * from private.record_event_handler_receipt(
  'w3c.contract_probe',
  (
    select event_id from private.outbox_events
    where command_id = (
      select command_id from private.command_idempotency
      where idempotency_key_hash = private.semantic_fingerprint(pg_catalog.to_jsonb('w3c-command-key-0001'::text))
        and tenant_id = (select tenant_id from w3c_tenant_a)
    )
  ),
  'w3c_profile_created_probe', 1, 1, '{"ignored_on_duplicate":true}'::jsonb
);

select is((select replayed from w3c_receipt_first), false, 'first handler completion records a receipt');
select is((select replayed from w3c_receipt_replay), true, 'duplicate consumer/event is a replay no-op');
select is(
  (select stored_receipt_id from w3c_receipt_first),
  (select stored_receipt_id from w3c_receipt_replay),
  'duplicate processing returns the original receipt identity'
);
select is(
  (select stored_result from w3c_receipt_replay),
  '{"observed":true}'::jsonb,
  'duplicate processing returns the original stable result'
);
select is(
  (
    select count(*) from private.event_handler_receipts
    where consumer_name = 'w3c.contract_probe'
  ),
  1::bigint,
  'receipt uniqueness prevents a second logical completion record'
);
select is(
  (
    select receipt.tenant_id = event.tenant_id
      and receipt.event_type = event.event_type
      and receipt.event_version = event.event_version
    from private.event_handler_receipts as receipt
    join private.outbox_events as event on event.event_id = receipt.event_id
    where receipt.consumer_name = 'w3c.contract_probe'
  ),
  true,
  'receipt tenant and event contract are derived consistently from persisted origin'
);
select is(
  (
    select status from private.outbox_events
    where event_id = (select event_id from private.event_handler_receipts where consumer_name = 'w3c.contract_probe')
  ),
  'pending',
  'recording a receipt does not implement or mutate W3D delivery state'
);

select throws_ok(
  $$ select * from private.record_event_handler_receipt(
    'w3c.contract_probe',
    (select event_id from private.event_handler_receipts where consumer_name = 'w3c.contract_probe'),
    'different_handler', 1, 1, '{}'::jsonb
  ) $$,
  'P0001', 'HANDLER_RECEIPT_CONFLICT',
  'the same consumer/event cannot be reassigned to another handler'
);

select throws_ok(
  $$ select * from private.record_event_handler_receipt(
    'w3c.unsafe_result_probe',
    (select event_id from private.event_handler_receipts where consumer_name = 'w3c.contract_probe'),
    'w3c_profile_created_probe', 1, 1,
    '{"refresh_token":"must-not-persist"}'::jsonb
  ) $$,
  '23514', null,
  'handler receipt result rejects secret-bearing keys'
);
select is(
  (select count(*) from private.event_handler_receipts where consumer_name = 'w3c.unsafe_result_probe'),
  0::bigint,
  'unsafe handler result leaves no receipt'
);

select throws_ok(
  $$ insert into private.event_handler_receipts (
    consumer_name, event_id, tenant_id, event_type, event_version,
    handler_name, handler_version, result_version, result
  ) values (
    'w3c.forged_consumer',
    (select event_id from private.event_handler_receipts where consumer_name = 'w3c.contract_probe'),
    '2c000000-0000-4000-8000-000000000002',
    'authorization.profile.created', 1, 'forged_handler', 1, 1, '{}'
  ) $$,
  '23503', null,
  'receipt cannot forge a tenant inconsistent with its persisted event origin'
);

select throws_ok(
  $$ update private.event_handler_receipts set result = '{"changed":true}'::jsonb
     where consumer_name = 'w3c.contract_probe' $$,
  '55000', 'event handler receipt is immutable',
  'completed receipt evidence cannot be rewritten'
);

select throws_ok(
  $$ update private.command_idempotency
     set idempotency_key_hash = private.semantic_fingerprint(pg_catalog.to_jsonb('w3c-rewritten-key'::text))
     where idempotency_key_hash = private.semantic_fingerprint(pg_catalog.to_jsonb('w3c-command-key-0001'::text)) $$,
  '55000', 'command idempotency identity is immutable',
  'completed command namespace cannot be rewritten'
);

-- Direct runtime access remains closed for all bypass-relevant roles.
set local role authenticated;
select throws_ok($$ select * from private.command_idempotency $$, '42501', null, 'authenticated cannot read command idempotency');
select throws_ok($$ select * from private.event_handler_receipts $$, '42501', null, 'authenticated cannot read receipts');
reset role;
set local role anon;
select throws_ok($$ select * from private.command_idempotency $$, '42501', null, 'anon cannot read command idempotency');
reset role;
set local role service_role;
select throws_ok($$ select * from private.command_idempotency $$, '42501', null, 'service_role has no command idempotency shortcut');
select throws_ok($$ select * from private.event_handler_receipts $$, '42501', null, 'service_role has no receipt shortcut');
reset role;

-- W3D remains absent.
select is(
  (
    select count(*) from information_schema.columns
    where table_schema = 'private'
      and table_name = 'outbox_events'
      and column_name in (
        'claimed_by', 'claimed_at', 'lease_expires_at', 'lease_token',
        'processed_at', 'last_error_class', 'last_error_code',
        'last_error_message', 'handler_name', 'handler_version', 'requeue_count'
      )
  ),
  0::bigint,
  'W3C does not add W3D delivery runtime columns'
);
select is(
  (
    select count(*)
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'private'
      and relation.relname = 'worker_handler_controls'
  ),
  0::bigint,
  'W3C does not create the W3D operational registry table'
);
select is(
  (
    select count(*)
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
    where procedure.proname in ('claim_outbox_batch', 'complete_outbox_event', 'fail_outbox_event', 'requeue_dead_letter')
      and namespace.nspname in ('public', 'private')
  ),
  0::bigint,
  'W3C introduces no claim ack retry dead-letter or requeue boundary'
);

select * from finish();
rollback;
