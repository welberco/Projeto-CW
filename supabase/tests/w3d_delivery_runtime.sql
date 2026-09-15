begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select has_table('private', 'worker_handler_controls', 'W3D creates private handler controls');
select has_column('private', 'outbox_events', 'lease_token', 'outbox has an unpredictable lease token');
select has_column('private', 'outbox_events', 'fencing_token', 'outbox has a monotonic fencing token');
select has_column('private', 'outbox_events', 'dead_lettered_at', 'outbox records terminal delivery time');
select has_column('private', 'outbox_events', 'requeue_count', 'outbox preserves controlled reprocessing count');
select has_index('private', 'outbox_events', 'outbox_events_processing_lease_idx', 'expired processing leases have a targeted index');

select is(
  (select count(*) from information_schema.table_privileges
   where table_schema = 'private'
     and table_name in ('outbox_events', 'worker_handler_controls')
     and grantee in ('PUBLIC', 'anon', 'authenticated', 'service_role', 'cw_worker')),
  0::bigint,
  'clients service_role and worker have no direct delivery table grants'
);
select is(
  (select count(*) from pg_catalog.pg_policies
   where schemaname = 'private' and tablename = 'outbox_events'),
  0::bigint,
  'outbox remains fail-closed without client policies'
);

select has_function('public', 'claim_outbox_batch', array['text', 'integer'], 'claim boundary exists');
select has_function(
  'public', 'read_profile_created_origin', array['uuid', 'text', 'uuid', 'bigint'],
  'fixed authoritative profile reread boundary exists'
);
select has_function(
  'public', 'complete_outbox_event', array['uuid', 'text', 'uuid', 'bigint', 'integer', 'jsonb'],
  'fenced ack boundary exists'
);
select has_function(
  'public', 'fail_outbox_event', array['uuid', 'text', 'uuid', 'bigint', 'text', 'text', 'text'],
  'fenced failure boundary exists'
);
select has_function(
  'private', 'requeue_dead_letter', array['uuid', 'text', 'text', 'uuid'],
  'controlled private reprocessing boundary exists'
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
     )
     and procedure.prosecdef
     and owner_role.rolname = 'postgres'
     and exists (
       select 1 from pg_catalog.unnest(coalesce(procedure.proconfig, array[]::text[])) as setting(value)
       where setting.value = 'search_path=""'
     )),
  4::bigint,
  'all public worker boundaries are controlled SECURITY DEFINER functions with empty search_path'
);
select is(
  (select count(*) from information_schema.routine_privileges
   where routine_schema = 'public'
     and routine_name in (
       'claim_outbox_batch', 'read_profile_created_origin',
       'complete_outbox_event', 'fail_outbox_event'
     )
     and grantee = 'cw_worker'),
  4::bigint,
  'dedicated worker role receives only the four explicit technical boundaries'
);
select is(
  (select count(*) from information_schema.routine_privileges
   where routine_schema = 'public'
     and routine_name in (
       'claim_outbox_batch', 'read_profile_created_origin',
       'complete_outbox_event', 'fail_outbox_event'
     )
     and grantee in ('PUBLIC', 'anon', 'authenticated', 'service_role')),
  0::bigint,
  'public clients and service_role have no worker boundary shortcut'
);
select is(
  (select count(*) from information_schema.routine_privileges
   where routine_schema = 'private'
     and routine_name in (
       'assert_current_outbox_lease', 'sanitize_worker_error', 'requeue_dead_letter'
     )
     and grantee in ('PUBLIC', 'anon', 'authenticated', 'service_role', 'cw_worker')),
  0::bigint,
  'private W3D helpers remain inaccessible to client and worker roles'
);
select is(
  (select row(
     rolcanlogin, rolinherit, rolsuper, rolcreatedb,
     rolcreaterole, rolreplication, rolbypassrls
   )::text from pg_catalog.pg_roles where rolname = 'cw_worker'),
  row(false, false, false, false, false, false, false)::text,
  'worker role is no-login no-inherit and has no administrative or RLS bypass attributes'
);
select is(
  (select count(*)
   from pg_catalog.pg_auth_members as membership
   join pg_catalog.pg_roles as granted_role on granted_role.oid = membership.roleid
   join pg_catalog.pg_roles as member_role on member_role.oid = membership.member
   where granted_role.rolname = 'cw_worker'
     and member_role.rolname in ('anon', 'authenticated', 'service_role', 'authenticator')),
  0::bigint,
  'no client-facing or PostgREST role can assume cw_worker'
);

