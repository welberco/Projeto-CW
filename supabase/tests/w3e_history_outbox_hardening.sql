begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Integrated catalog gate: all persisted W3 facts are closed by default.
select is(
  (select count(*)
   from pg_catalog.pg_class as relation
   join pg_catalog.pg_namespace as namespace on namespace.oid = relation.relnamespace
   where (namespace.nspname, relation.relname) in (
     ('public', 'audit_events'), ('public', 'history_entries'),
     ('private', 'outbox_events'), ('private', 'command_idempotency'),
     ('private', 'event_handler_receipts')
   ) and relation.relrowsecurity),
  5::bigint,
  'all tenant-bearing W3 stores have RLS enabled'
);

select is(
  (select count(*) from pg_catalog.pg_policies
   where (schemaname, tablename) in (
     ('public', 'audit_events'), ('public', 'history_entries'),
     ('private', 'outbox_events'), ('private', 'command_idempotency'),
     ('private', 'event_handler_receipts')
   )),
  0::bigint,
  'W3 storage remains fail-closed without client policies'
);

select is(
  (select count(*) from information_schema.table_privileges
   where (table_schema, table_name) in (
     ('public', 'audit_events'), ('public', 'history_entries'),
     ('private', 'outbox_events'), ('private', 'command_idempotency'),
     ('private', 'event_handler_receipts'), ('private', 'worker_handler_controls')
   ) and grantee in ('PUBLIC', 'anon', 'authenticated', 'service_role', 'cw_worker')),
  0::bigint,
  'clients service_role and worker have no direct W3 table privileges'
);

select is(
  (select count(*) from information_schema.routine_privileges
   where routine_schema = 'public'
     and routine_name in (
       'claim_outbox_batch', 'read_profile_created_origin',
       'complete_outbox_event', 'fail_outbox_event'
     ) and grantee = 'cw_worker'),
  4::bigint,
  'cw_worker receives exactly the four fixed delivery boundaries'
);

select is(
  (select count(*) from information_schema.routine_privileges
   where routine_schema = 'public'
     and routine_name in (
       'claim_outbox_batch', 'read_profile_created_origin',
       'complete_outbox_event', 'fail_outbox_event'
     ) and grantee = 'service_role'),
  0::bigint,
  'service_role is not a W3 delivery shortcut'
);

select is(
  (select row(rolcanlogin, rolinherit, rolsuper, rolcreatedb,
              rolcreaterole, rolreplication, rolbypassrls)::text
   from pg_catalog.pg_roles where rolname = 'cw_worker'),
  row(false, false, false, false, false, false, false)::text,
  'cw_worker remains NOLOGIN NOINHERIT and non-administrative'
);

select is(
  (select count(*)
   from pg_catalog.pg_proc as procedure
   join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
   join pg_catalog.pg_roles as owner_role on owner_role.oid = procedure.proowner
   where namespace.nspname = 'public'
     and procedure.proname in (
       'claim_outbox_batch', 'read_profile_created_origin',
       'complete_outbox_event', 'fail_outbox_event'
     ) and procedure.prosecdef
     and owner_role.rolname = 'postgres'
     and 'search_path=""' = any(coalesce(procedure.proconfig, array[]::text[]))),
  4::bigint,
  'all privileged worker boundaries have controlled owner and empty search_path'
);

select is(
  (select count(*)
   from pg_catalog.pg_proc as procedure
   join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
   where namespace.nspname in ('public', 'private')
     and procedure.proname ~* '(purge|cleanup|retention)'
     and pg_catalog.pg_get_functiondef(procedure.oid) ~* '(audit_events|history_entries|outbox_events|command_idempotency|event_handler_receipts)'),
  0::bigint,
  'W3 introduces no implicit or arbitrary retention purge boundary'
);

-- Real command fixture used to verify the complete persisted chain.
insert into auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
values (
  '1e000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
  'w3e-manager@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp()
);

create temporary table w3e_tenant as
select * from public.bootstrap_initial_tenant(
  '1e000000-0000-4000-8000-000000000001',
  'W3E Tenant',
  '7e000000-0000-4000-8000-000000000001'
);
grant select on table w3e_tenant to authenticated;

set local "request.jwt.claim.sub" = '1e000000-0000-4000-8000-000000000001';
set local role authenticated;
select * from public.create_tenant_profile(
  'W3E Integrated Profile', 'integrated hardening command',
  '5e000000-0000-4000-8000-000000000001', 'w3e-command-key-0001'
);
reset role;

