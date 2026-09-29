import { randomUUID } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { spawn, spawnSync } from 'node:child_process'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const config = readFileSync(path.join(projectRoot, 'supabase', 'config.toml'), 'utf8')
const projectId = /^project_id\s*=\s*"([a-z0-9-]+)"\s*$/mu.exec(config)?.[1]

function fail(message) {
  process.stderr.write(`${message}\n`)
  process.exit(1)
}

if (projectId === undefined) {
  fail('W5A_CONCURRENCY_BLOCKER: projeto Supabase local não identificado.')
}

const containerName = `supabase_db_${projectId}`
const suffix = randomUUID().replaceAll('-', '')
const actorId = randomUUID()
const membershipId = randomUUID()
const tenantId = randomUUID()
const tenantRef = randomUUID()
const overrideId = randomUUID()

function dockerArgs(sql) {
  return [
    'exec', '-i', containerName,
    'psql', '-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1',
    '-U', 'postgres', '-d', 'postgres', '-c', sql,
  ]
}

function run(sql) {
  const result = spawnSync('docker', dockerArgs(sql), {
    cwd: projectRoot,
    encoding: 'utf8',
    stdio: 'pipe',
  })
  if (result.error !== undefined || result.status !== 0) {
    fail(`W5A_CONCURRENCY_BLOCKER: ${result.error?.message ?? result.stderr.trim()}`)
  }
  return result.stdout.trim()
}

function runAsync(sql) {
  return new Promise((resolve, reject) => {
    const child = spawn('docker', dockerArgs(sql), {
      cwd: projectRoot,
      stdio: ['ignore', 'pipe', 'pipe'],
    })
    let output = ''
    let errorOutput = ''
    child.stdout.setEncoding('utf8')
    child.stderr.setEncoding('utf8')
    child.stdout.on('data', (chunk) => { output += chunk })
    child.stderr.on('data', (chunk) => { errorOutput += chunk })
    child.on('error', reject)
    child.on('close', (code) => {
      if (code === 0) resolve(output.trim())
      else reject(new Error(errorOutput.trim() || `psql exited ${code}`))
    })
  })
}

const running = spawnSync(
  'docker',
  ['inspect', '--format', '{{.State.Running}}', containerName],
  { cwd: projectRoot, encoding: 'utf8', stdio: 'pipe' },
)
if (running.status !== 0 || running.stdout.trim() !== 'true') {
  fail('W5A_CONCURRENCY_BLOCKER: PostgreSQL do Supabase LOCAL não está em execução.')
}

run(`
insert into auth.users(id,aud,role,email,email_confirmed_at,created_at,updated_at)
values('${actorId}','authenticated','authenticated','w5a-race-${suffix}@example.invalid',statement_timestamp(),statement_timestamp(),statement_timestamp());
insert into public.tenants(id,tenant_ref,display_name,status,created_by)
values('${tenantId}','${tenantRef}','W5A Race ${suffix}','active','${actorId}');
select * from private.provision_tenant_authorization('${tenantId}',null,'${actorId}','${randomUUID()}');
insert into public.tenant_memberships(
  id,tenant_id,user_id,status,joined_at,created_by,profile_id,profile_assigned_at,profile_assigned_by
)
select '${membershipId}','${tenantId}','${actorId}','active',statement_timestamp(),'${actorId}',
       profile.id,statement_timestamp(),'${actorId}'
from public.tenant_profiles as profile
where profile.tenant_id='${tenantId}' and profile.template_key='manager';
insert into public.tenant_permission_overrides(
  id,tenant_id,membership_id,permission_id,effect,created_by,updated_by
)
select '${overrideId}','${tenantId}','${membershipId}',permission.id,'deny','${actorId}','${actorId}'
from public.permission_catalog as permission
where permission.code='shared.asset_files.read.all_tenant';
delete from public.tenant_profile_permissions as baseline
using public.tenant_profiles as profile, public.permission_catalog as permission
where profile.id=baseline.profile_id
  and permission.id=baseline.permission_id
  and profile.tenant_id='${tenantId}'
  and profile.template_key in ('manager','technician','assistant','requester')
  and permission.resource_code in ('asset_types','assets','asset_files');
`)

const concurrentRollout = `begin;
select private.apply_w5a_authorization_rollout('${tenantId}');
select pg_catalog.pg_sleep(1);
commit;`

const first = runAsync(concurrentRollout)
await new Promise((resolve) => setTimeout(resolve, 100))
const second = runAsync(concurrentRollout)

try {
  await Promise.all([first, second])
} catch (error) {
  fail(`W5A_CONCURRENCY_FAIL: ${error instanceof Error ? error.message : String(error)}`)
}

const counts = run(`select
(select count(*) from public.tenant_profile_permissions as baseline
 join public.tenant_profiles as profile on profile.id=baseline.profile_id
 join public.permission_catalog as permission on permission.id=baseline.permission_id
 where profile.tenant_id='${tenantId}'
   and profile.template_key in ('manager','technician','assistant','requester')
   and permission.resource_code in ('asset_types','assets','asset_files')),
(select count(*) from private.authorization_profile_rollouts
 where tenant_id='${tenantId}' and rollout_key='w5a_assets_storage_v1'),
(select count(*) from public.audit_events
 where tenant_id='${tenantId}'
   and event_type='authorization.profile.baseline_rolled_out'
   and actor_ref='w5a.authorization_rollout'
   and metadata->>'rollout_key'='w5a_assets_storage_v1'),
(select count(*) from public.tenant_permission_overrides
 where id='${overrideId}' and tenant_id='${tenantId}' and effect='deny');`)

if (counts !== '31|4|4|1') {
  fail(`W5A_CONCURRENCY_FAIL: efeitos finais inesperados (${counts}).`)
}

const grantSum = run(`select coalesce(sum(grants_added),0)
from private.authorization_profile_rollouts
where tenant_id='${tenantId}' and rollout_key='w5a_assets_storage_v1';`)
if (grantSum !== '31') {
  fail(`W5A_CONCURRENCY_FAIL: ledger registrou ${grantSum} grants em vez de 31.`)
}

run(`set session_replication_role=replica;
delete from public.audit_events where tenant_id='${tenantId}';
delete from private.authorization_profile_rollouts where tenant_id='${tenantId}';
delete from public.tenant_permission_overrides where tenant_id='${tenantId}';
delete from public.tenant_profile_permissions where tenant_id='${tenantId}';
delete from public.tenant_memberships where tenant_id='${tenantId}';
delete from public.tenant_profiles where tenant_id='${tenantId}';
delete from public.tenant_entitlements where tenant_id='${tenantId}';
delete from public.tenants where id='${tenantId}';
delete from public.app_users where id='${actorId}';
delete from auth.users where id='${actorId}';
set session_replication_role=origin;`)

process.stdout.write(
  'W5A_CONCURRENCY_OK: duas execuções serializadas produziram 31 grants, 4 ledgers, 4 Audits e preservaram o exact DENY.\n',
)