select is(
  (select row(
     consumer_name, handler_name, handler_version, enabled,
     lease_seconds, max_attempts, backoff_base_seconds,
     backoff_max_seconds, jitter_percent
   )::text
   from private.worker_handler_controls
   where event_type = 'authorization.profile.created' and event_version = 1),
  row(
    'cw.authorization.profile_projection', 'authorization_profile_created_v1',
    1, true, 30, 3, 1, 60, 20
  )::text,
  'known event/version has a bounded allowlisted control and kill switch'
);

insert into auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
values (
  '1d000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
  'w3d-manager@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp()
);

create temporary table w3d_tenant as
select * from public.bootstrap_initial_tenant(
  '1d000000-0000-4000-8000-000000000001',
  'W3D Tenant',
  '7d000000-0000-4000-8000-000000000001'
);
grant select on table w3d_tenant to authenticated, cw_worker;

set local "request.jwt.claim.sub" = '1d000000-0000-4000-8000-000000000001';
set local role authenticated;
select * from public.create_tenant_profile(
  'W3D Ack Profile', 'create ack fixture',
  '5d000000-0000-4000-8000-000000000001', 'w3d-command-key-ack-0001'
);
select * from public.create_tenant_profile(
  'W3D Retry Profile', 'create retry fixture',
  '5d000000-0000-4000-8000-000000000002', 'w3d-command-key-retry-0001'
);
select * from public.create_tenant_profile(
  'W3D Kill Profile', 'create kill switch fixture',
  '5d000000-0000-4000-8000-000000000003', 'w3d-command-key-kill-0001'
);
reset role;

create temporary table w3d_events as
select profile.name, event.event_id
from private.outbox_events as event
join public.tenant_profiles as profile on profile.id = event.aggregate_id
where profile.name like 'W3D % Profile';

update private.outbox_events
set next_attempt_at = statement_timestamp() + interval '1 day'
where event_id in (select event_id from w3d_events);
update private.outbox_events
set next_attempt_at = statement_timestamp() - interval '2 seconds'
where event_id = (select event_id from w3d_events where name = 'W3D Ack Profile');
update private.outbox_events
set next_attempt_at = statement_timestamp() - interval '1 second'
where event_id = (select event_id from w3d_events where name = 'W3D Retry Profile');

create temporary table w3d_claims as
select * from public.claim_outbox_batch('local:w3d-shape', 1) with no data;
grant insert, select, delete on table w3d_claims to cw_worker;

-- Invoked by the local migration/test administrator; cw_worker ACL is inventoried above.
insert into w3d_claims select * from public.claim_outbox_batch('local:w3d-worker-a', 1);
reset role;

select is((select count(*) from w3d_claims), 1::bigint, 'batch limit returns exactly one eligible event');
select is(
  (select event_id from w3d_claims),
  (select event_id from w3d_events where name = 'W3D Ack Profile'),
  'claim follows deterministic eligibility and ordering'
);
update private.outbox_events
set next_attempt_at = statement_timestamp() + interval '1 day'
where event_id = (select event_id from w3d_events where name = 'W3D Retry Profile');
select is((select attempt_count from w3d_claims), 1, 'first claim records the first attempt');
select is((select fencing_token from w3d_claims), 1::bigint, 'first claim advances the fence to one');
select ok((select lease_expires_at > statement_timestamp() from w3d_claims), 'claim creates a valid database-time lease');
select ok((select lease_token is not null from w3d_claims), 'claim creates an unpredictable lease token');

create temporary table w3d_steal_probe as
select * from public.claim_outbox_batch('local:w3d-shape', 1) with no data;
grant insert, select on table w3d_steal_probe to cw_worker;
-- Local administrative test invocation of the same narrow boundary.
insert into w3d_steal_probe select * from public.claim_outbox_batch('local:w3d-worker-b', 1);
reset role;
select is((select count(*) from w3d_steal_probe), 0::bigint, 'a valid lease cannot be stolen');