create temporary table w3e_event as
select event.event_id, event.tenant_id, event.aggregate_id, event.command_id,
       event.correlation_id, event.payload, event.metadata
from private.outbox_events as event
join public.tenant_profiles as profile on profile.id = event.aggregate_id
where profile.name = 'W3E Integrated Profile';

select is((select count(*) from w3e_event), 1::bigint, 'real command persists exactly one Event/Outbox fact');
select is(
  (select count(*) from public.audit_events where command_id = (select command_id from w3e_event)),
  1::bigint,
  'real command persists exactly one required Audit fact'
);
select is(
  (select count(*) from private.command_idempotency where command_id = (select command_id from w3e_event) and status = 'completed'),
  1::bigint,
  'real command completes exactly one stable idempotency result'
);
select is(
  (select count(*) from public.history_entries where command_id = (select command_id from w3e_event)),
  0::bigint,
  'History remains correctly N/A for profile creation'
);

set local role authenticated;
select * from public.create_tenant_profile(
  'W3E Integrated Profile', 'integrated hardening command',
  '5e000000-0000-4000-8000-000000000099', 'w3e-command-key-0001'
);
reset role;
select is(
  (select count(*) from public.tenant_profiles where name = 'W3E Integrated Profile'),
  1::bigint,
  'compatible replay returns without duplicating the domain mutation'
);
select is(
  (select count(*) from private.outbox_events where command_id = (select command_id from w3e_event)),
  1::bigint,
  'compatible replay does not duplicate Event/Outbox'
);
select is(
  (select count(*) from public.audit_events where command_id = (select command_id from w3e_event)),
  1::bigint,
  'compatible replay does not duplicate Audit'
);

set local role authenticated;
select throws_ok(
  $$ select * from public.create_tenant_profile(
       'W3E Changed Meaning', 'semantic conflict',
       '5e000000-0000-4000-8000-000000000001', 'w3e-command-key-0001'
     ) $$,
  'P0001', 'IDEMPOTENCY_FINGERPRINT_CONFLICT',
  'semantic change under the same namespace fails closed'
);
reset role;

-- Every class of persisted Event fact is immutable after enqueue.
select throws_ok(
  $$ update private.outbox_events set event_id = pg_catalog.gen_random_uuid()
     where event_id = (select event_id from w3e_event) $$,
  '55000', 'outbox event fact is immutable', 'event identity is immutable'
);
select throws_ok(
  $$ update private.outbox_events set event_type = 'authorization.profile.changed', event_version = 2
     where event_id = (select event_id from w3e_event) $$,
  '55000', 'outbox event fact is immutable', 'event type and version are immutable'
);
select throws_ok(
  $$ update private.outbox_events set tenant_id = '7e000000-0000-4000-8000-000000000001'
     where event_id = (select event_id from w3e_event) $$,
  '55000', 'outbox event fact is immutable', 'event tenant scope is immutable'
);
select throws_ok(
  $$ update private.outbox_events set aggregate_type = 'forged', aggregate_id = pg_catalog.gen_random_uuid()
     where event_id = (select event_id from w3e_event) $$,
  '55000', 'outbox event fact is immutable', 'event aggregate identity is immutable'
);
select throws_ok(
  $$ update private.outbox_events set actor_kind = 'system', actor_user_id = null, actor_ref = 'system:forged', source = 'system'
     where event_id = (select event_id from w3e_event) $$,
  '55000', 'outbox event fact is immutable', 'event actor and source are immutable'
);
select throws_ok(
  $$ update private.outbox_events set command_id = pg_catalog.gen_random_uuid(), correlation_id = pg_catalog.gen_random_uuid(), causation_id = pg_catalog.gen_random_uuid()
     where event_id = (select event_id from w3e_event) $$,
  '55000', 'outbox event fact is immutable', 'event command correlation and causation are immutable'
);
select throws_ok(
  $$ update private.outbox_events set payload = '{"profile_version":999}'::jsonb, metadata = '{"forged":true}'::jsonb
     where event_id = (select event_id from w3e_event) $$,
  '55000', 'outbox event fact is immutable', 'event payload and factual metadata are immutable'
);
select throws_ok(
  $$ update private.outbox_events set occurred_at = statement_timestamp() + interval '1 day'
     where event_id = (select event_id from w3e_event) $$,
  '55000', 'outbox event fact is immutable', 'authoritative event timestamp is immutable'
);

