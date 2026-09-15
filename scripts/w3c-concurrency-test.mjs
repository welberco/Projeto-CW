import { randomUUID } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { spawn, spawnSync } from 'node:child_process'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const config = readFileSync(path.join(projectRoot, 'supabase', 'config.toml'), 'utf8')
const projectId = /^project_id\s*=\s*"([a-z0-9-]+)"\s*$/mu.exec(config)?.[1]

if (projectId === undefined) {
  fail('W3C_CONCURRENCY_BLOCKER: projeto Supabase local não identificado.')
}

const containerName = `supabase_db_${projectId}`
const suffix = randomUUID().replaceAll('-', '')
const actorId = randomUUID()
const tenantId = randomUUID()
const tenantRef = randomUUID()
const key = `w3c-race-${suffix}`
const profileName = `W3C Race ${suffix}`
const firstCorrelation = randomUUID()
const secondCorrelation = randomUUID()

function fail(message) {
  process.stderr.write(`${message}\n`)
  process.exit(1)
}

function psqlArgs(sql) {
  return [
    'exec',
    '-i',
    containerName,
    'psql',
    '-X',
    '-q',
    '-A',
    '-t',
    '-v',
    'ON_ERROR_STOP=1',
    '-U',
    'postgres',
    '-d',
    'postgres',
    '-c',
    sql,
  ]
}

function runPsql(sql) {
  const result = spawnSync('docker', psqlArgs(sql), {
    cwd: projectRoot,
    encoding: 'utf8',
    stdio: 'pipe',
  })

  if (result.error !== undefined || result.status !== 0) {
    fail(
      `W3C_CONCURRENCY_BLOCKER: consulta PostgreSQL local falhou: ${
        result.error?.message ?? result.stderr.trim()
      }`,
    )
  }

  return result.stdout.trim()
}

function runPsqlAsync(sql) {
  return new Promise((resolve, reject) => {
    const child = spawn('docker', psqlArgs(sql), {
      cwd: projectRoot,
      stdio: ['ignore', 'pipe', 'pipe'],
    })
    let stdout = ''
    let stderr = ''

    child.stdout.setEncoding('utf8')
    child.stderr.setEncoding('utf8')
    child.stdout.on('data', (chunk) => {
      stdout += chunk
    })
    child.stderr.on('data', (chunk) => {
      stderr += chunk
    })
    child.on('error', reject)
    child.on('close', (code) => {
      if (code === 0) {
        resolve(stdout.trim())
        return
      }
      reject(new Error(stderr.trim() || `psql exited with code ${code}`))
    })
  })
}

const runningContainer = spawnSync(
  'docker',
  ['inspect', '--format', '{{.State.Running}}', containerName],
  { cwd: projectRoot, encoding: 'utf8', stdio: 'pipe' },
)

if (runningContainer.status !== 0 || runningContainer.stdout.trim() !== 'true') {
  fail('W3C_CONCURRENCY_BLOCKER: PostgreSQL do Supabase LOCAL não está em execução.')
}

runPsql(`
  insert into auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
  values (
    '${actorId}', 'authenticated', 'authenticated',
    'w3c-race-${suffix}@example.invalid',
    statement_timestamp(), statement_timestamp(), statement_timestamp()
  );
  insert into public.tenants (id, tenant_ref, display_name, status, created_by)
  values (
    '${tenantId}', '${tenantRef}', 'W3C Race Tenant ${suffix}', 'active', '${actorId}'
  );
  select * from private.provision_tenant_authorization(
    '${tenantId}', null, '${actorId}', '${randomUUID()}'
  );
  insert into public.tenant_memberships (
    tenant_id, user_id, status, joined_at, created_by,
    profile_id, profile_assigned_at, profile_assigned_by
  )
  select
    '${tenantId}', '${actorId}', 'active', statement_timestamp(), '${actorId}',
    profile.id, statement_timestamp(), '${actorId}'
  from public.tenant_profiles as profile
  where profile.tenant_id = '${tenantId}' and profile.template_key = 'manager';
`)

function concurrentCommand(correlationId) {
  return `
    begin;
    set local "request.jwt.claim.sub" = '${actorId}';
    set local role authenticated;
    select profile_id::text || '|' || profile_version::text || '|' || command_correlation_id::text
    from public.create_tenant_profile(
      '${profileName}', 'prove concurrent command idempotency', '${correlationId}', '${key}'
    );
    select pg_catalog.pg_sleep(1);
    commit;
  `
}

const firstRequest = runPsqlAsync(concurrentCommand(firstCorrelation))
await new Promise((resolve) => setTimeout(resolve, 100))
const secondRequest = runPsqlAsync(concurrentCommand(secondCorrelation))

let outputs
try {
  outputs = await Promise.all([firstRequest, secondRequest])
} catch (error) {
  fail(`W3C_CONCURRENCY_FAIL: ${error instanceof Error ? error.message : String(error)}`)
}

const stableResults = outputs.map((output) =>
  output
    .split(/\r?\n/u)
    .map((line) => line.trim())
    .find((line) => /^[0-9a-f-]{36}\|[1-9][0-9]*\|[0-9a-f-]{36}$/u.test(line)),
)

if (
  stableResults[0] === undefined ||
  stableResults[1] === undefined ||
  stableResults[0] !== stableResults[1]
) {
  fail('W3C_CONCURRENCY_FAIL: requisições concorrentes não retornaram o mesmo resultado estável.')
}

const counts = runPsql(`
  select
    (select count(*) from public.tenant_profiles where name = '${profileName}'),
    (select count(*) from private.command_idempotency where idempotency_key_hash = private.semantic_fingerprint(pg_catalog.to_jsonb('${key}'::text))),
    (select count(*) from public.audit_events where command_id = (
      select command_id from private.command_idempotency where idempotency_key_hash = private.semantic_fingerprint(pg_catalog.to_jsonb('${key}'::text))
    )),
    (select count(*) from private.outbox_events where command_id = (
      select command_id from private.command_idempotency where idempotency_key_hash = private.semantic_fingerprint(pg_catalog.to_jsonb('${key}'::text))
    )),
    (select count(*) from public.history_entries where command_id = (
      select command_id from private.command_idempotency where idempotency_key_hash = private.semantic_fingerprint(pg_catalog.to_jsonb('${key}'::text))
    ));
`)

if (counts !== '1|1|1|1|0') {
  fail(`W3C_CONCURRENCY_FAIL: efeitos concorrentes inesperados (${counts}).`)
}

runPsql(`
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
`)

process.stdout.write(
  'W3C_CONCURRENCY_OK: 2 requests, 1 mutation, 1 idempotency row, 1 Audit, 1 Event, 0 History duplicates.\n',
)