create temporary table w3d_origin (
  authoritative_tenant_id uuid,
  authoritative_profile_id uuid,
  authoritative_profile_version bigint,
  authoritative_profile_status text
);
grant insert, select on table w3d_origin to cw_worker;
-- Local administrative test invocation of the same narrow boundary.
insert into w3d_origin
select * from public.read_profile_created_origin(
  (select event_id from w3d_claims),
  'local:w3d-worker-a',
  (select lease_token from w3d_claims),
  (select fencing_token from w3d_claims)
);
reset role;
select is(
  (select authoritative_tenant_id from w3d_origin),
  (select tenant_id from w3d_tenant),
  'authoritative reread derives tenant from the claimed persisted event'
);
select is(
  (select authoritative_profile_id from w3d_origin),
  (select aggregate_id from w3d_claims),
  'authoritative reread resolves the persisted aggregate instead of trusting payload'
);

select throws_ok(
  $$ update private.outbox_events set payload = '{"profile_version":999}'::jsonb
     where event_id = (select event_id from w3d_claims) $$,
  '55000', 'outbox event fact is immutable',
  'W3D cannot rewrite payload or event fact'
);

create temporary table w3d_fact_before as
select pg_catalog.to_jsonb(event)
  - 'status' - 'attempt_count' - 'next_attempt_at'
  - 'claimed_by' - 'claimed_at' - 'lease_expires_at' - 'lease_token'
  - 'fencing_token' - 'processed_at' - 'last_failed_at'
  - 'dead_lettered_at' - 'last_error_class' - 'last_error_code'
  - 'last_error_message' - 'requeue_count' as fact
from private.outbox_events as event
where event.event_id = (select event_id from w3d_claims);

create temporary table w3d_ack (receipt_id uuid, receipt_replayed boolean);
grant insert, select on table w3d_ack to cw_worker;
-- Local administrative test invocation of the same narrow boundary.
insert into w3d_ack
select * from public.complete_outbox_event(
  (select event_id from w3d_claims), 'local:w3d-worker-a',
  (select lease_token from w3d_claims), (select fencing_token from w3d_claims),
  1, '{"observed_profile_status":"active"}'::jsonb
);
reset role;

select is(
  (select status from private.outbox_events where event_id = (select event_id from w3d_claims)),
  'processed',
  'current worker can acknowledge a claimed event'
);
select is((select receipt_replayed from w3d_ack), false, 'first successful ack records a new handler receipt');
select is(
  (select count(*) from private.event_handler_receipts
   where event_id = (select event_id from w3d_claims)),
  1::bigint,
  'ack records exactly one W3C receipt'
);
select is(
  (select fact from w3d_fact_before),
  (select pg_catalog.to_jsonb(event)
     - 'status' - 'attempt_count' - 'next_attempt_at'
     - 'claimed_by' - 'claimed_at' - 'lease_expires_at' - 'lease_token'
     - 'fencing_token' - 'processed_at' - 'last_failed_at'
     - 'dead_lettered_at' - 'last_error_class' - 'last_error_code'
     - 'last_error_message' - 'requeue_count'
   from private.outbox_events as event
   where event.event_id = (select event_id from w3d_claims)),
  'ack changes only technical delivery state and preserves the Event fact'
);

-- Local administrative test invocation of the same narrow boundary.
select throws_ok(
  format(
    $$ select * from public.complete_outbox_event('%s','local:w3d-worker-a','%s',%s,1,'{}') $$,
    (select event_id from w3d_claims), (select lease_token from w3d_claims),
    (select fencing_token from w3d_claims)
  ),
  'P0001', 'OUTBOX_LEASE_STALE',
  'ack cannot be repeated after claim ownership is gone'
);
reset role;

-- Retry, reclaim, stale fencing, capped attempts and dead-letter.
update private.outbox_events set next_attempt_at = statement_timestamp() - interval '1 second'
where event_id = (select event_id from w3d_events where name = 'W3D Retry Profile');
delete from w3d_claims;
-- Local administrative test invocation of the same narrow boundary.
insert into w3d_claims select * from public.claim_outbox_batch('local:w3d-worker-old', 1);
reset role;

