import { randomUUID } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { spawnSync } from 'node:child_process'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const config = readFileSync(path.join(projectRoot, 'supabase', 'config.toml'), 'utf8')
const projectId = /^project_id\s*=\s*"([a-z0-9-]+)"\s*$/mu.exec(config)?.[1]
if (projectId === undefined) throw new Error('W3E_ADVERSARIAL_BLOCKER: projeto local ausente.')

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
const redactedMessage = 'Sensitive worker error details were redacted.'

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
  return result
}

function output(result) {
  return result.stdout.trim()
}

function sqlLiteral(value) {
  return `'${value.replaceAll("'", "''")}'`
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

function createClaimedEvent(sourceProfile, workerIdentity) {
  const eventId = output(run(`
    select private.enqueue_event(
      '${tenantId}', 'authorization.profile.created', 'system', 'system',
      gen_random_uuid(), gen_random_uuid(), 'tenant_profile', '${sourceProfile}', 1, 1,
      null, 'system:w3e-adversarial-test', null, '{"profile_version":1}', '{}'
    );
  `))
  const claim = output(run(`
    set role cw_worker;
    select event_id::text || '|' || lease_token::text || '|' || fencing_token::text
    from public.claim_outbox_batch('${workerIdentity}', 1);
  `)).split('|')
  if (claim[0] !== eventId || claim.length !== 3) {
    throw new Error(`W3E claim mismatch for ${workerIdentity}`)
  }
  return { eventId, leaseToken: claim[1], fencingToken: claim[2] }
}

function failAndRead(sourceProfile, failureCode, failureMessage) {
  const workerIdentity = `local:w3e-${failureCode.toLowerCase().replaceAll('_', '-')}`
  const claim = createClaimedEvent(sourceProfile, workerIdentity)
  run(`
    set role cw_worker;
    select * from public.fail_outbox_event(
      '${claim.eventId}', '${workerIdentity}', '${claim.leaseToken}', ${claim.fencingToken},
      'non_retryable', '${failureCode}', ${sqlLiteral(failureMessage)}
    );
  `)
  return output(run(`
    select coalesce(last_error_message, '<NULL>')
    from private.outbox_events where event_id = '${claim.eventId}';
  `))
}

try {
  run(`
    insert into auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
    values ('${actorId}', 'authenticated', 'authenticated',
      'w3e-${suffix}@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp());
    insert into public.tenants (id, tenant_ref, display_name, status, created_by)
    values ('${tenantId}', '${tenantRef}', 'W3E Adversarial ${suffix}', 'active', '${actorId}');
    select * from private.provision_tenant_authorization('${tenantId}', null, '${actorId}', '${randomUUID()}');
    insert into public.tenant_memberships (
      tenant_id, user_id, status, joined_at, created_by,
      profile_id, profile_assigned_at, profile_assigned_by
    )
    select '${tenantId}', '${actorId}', 'active', statement_timestamp(), '${actorId}',
      profile.id, statement_timestamp(), '${actorId}'
    from public.tenant_profiles as profile
    where profile.tenant_id = '${tenantId}' and profile.template_key = 'manager';
  `)

  const sourceProfile = output(run(`
    select id from public.tenant_profiles
    where tenant_id = '${tenantId}' and template_key = 'manager';
  `))
  if (sourceProfile.length === 0) throw new Error('W3E source profile fixture missing')

  const safeMessage = 'Temporary upstream timeout while reading authoritative profile.'
  if (failAndRead(sourceProfile, 'SAFE_OPERATIONAL', safeMessage) !== safeMessage) {
    throw new Error('safe operational error was not preserved')
  }

  const sensitiveMessages = [
    ['SYNTHETIC_BEARER', 'Authorization: Bearer synthetic-token-value'],
    ['SYNTHETIC_JWT', syntheticJwt],
    ['SYNTHETIC_SIGNED_URL', 'https://files.example.invalid/object?X-Goog-Signature=synthetic-signature'],
    ['SYNTHETIC_ACCESS_TOKEN', 'https://api.example.invalid/callback?access_token=synthetic-access'],
    ['SYNTHETIC_REFRESH_TOKEN', 'refresh_token=synthetic-refresh'],
    ['SYNTHETIC_API_KEY', 'api_key=synthetic-api-key'],
    ['SYNTHETIC_APIKEY', 'apikey=synthetic-apikey'],
    ['SYNTHETIC_SIGNATURE', 'signature=synthetic-signature'],
    ['SYNTHETIC_SIG', 'sig=synthetic-sig'],
    ['SYNTHETIC_SECRET', 'secret=synthetic-secret'],
    ['SYNTHETIC_PASSWORD', 'password=synthetic-password'],
    ['SYNTHETIC_DUMP', 'stack trace: synthetic database dump content'],
  ]

  for (const [failureCode, failureMessage] of sensitiveMessages) {
    const stored = failAndRead(sourceProfile, failureCode, failureMessage)
    if (stored !== redactedMessage || stored.includes('synthetic')) {
      throw new Error(`sensitive material persisted through fail_outbox_event for ${failureCode}: ${stored}`)
    }
  }

  const oversizedClaim = createClaimedEvent(sourceProfile, 'local:w3e-oversized')
  const oversized = run(`
    set role cw_worker;
    select * from public.fail_outbox_event(
      '${oversizedClaim.eventId}', 'local:w3e-oversized', '${oversizedClaim.leaseToken}',
      ${oversizedClaim.fencingToken}, 'non_retryable', 'OVERSIZED', repeat('x', 501)
    );
  `, true)
  if (oversized.status === 0 || !oversized.stderr.includes('UNSAFE_WORKER_ERROR')) {
    throw new Error('oversized worker error did not fail closed')
  }
  const oversizedState = output(run(`
    select status || '|' || coalesce(last_error_message, '<NULL>')
    from private.outbox_events where event_id = '${oversizedClaim.eventId}';
  `))
  if (oversizedState !== 'processing|<NULL>') {
    throw new Error(`oversized error mutated authoritative state: ${oversizedState}`)
  }

  const directMutation = run(`
    set role cw_worker;
    update private.outbox_events set status = 'processed'
    where event_id = '${oversizedClaim.eventId}';
  `, true)
  if (directMutation.status === 0 || !directMutation.stderr.toLowerCase().includes('permission denied')) {
    throw new Error('cw_worker unexpectedly bypassed the fenced delivery boundaries')
  }

  process.stdout.write(
    'W3E_ADVERSARIAL_OK: real fail_outbox_event path preserved safe text, redacted all synthetic credential classes and dump-like content, rejected >500 characters without state mutation, and denied direct worker state overwrite.\n',
  )
} finally {
  cleanup()
}
