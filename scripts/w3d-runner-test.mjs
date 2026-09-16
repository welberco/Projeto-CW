import { randomUUID } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { spawnSync } from 'node:child_process'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { processOnce } from './w3d-local-runner.mjs'

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const config = readFileSync(path.join(projectRoot, 'supabase', 'config.toml'), 'utf8')
const projectId = /^project_id\s*=\s*"([a-z0-9-]+)"\s*$/mu.exec(config)?.[1]
if (projectId === undefined) throw new Error('W3D_RUNNER_TEST_BLOCKER: projeto local ausente.')

const containerName = `supabase_db_${projectId}`
const suffix = randomUUID().replaceAll('-', '')
const actorId = randomUUID()
const tenantId = randomUUID()
const tenantRef = randomUUID()
const syntheticJwt = [
  'eyJhbGciOiJub25lIn0',
  'eyJzdWIiOiJzeW50aGV0aWMifQ',
  'synthetic-signature',
].join('.')

function run(sql, allowFailure = false) {
  const result = spawnSync(
    'docker',
    [
      'exec', '-i', containerName, 'psql', '-X', '-q', '-A', '-t',
      '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres', '-c', sql,
    ],
    { cwd: projectRoot, encoding: 'utf8', stdio: 'pipe' },
  )
  if (!allowFailure && (result.error !== undefined || result.status !== 0)) {
    throw new Error(result.error?.message ?? result.stderr.trim())
  }
  return result.stdout.trim()
}

function cleanup() {
  run(`
    set session_replication_role = replica;
    delete from private.event_handler_receipts where tenant_id = '${tenantId}';
    delete from private.command_idempotency where tenant_id = '${tenantId}';
    delete from private.outbox_events where tenant_id = '${tenantId}';
    delete from public.history_entries where tenant_id = '${tenantId}';
    delete from public.audit_events where tenant_id = '${tenantId}';
    delete from public.tenant_permission_overrides where tenant_id = '${tenantId}';
    delete from public.tenant_profile_permissions where tenant_id = '${tenantId}';
    delete from public.tenant_memberships where tenant_id = '${tenantId}';
    delete from public.tenant_profiles where tenant_id = '${tenantId}';
    delete from public.tenant_entitlements where tenant_id = '${tenantId}';
    delete from public.tenants where id = '${tenantId}';
    delete from public.app_users where id = '${actorId}';
    delete from auth.users where id = '${actorId}';
    set session_replication_role = origin;
  `, true)
}

function makeEligible(eventId) {
  run(`update private.outbox_events set next_attempt_at = statement_timestamp() - interval '1 second' where event_id = '${eventId}';`)
}

function eventState(eventId) {
  return run(`select status || '|' || attempt_count || '|' || (select count(*) from private.event_handler_receipts where event_id = '${eventId}') from private.outbox_events where event_id = '${eventId}';`)
}

function sqlLiteral(value) {
  return `'${value.replaceAll("'", "''")}'`
}

function failThroughWorkerBoundary(sourceProfile, failureCode, failureMessage) {
  const eventId = run(`
    select private.enqueue_event(
      '${tenantId}', 'authorization.profile.created', 'system', 'system',
      gen_random_uuid(), gen_random_uuid(), 'tenant_profile', '${sourceProfile}', 1, 1,
      null, 'system:w3d-sanitization-test', null, '{}', '{}'
    );
  `)
  makeEligible(eventId)

  const [claimedEventId, leaseToken, fencingToken] = run(`
    set role cw_worker;
    select event_id::text || '|' || lease_token::text || '|' || fencing_token::text
    from public.claim_outbox_batch('local:w3d-sanitization-worker', 1);
  `).split('|')
  if (claimedEventId !== eventId || !leaseToken || !fencingToken) {
    throw new Error('sanitization fixture was not claimed by the worker boundary')
  }

  run(`
    set role cw_worker;
    select * from public.fail_outbox_event(
      '${eventId}', 'local:w3d-sanitization-worker', '${leaseToken}', ${fencingToken},
      'non_retryable', '${failureCode}', ${sqlLiteral(failureMessage)}
    );
  `)

  return run(`select last_error_message from private.outbox_events where event_id = '${eventId}';`)
}