create temporary table w3d_fail (
  delivery_status text,
  next_eligible_at timestamptz,
  applied_backoff_seconds numeric
);
grant insert, select, delete on table w3d_fail to cw_worker;
-- Local administrative test invocation of the same narrow boundary.
insert into w3d_fail
select * from public.fail_outbox_event(
  (select event_id from w3d_claims), 'local:w3d-worker-old',
  (select lease_token from w3d_claims), (select fencing_token from w3d_claims),
  'retryable', 'TEMPORARY_FAILURE', 'Temporary handler failure.'
);
reset role;
select is((select delivery_status from w3d_fail), 'pending', 'retryable failure returns the event to pending');
select ok(
  (select applied_backoff_seconds between 0.8 and 1.2 from w3d_fail),
  'first retry uses base exponential delay within configured jitter bounds'
);
select is(
  (select last_error_class from private.outbox_events where event_id = (select event_id from w3d_claims)),
  'retryable',
  'retry stores only the controlled failure classification'
);

delete from w3d_steal_probe;
-- Local administrative test invocation of the same narrow boundary.
insert into w3d_steal_probe select * from public.claim_outbox_batch('local:w3d-worker-new', 1);
reset role;
select is((select count(*) from w3d_steal_probe), 0::bigint, 'retry is not eligible before next_attempt_at');

update private.outbox_events
set next_attempt_at = statement_timestamp() - interval '1 second'
where event_id = (select event_id from w3d_claims);
delete from w3d_steal_probe;
-- Local administrative test invocation of the same narrow boundary.
insert into w3d_steal_probe select * from public.claim_outbox_batch('local:w3d-worker-new', 1);
reset role;
select is((select fencing_token from w3d_steal_probe), 2::bigint, 'reclaim advances the fencing token monotonically');
select is((select attempt_count from w3d_steal_probe), 2, 'reclaim increments the bounded attempt count');

-- Local administrative test invocation of the same narrow boundary.
select throws_ok(
  format(
    $$ select * from public.complete_outbox_event('%s','local:w3d-worker-old','%s',%s,1,'{}') $$,
    (select event_id from w3d_claims), (select lease_token from w3d_claims),
    (select fencing_token from w3d_claims)
  ),
  'P0001', 'OUTBOX_LEASE_STALE',
  'stale worker cannot ack after a newer fence exists'
);
select throws_ok(
  format(
    $$ select * from public.fail_outbox_event('%s','local:w3d-worker-old','%s',%s,'retryable','STALE','Stale worker.') $$,
    (select event_id from w3d_claims), (select lease_token from w3d_claims),
    (select fencing_token from w3d_claims)
  ),
  'P0001', 'OUTBOX_LEASE_STALE',
  'stale worker cannot fail after a newer fence exists'
);
reset role;

delete from w3d_fail;
-- Local administrative test invocation of the same narrow boundary.
insert into w3d_fail
select * from public.fail_outbox_event(
  (select event_id from w3d_steal_probe), 'local:w3d-worker-new',
  (select lease_token from w3d_steal_probe), (select fencing_token from w3d_steal_probe),
  'retryable', 'TEMPORARY_FAILURE', 'Temporary handler failure.'
);
reset role;
select ok(
  (select applied_backoff_seconds between 1.6 and 2.4 from w3d_fail),
  'second retry doubles the base delay and stays within jitter bounds'
);

update private.outbox_events set next_attempt_at = statement_timestamp() - interval '1 second'
where event_id = (select event_id from w3d_steal_probe);
delete from w3d_claims;
-- Local administrative test invocation of the same narrow boundary.
insert into w3d_claims select * from public.claim_outbox_batch('local:w3d-worker-final', 1);
delete from w3d_fail;
insert into w3d_fail
select * from public.fail_outbox_event(
  (select event_id from w3d_claims), 'local:w3d-worker-final',
  (select lease_token from w3d_claims), (select fencing_token from w3d_claims),
  'retryable', 'TEMPORARY_FAILURE', 'Temporary handler failure.'
);
reset role;
select is((select delivery_status from w3d_fail), 'dead_letter', 'retry at max attempts becomes terminal dead-letter');
select is(
  (select last_error_class from private.outbox_events where event_id = (select event_id from w3d_claims)),
  'attempts_exhausted',
  'attempt limit records the stable exhausted classification'
);

delete from w3d_steal_probe;
-- Local administrative test invocation of the same narrow boundary.
insert into w3d_steal_probe select * from public.claim_outbox_batch('local:w3d-worker-after-dead', 100);
reset role;
select is(
  (select count(*) from w3d_steal_probe where event_id = (select event_id from w3d_claims)),
  0::bigint,
  'dead-letter stops automatic processing'
);