-- Audit and History are independent append-only evidence streams.
select private.append_history(
  (select tenant_id from w3e_event), 'tenant_profile', (select aggregate_id from w3e_event),
  'authorization.profile.created', 'application_user', 'authorization.profile.create',
  pg_catalog.gen_random_uuid(), pg_catalog.gen_random_uuid(), 'user_command',
  1, null, 1, '1e000000-0000-4000-8000-000000000001', null, null,
  '{"summary":"synthetic W3E history fixture"}'::jsonb
);
select throws_ok(
  $$ update public.audit_events set event_type = 'forged.audit.event'
     where command_id = (select command_id from w3e_event) $$,
  '55000', 'audit_events is append-only', 'Audit cannot be rewritten'
);
select throws_ok(
  $$ delete from public.audit_events where command_id = (select command_id from w3e_event) $$,
  '55000', 'audit_events is append-only', 'Audit cannot be deleted'
);
select throws_ok(
  $$ update public.history_entries set payload = '{"forged":true}'::jsonb
     where aggregate_id = (select aggregate_id from w3e_event) $$,
  '55000', 'history_entries is append-only', 'History cannot be falsified by update'
);
select throws_ok(
  $$ delete from public.history_entries where aggregate_id = (select aggregate_id from w3e_event) $$,
  '55000', 'history_entries is append-only', 'History cannot be deleted'
);

-- Effective access checks, not just static RLS declarations.
set local role anon;
select throws_ok($$ select * from public.audit_events $$, '42501', null, 'anonymous cannot read Audit');
select throws_ok($$ select * from public.history_entries $$, '42501', null, 'anonymous cannot read History');
reset role;

set local role authenticated;
select throws_ok($$ select * from public.audit_events $$, '42501', null, 'authenticated cannot read Audit directly');
select throws_ok($$ insert into public.audit_events default values $$, '42501', null, 'authenticated cannot inject Audit');
select throws_ok($$ select * from public.history_entries $$, '42501', null, 'authenticated cannot read History directly');
select throws_ok($$ insert into public.history_entries default values $$, '42501', null, 'authenticated cannot inject History');
select throws_ok($$ select * from private.outbox_events $$, '42501', null, 'authenticated cannot inspect Outbox');
reset role;

set local role service_role;
select throws_ok($$ select * from private.command_idempotency $$, '42501', null, 'service_role cannot inspect command idempotency');
select throws_ok($$ select * from private.event_handler_receipts $$, '42501', null, 'service_role cannot forge receipts');
select throws_ok($$ select * from private.worker_handler_controls $$, '42501', null, 'service_role cannot inspect handler controls');
reset role;

select is(
  pg_catalog.has_table_privilege('cw_worker', 'private.outbox_events', 'UPDATE'),
  false,
  'cw_worker cannot bypass fenced boundaries with direct state mutation'
);
select is(
  pg_catalog.has_table_privilege('cw_worker', 'private.worker_handler_controls', 'SELECT'),
  false,
  'cw_worker cannot select arbitrary handlers'
);

-- Boundary values and forbidden authority-bearing content remain fail-closed.
select throws_ok(
  $$ select private.enqueue_event(
       (select tenant_id from w3e_event), 'authorization.profile.created', 'system', 'system',
       pg_catalog.gen_random_uuid(), pg_catalog.gen_random_uuid(), 'tenant_profile',
       (select aggregate_id from w3e_event), 1, 1, null, 'system:w3e', null,
       '{"tenant_id":"forged","handler":"forged","capability":"admin"}'::jsonb, '{}'
     ) $$,
  '23514', null, 'payload cannot carry tenant handler or capability authority'
);
select throws_ok(
  $$ select * from public.claim_outbox_batch('local:w3e-worker', 0) $$,
  '22023', 'INVALID_OUTBOX_BATCH_SIZE', 'claim rejects batch size below one'
);
select throws_ok(
  $$ select * from public.claim_outbox_batch('local:w3e-worker', 101) $$,
  '22023', 'INVALID_OUTBOX_BATCH_SIZE', 'claim rejects batch size above one hundred'
);
select is(
  pg_catalog.char_length(private.sanitize_worker_error(pg_catalog.repeat('x', 500))),
  500,
  'error sanitizer accepts exactly five hundred safe characters'
);
select throws_ok(
  $$ select private.sanitize_worker_error(pg_catalog.repeat('x', 501)) $$,
  '22023', 'UNSAFE_WORKER_ERROR', 'error sanitizer rejects more than five hundred characters'
);

select * from finish();
rollback;