try {
  run(`
    insert into auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
    values ('${actorId}', 'authenticated', 'authenticated',
      'w3d-runner-${suffix}@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp());
    insert into public.tenants (id, tenant_ref, display_name, status, created_by)
    values ('${tenantId}', '${tenantRef}', 'W3D Runner ${suffix}', 'active', '${actorId}');
    select * from private.provision_tenant_authorization('${tenantId}', null, '${actorId}', '${randomUUID()}');
    insert into public.tenant_memberships (
      tenant_id, user_id, status, joined_at, created_by,
      profile_id, profile_assigned_at, profile_assigned_by
    )
    select '${tenantId}', '${actorId}', 'active', statement_timestamp(), '${actorId}',
      profile.id, statement_timestamp(), '${actorId}'
    from public.tenant_profiles as profile
    where profile.tenant_id = '${tenantId}' and profile.template_key = 'manager';
    begin;
    set local "request.jwt.claim.sub" = '${actorId}';
    set local role authenticated;
    select * from public.create_tenant_profile('W3D Runner Success ${suffix}','runner success','${randomUUID()}','w3d-runner-success-${suffix}');
    select * from public.create_tenant_profile('W3D Runner Retry ${suffix}','runner retry','${randomUUID()}','w3d-runner-retry-${suffix}');
    select * from public.create_tenant_profile('W3D Runner Dead ${suffix}','runner dead','${randomUUID()}','w3d-runner-dead-${suffix}');
    commit;
    update private.outbox_events set next_attempt_at = statement_timestamp() + interval '1 day' where tenant_id = '${tenantId}';
  `)

  const ids = Object.fromEntries(
    run(`
      select split_part(profile.name, ' ', 3) || '|' || event.event_id
      from private.outbox_events as event
      join public.tenant_profiles as profile on profile.id = event.aggregate_id
      where event.tenant_id = '${tenantId}' order by profile.name;
    `).split(/\r?\n/u).map((line) => line.split('|')),
  )
  const successId = ids.Success
  const retryId = ids.Retry
  const deadId = ids.Dead
  if (![successId, retryId, deadId].every(Boolean)) throw new Error('runner fixtures ausentes')

  makeEligible(successId)
  const success = await processOnce({ workerIdentity: 'local:w3d-runner-success', batchSize: 1 })
  if (JSON.stringify(success) !== JSON.stringify({ claimed: 1, processed: 1, failed: 0, replayed: 0 })) {
    throw new Error(`runner success inesperado: ${JSON.stringify(success)}`)
  }
  if (eventState(successId) !== 'processed|1|1') throw new Error('runner não persistiu receipt + ack')

  makeEligible(retryId)
  const retryFailure = await processOnce({
    workerIdentity: 'local:w3d-runner-retry-a', batchSize: 1,
    failureInjectionEventIds: new Set([retryId]),
  })
  if (retryFailure.failed !== 1 || eventState(retryId) !== 'pending|1|0') {
    throw new Error('runner não registrou retry sem receipt')
  }
  makeEligible(retryId)
  const retrySuccess = await processOnce({ workerIdentity: 'local:w3d-runner-retry-b', batchSize: 1 })
  if (retrySuccess.processed !== 1 || eventState(retryId) !== 'processed|2|1') {
    throw new Error('runner não convergiu de retry para sucesso')
  }

  for (let attempt = 1; attempt <= 3; attempt += 1) {
    makeEligible(deadId)
    await processOnce({
      workerIdentity: `local:w3d-runner-dead-${attempt}`,
      batchSize: 1,
      failureInjectionEventIds: new Set([deadId]),
    })
  }
  if (eventState(deadId) !== 'dead_letter|3|0') throw new Error('runner não respeitou max attempts')
  const afterDead = await processOnce({ workerIdentity: 'local:w3d-runner-after-dead', batchSize: 1 })
  if (afterDead.claimed !== 0) throw new Error('runner reclamou dead-letter automaticamente')

  const sourceProfile = run(`select aggregate_id from private.outbox_events where event_id = '${successId}';`)
  const poisonId = run(`
    select private.enqueue_event(
      '${tenantId}', 'authorization.profile.created', 'system', 'system',
      gen_random_uuid(), gen_random_uuid(), 'tenant_profile', '${sourceProfile}', 1, 1,
      null, 'system:w3d-runner-test', null, '{}', '{}'
    );
  `)
  const poison = await processOnce({ workerIdentity: 'local:w3d-runner-poison', batchSize: 1 })
  if (poison.failed !== 1 || eventState(poisonId) !== 'dead_letter|1|0') {
    throw new Error('runner não classificou poison event como terminal')
  }

  const normalMessage = 'Temporary upstream timeout while reading profile.'
  if (failThroughWorkerBoundary(sourceProfile, 'SAFE_OPERATIONAL', normalMessage) !== normalMessage) {
    throw new Error('worker boundary did not preserve safe operational text')
  }

  const redactedMessage = 'Sensitive worker error details were redacted.'
  const sensitiveMessages = [
    ['SYNTHETIC_BEARER', 'Authorization: Bearer synthetic-token-value'],
    ['SYNTHETIC_JWT', syntheticJwt],
    ['SYNTHETIC_SIGNED_URL', 'https://storage.example.invalid/object?X-Amz-Signature=synthetic-signature'],
    ['SYNTHETIC_ACCESS_TOKEN', 'https://api.example.invalid/callback?access_token=synthetic-access'],
    ['SYNTHETIC_API_KEY', 'api_key=synthetic-api-key'],
    ['SYNTHETIC_SIGNATURE', 'signature=synthetic-signature'],
    ['SYNTHETIC_SECRET', 'secret=synthetic-secret'],
    ['SYNTHETIC_PASSWORD', 'password=synthetic-password'],
  ]
  for (const [failureCode, failureMessage] of sensitiveMessages) {
    const stored = failThroughWorkerBoundary(sourceProfile, failureCode, failureMessage)
    if (stored !== redactedMessage || stored.includes('synthetic')) {
      throw new Error(`worker boundary persisted sensitive material for ${failureCode}`)
    }
  }

  process.stdout.write(
    'W3D_RUNNER_OK: claim-handler-authoritative reread-receipt-ack, retry-success, attempt exhaustion, dead-letter stop, poison event and direct persisted error sanitization verified locally.\n',
  )
} finally {
  cleanup()
}