create temporary table w3d_dead_fact as
select pg_catalog.to_jsonb(event)
  - 'status' - 'attempt_count' - 'next_attempt_at'
  - 'claimed_by' - 'claimed_at' - 'lease_expires_at' - 'lease_token'
  - 'fencing_token' - 'processed_at' - 'last_failed_at'
  - 'dead_lettered_at' - 'last_error_class' - 'last_error_code'
  - 'last_error_message' - 'requeue_count' as fact
from private.outbox_events as event
where event.event_id = (select event_id from w3d_claims);

select lives_ok(
  format(
    $$ select private.requeue_dead_letter('%s','technical:w3d-operator','approved local reprocessing','5d000000-0000-4000-8000-000000000099') $$,
    (select event_id from w3d_claims)
  ),
  'controlled reprocessing accepts technical actor reason and correlation'
);
select is(
  (select row(status, attempt_count, requeue_count)::text
   from private.outbox_events where event_id = (select event_id from w3d_claims)),
  row('pending', 3, 1)::text,
  'reprocessing preserves prior attempts and opens one new bounded attempt cycle'
);
select is(
  (select count(*) from public.audit_events
   where event_type = 'infrastructure.outbox.requeued'
     and entity_id = (select event_id from w3d_claims)
     and reason = 'approved local reprocessing'),
  1::bigint,
  'reprocessing is explicitly audited'
);
select is(
  (select fact from w3d_dead_fact),
  (select pg_catalog.to_jsonb(event)
     - 'status' - 'attempt_count' - 'next_attempt_at'
     - 'claimed_by' - 'claimed_at' - 'lease_expires_at' - 'lease_token'
     - 'fencing_token' - 'processed_at' - 'last_failed_at'
     - 'dead_lettered_at' - 'last_error_class' - 'last_error_code'
     - 'last_error_message' - 'requeue_count'
   from private.outbox_events as event
   where event.event_id = (select event_id from w3d_claims)),
  'reprocessing never alters the persisted Event fact'
);

delete from w3d_claims;
-- Local administrative test invocation of the same narrow boundary.
insert into w3d_claims select * from public.claim_outbox_batch('local:w3d-reprocess-worker', 1);
delete from w3d_fail;
insert into w3d_fail
select * from public.fail_outbox_event(
  (select event_id from w3d_claims), 'local:w3d-reprocess-worker',
  (select lease_token from w3d_claims), (select fencing_token from w3d_claims),
  'non_retryable', 'REPROCESS_REJECTED', 'Controlled reprocessing probe stopped.'
);
reset role;
select is((select attempt_count from w3d_claims), 4, 'reprocessing creates a new attempt without resetting prior counters');
select is((select delivery_status from w3d_fail), 'dead_letter', 'non-retryable failure returns reprocessed work to dead-letter');

-- Kill switch blocks claim and reprocessing without becoming event authority.
update private.worker_handler_controls
set enabled = false, updated_at = statement_timestamp()
where event_type = 'authorization.profile.created' and event_version = 1;
update private.outbox_events set next_attempt_at = statement_timestamp() - interval '1 second'
where event_id = (select event_id from w3d_events where name = 'W3D Kill Profile');
delete from w3d_steal_probe;
-- Local administrative test invocation of the same narrow boundary.
insert into w3d_steal_probe select * from public.claim_outbox_batch('local:w3d-worker-disabled', 100);
reset role;
select is((select count(*) from w3d_steal_probe), 0::bigint, 'disabled handler kill switch blocks new claims');
select throws_ok(
  format(
    $$ select private.requeue_dead_letter('%s','technical:w3d-operator','blocked while handler disabled','5d000000-0000-4000-8000-000000000098') $$,
    (select event_id from w3d_claims)
  ),
  'P0001', 'OUTBOX_HANDLER_DISABLED',
  'kill switch blocks controlled reprocessing while the handler is disabled'
);
update private.worker_handler_controls
set enabled = true, updated_at = statement_timestamp()
where event_type = 'authorization.profile.created' and event_version = 1;

-- Unknown contract is terminal without being executed or copied elsewhere.
select private.enqueue_event(
  (select tenant_id from w3d_tenant), 'authorization.profile.created',
  'system', 'system', pg_catalog.gen_random_uuid(),
  '5d000000-0000-4000-8000-000000000097',
  null, null, 999, null, null, 'system:w3d-test', null, '{}', '{}'
);
-- Local administrative test invocation of the same narrow boundary.
select count(*) from public.claim_outbox_batch('local:w3d-worker-unknown', 100);
reset role;
select is(
  (select count(*) from private.outbox_events
   where event_type = 'authorization.profile.created'
     and event_version = 999
     and status = 'dead_letter'
     and last_error_class = 'unsupported_event'),
  1::bigint,
  'unsupported event/version becomes terminal without dynamic dispatch'
);

set local role authenticated;
select throws_ok($$ select * from public.claim_outbox_batch('forged:client', 1) $$, '42501', null, 'authenticated cannot claim events');
select throws_ok($$ select * from private.worker_handler_controls $$, '42501', null, 'authenticated cannot read kill switches');
reset role;
set local role service_role;
select throws_ok($$ select * from public.claim_outbox_batch('forged:service', 1) $$, '42501', null, 'service_role has no worker shortcut');
reset role;

select is(
  private.sanitize_worker_error('Temporary upstream timeout while reading profile.'),
  'Temporary upstream timeout while reading profile.',
  'worker error sanitizer preserves useful operational text'
);
select is(
  private.sanitize_worker_error('Authorization: Bearer synthetic-token-value'),
  'Sensitive worker error details were redacted.',
  'worker error sanitizer redacts a Bearer credential'
);
select is(
  private.sanitize_worker_error('eyJhbGciOiJub25lIn0.eyJzdWIiOiJzeW50aGV0aWMifQ.synthetic-signature'),
  'Sensitive worker error details were redacted.',
  'worker error sanitizer redacts a raw JWT-shaped value'
);
select is(
  private.sanitize_worker_error('https://storage.example.invalid/object?X-Amz-Signature=synthetic-signature'),
  'Sensitive worker error details were redacted.',
  'worker error sanitizer redacts a generic signed URL query credential'
);
select is(
  private.sanitize_worker_error('https://api.example.invalid/callback?access_token=synthetic-access'),
  'Sensitive worker error details were redacted.',
  'worker error sanitizer redacts access_token query values'
);
select is(
  private.sanitize_worker_error('refresh_token=synthetic-refresh'),
  'Sensitive worker error details were redacted.',
  'worker error sanitizer redacts refresh_token values'
);
select is(
  private.sanitize_worker_error('id_token: synthetic-id'),
  'Sensitive worker error details were redacted.',
  'worker error sanitizer redacts id_token values'
);
select is(
  private.sanitize_worker_error('api_key=synthetic-api-key'),
  'Sensitive worker error details were redacted.',
  'worker error sanitizer redacts api_key values'
);
select is(
  private.sanitize_worker_error('apikey: synthetic-apikey'),
  'Sensitive worker error details were redacted.',
  'worker error sanitizer redacts apikey values'
);
select is(
  private.sanitize_worker_error('authorization=synthetic-authorization'),
  'Sensitive worker error details were redacted.',
  'worker error sanitizer redacts authorization values'
);
select is(
  private.sanitize_worker_error('token=synthetic-token'),
  'Sensitive worker error details were redacted.',
  'worker error sanitizer redacts generic token values'
);
select is(
  private.sanitize_worker_error('signature=synthetic-signature'),
  'Sensitive worker error details were redacted.',
  'worker error sanitizer redacts signature values'
);
select is(
  private.sanitize_worker_error('sig=synthetic-sig'),
  'Sensitive worker error details were redacted.',
  'worker error sanitizer redacts sig values'
);
select is(
  private.sanitize_worker_error('secret=synthetic-secret'),
  'Sensitive worker error details were redacted.',
  'worker error sanitizer redacts secret values'
);
select is(
  private.sanitize_worker_error('password=synthetic-password'),
  'Sensitive worker error details were redacted.',
  'worker error sanitizer redacts password values'
);
select is(
  private.sanitize_worker_error('passwd: synthetic-passwd'),
  'Sensitive worker error details were redacted.',
  'worker error sanitizer redacts passwd values'
);
select throws_ok(
  $$ select private.sanitize_worker_error(repeat('x', 501)) $$,
  '22023', 'UNSAFE_WORKER_ERROR',
  'worker error sanitizer keeps the 500 character boundary fail-closed'
);
select is(
  private.sanitize_worker_error('Token bucket exhausted; signature validation failed during secret rotation.'),
  'Token bucket exhausted; signature validation failed during secret rotation.',
  'similar non-sensitive operational wording remains usable'
);

select * from finish();
rollback;
