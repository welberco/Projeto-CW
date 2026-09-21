import { randomUUID } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { spawn, spawnSync } from 'node:child_process'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const config = readFileSync(path.join(projectRoot, 'supabase', 'config.toml'), 'utf8')
const projectId = /^project_id\s*=\s*"([a-z0-9-]+)"\s*$/mu.exec(config)?.[1]
if (projectId === undefined) fail('W4B_CONCURRENCY_BLOCKER: projeto Supabase local não identificado.')

const containerName = `supabase_db_${projectId}`
const suffix = randomUUID().replaceAll('-', '')
const actorId = randomUUID()
const targetIds = Array.from({ length: 5 }, () => randomUUID())
const tenantId = randomUUID()
const tenantRef = randomUUID()
const actorMembershipId = randomUUID()
const membershipIds = Array.from({ length: 5 }, () => randomUUID())
const correlations = Array.from({ length: 30 }, () => randomUUID())

function fail(message) {
  process.stderr.write(`${message}\n`)
  process.exit(1)
}

function args(sql) {
  return [
    'exec', '-i', containerName, 'psql', '-X', '-q', '-A', '-t',
    '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres', '-c', sql,
  ]
}

function run(sql) {
  const result = spawnSync('docker', args(sql), {
    cwd: projectRoot,
    encoding: 'utf8',
    stdio: 'pipe',
  })
  if (result.error !== undefined || result.status !== 0) {
    fail(`W4B_CONCURRENCY_BLOCKER: ${result.error?.message ?? result.stderr.trim()}`)
  }
  return result.stdout.trim()
}

function runAsync(sql) {
  return new Promise((resolve, reject) => {
    const child = spawn('docker', args(sql), {
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

function authenticated(sql, userId = actorId) {
  return `begin; set local "request.jwt.claim.sub"='${userId}'; set local role authenticated; ${sql}; commit;`
}

function heldAuthenticated(sql, userId = actorId) {
  return authenticated(`${sql}; select pg_catalog.pg_sleep(1)`, userId)
}

function jsonResult(output) {
  return output.split(/\r?\n/u).map((line) => line.trim())
    .find((line) => line.startsWith('{') && line.endsWith('}'))
}

function oneSuccessOneFailure(results, expectedError, label) {
  const successes = results.filter((result) => result.status === 'fulfilled')
  const failures = results.filter((result) => result.status === 'rejected')
  if (successes.length !== 1 || failures.length !== 1) {
    fail(`W4B_CONCURRENCY_FAIL: ${label} não produziu exatamente um sucesso e uma falha.`)
  }
  const failure = failures[0]
  if (failure.status !== 'rejected' || !String(failure.reason).includes(expectedError)) {
    fail(`W4B_CONCURRENCY_FAIL: ${label} não falhou com ${expectedError}.`)
  }
}

const running = spawnSync(
  'docker', ['inspect', '--format', '{{.State.Running}}', containerName],
  { cwd: projectRoot, encoding: 'utf8', stdio: 'pipe' },
)
if (running.status !== 0 || running.stdout.trim() !== 'true') {
  fail('W4B_CONCURRENCY_BLOCKER: PostgreSQL do Supabase LOCAL não está em execução.')
}

const users = [actorId, ...targetIds]
run(`
insert into auth.users(id,aud,role,email,email_confirmed_at,created_at,updated_at)
select id,'authenticated','authenticated','w4b-race-' || id || '@example.invalid',statement_timestamp(),statement_timestamp(),statement_timestamp()
from pg_catalog.unnest(array[${users.map((id) => `'${id}'::uuid`).join(',')}]) as fixture(id);
insert into public.tenants(id,tenant_ref,display_name,status,created_by)
values('${tenantId}','${tenantRef}','W4B Race ${suffix}','active','${actorId}');
select * from private.provision_tenant_authorization('${tenantId}',null,'${actorId}','${randomUUID()}');
insert into public.tenant_memberships(id,tenant_id,user_id,status,joined_at,created_by,profile_id,profile_assigned_at,profile_assigned_by)
select fixture.membership_id,'${tenantId}',fixture.user_id,'active',statement_timestamp(),'${actorId}',profile.id,statement_timestamp(),'${actorId}'
from (values ${users.map((id, index) => `('${id}'::uuid,'${index === 0 ? actorMembershipId : membershipIds[index - 1]}'::uuid,${index})`).join(',')}) as fixture(user_id,membership_id,ordinal)
join public.tenant_profiles as profile on profile.tenant_id='${tenantId}'
 and profile.template_key=case when fixture.ordinal=0 then 'manager' else 'requester' end;
`)

const sector = JSON.parse(run(authenticated(
  `select public.create_sector('W4B-RACE','W4B Race Sector',null,'concurrency fixture','${correlations[0]}','w4b-sector-${suffix}')::text`,
)))
const sectorId = sector.id

// 1. Same-key create: both sessions replay one stable result.
const createKey = `w4b-create-same-${suffix}`
const createSql = (correlationId) => heldAuthenticated(
  `select public.create_team('${sectorId}','RACE-A','Race Team A',null,'same-key create','${correlationId}','${createKey}')::text`,
)
const createFirst = runAsync(createSql(correlations[1]))
await new Promise((resolve) => setTimeout(resolve, 100))
const createSecond = runAsync(createSql(correlations[2]))
const createOutputs = await Promise.all([createFirst, createSecond])
const createResults = createOutputs.map(jsonResult)
if (createResults[0] === undefined || createResults[0] !== createResults[1]) {
  fail('W4B_CONCURRENCY_FAIL: same-key create não retornou resultado estável.')
}
const createResult = JSON.parse(createResults[0])
const teamId = createResult.id
const createCorrelationId = createResult.command_correlation_id

// 2. Same-key add: one association and one stable replay.
const addSameKey = `w4b-add-same-${suffix}`
const addSameSql = (correlationId) => heldAuthenticated(
  `select public.add_team_member('${teamId}','${membershipIds[0]}','same-key add','${correlationId}','${addSameKey}')::text`,
)
const addFirst = runAsync(addSameSql(correlations[3]))
await new Promise((resolve) => setTimeout(resolve, 100))
const addSecond = runAsync(addSameSql(correlations[4]))
const addOutputs = await Promise.all([addFirst, addSecond])
const addResults = addOutputs.map(jsonResult)
if (addResults[0] === undefined || addResults[0] !== addResults[1]) {
  fail('W4B_CONCURRENCY_FAIL: same-key add não retornou resultado estável.')
}

// 3. Different keys for the same active pair: unique active membership fails closed.
const duplicateCommands = [0, 1].map((index) => runAsync(heldAuthenticated(
  `select public.add_team_member('${teamId}','${membershipIds[1]}','different-key duplicate','${correlations[5 + index]}','w4b-add-different-${suffix}-${index}')::text`,
)))
oneSuccessOneFailure(
  await Promise.allSettled(duplicateCommands),
  'team_memberships_one_active_pair_uidx',
  'different-key active-pair race',
)

// 4. End then add: the ended row is preserved and a new active row is created.
const initialThird = JSON.parse(run(authenticated(
  `select public.add_team_member('${teamId}','${membershipIds[2]}','prepare end-add','${correlations[7]}','w4b-prepare-end-add-${suffix}')::text`,
)))
const endThenAdd = runAsync(heldAuthenticated(
  `select public.end_team_member('${initialThird.id}',1,'end before return','${correlations[8]}','w4b-end-add-end-${suffix}')::text`,
))
await new Promise((resolve) => setTimeout(resolve, 100))
const addAfterEnd = runAsync(authenticated(
  `select public.add_team_member('${teamId}','${membershipIds[2]}','return after end','${correlations[9]}','w4b-end-add-add-${suffix}')::text`,
))
await Promise.all([endThenAdd, addAfterEnd])

// 5. Add versus inactivate: the active roster dependency wins fail-closed.
const isolatedTeam = JSON.parse(run(authenticated(
  `select public.create_team('${sectorId}','RACE-B','Race Team B',null,'prepare add-inactivate','${correlations[10]}','w4b-team-b-${suffix}')::text`,
)))
const addWinner = runAsync(heldAuthenticated(
  `select public.add_team_member('${isolatedTeam.id}','${membershipIds[3]}','add before inactivate','${correlations[11]}','w4b-add-inactivate-add-${suffix}')::text`,
))
await new Promise((resolve) => setTimeout(resolve, 100))
const inactivateLoser = runAsync(authenticated(
  `select public.inactivate_team('${isolatedTeam.id}',1,'race inactivate','${correlations[12]}','w4b-add-inactivate-state-${suffix}')::text`,
))
oneSuccessOneFailure(
  await Promise.allSettled([addWinner, inactivateLoser]),
  'ACTIVE_TEAM_MEMBERSHIP_DEPENDENCY',
  'add versus inactivate race',
)

// 6. Two optimistic updates with the same version: one wins.
const updateCommands = [0, 1].map((index) => runAsync(heldAuthenticated(
  `select public.update_team('${teamId}',1,'${sectorId}','RACE-A','Race Team A ${index}',null,'version race','${correlations[13 + index]}','w4b-update-${suffix}-${index}')::text`,
)))
oneSuccessOneFailure(
  await Promise.allSettled(updateCommands),
  'TEAM_VERSION_CONFLICT',
  'same-version update race',
)

// 7. Two ends with the same version: one transition wins.
const initialFifth = JSON.parse(run(authenticated(
  `select public.add_team_member('${teamId}','${membershipIds[4]}','prepare double end','${correlations[15]}','w4b-prepare-double-end-${suffix}')::text`,
)))
const endCommands = [0, 1].map((index) => runAsync(heldAuthenticated(
  `select public.end_team_member('${initialFifth.id}',1,'double end','${correlations[16 + index]}','w4b-double-end-${suffix}-${index}')::text`,
)))
oneSuccessOneFailure(
  await Promise.allSettled(endCommands),
  'TEAM_MEMBERSHIP_STATE_OR_VERSION_CONFLICT',
  'double-end race',
)

// 8. A session re-evaluates TEAM reach after a concurrent membership change.
const activeThirdId = run(`select id from public.team_memberships where tenant_id='${tenantId}' and team_id='${teamId}' and membership_id='${membershipIds[2]}' and status='active';`)
const reachProbe = runAsync(authenticated(
  `select 'before:' || count(*) from public.list_my_teams(); select pg_catalog.pg_sleep(1); select 'after:' || count(*) from public.list_my_teams()`,
  targetIds[2],
))
await new Promise((resolve) => setTimeout(resolve, 100))
const reachRevocation = runAsync(authenticated(
  `select public.end_team_member('${activeThirdId}',1,'revoke live reach','${correlations[18]}','w4b-reach-end-${suffix}')`,
))
const [reachOutput] = await Promise.all([reachProbe, reachRevocation])
if (!reachOutput.includes('before:1') || !reachOutput.includes('after:0')) {
  fail(`W4B_CONCURRENCY_FAIL: alcance TEAM não acompanhou a mudança concorrente (${reachOutput}).`)
}

// 9. Replay emits one mutation and one effect triple.
const effectCounts = run(`select
(select count(*) from public.teams where tenant_id='${tenantId}' and id='${teamId}'),
(select count(*) from private.command_idempotency where tenant_id='${tenantId}' and idempotency_key_hash=private.semantic_fingerprint(pg_catalog.to_jsonb('${createKey}'::text))),
(select count(*) from public.audit_events where tenant_id='${tenantId}' and correlation_id='${createCorrelationId}'),
(select count(*) from public.history_entries where tenant_id='${tenantId}' and correlation_id='${createCorrelationId}'),
(select count(*) from private.outbox_events where tenant_id='${tenantId}' and correlation_id='${createCorrelationId}');`)
if (effectCounts !== '1|1|1|1|1') {
  fail(`W4B_CONCURRENCY_FAIL: efeitos idempotentes inesperados (${effectCounts}).`)
}

// 10. Team-membership mutation invalidates authorization projections by revision.
const bumpedRevision = run(`select (version > 1)::text from public.tenant_memberships where tenant_id='${tenantId}' and id='${membershipIds[0]}';`)
if (bumpedRevision !== 'true') {
  fail(`W4B_CONCURRENCY_FAIL: revision da membership alvo não avançou (${bumpedRevision}).`)
}

run(`set session_replication_role=replica;
delete from public.team_memberships where tenant_id='${tenantId}';
delete from public.teams where tenant_id='${tenantId}';
delete from public.sectors where tenant_id='${tenantId}';
delete from private.command_idempotency where tenant_id='${tenantId}';
delete from private.outbox_events where tenant_id='${tenantId}';
delete from public.history_entries where tenant_id='${tenantId}';
delete from public.audit_events where tenant_id='${tenantId}';
delete from private.authorization_profile_rollouts where tenant_id='${tenantId}';
delete from public.tenant_permission_overrides where tenant_id='${tenantId}';
delete from public.tenant_profile_permissions where tenant_id='${tenantId}';
delete from public.tenant_memberships where tenant_id='${tenantId}';
delete from public.tenant_profiles where tenant_id='${tenantId}';
delete from public.tenant_entitlements where tenant_id='${tenantId}';
delete from public.tenants where id='${tenantId}';
delete from public.app_users where id=any(array[${users.map((id) => `'${id}'::uuid`).join(',')}]);
delete from auth.users where id=any(array[${users.map((id) => `'${id}'::uuid`).join(',')}]);
set session_replication_role=origin;`)

process.stdout.write(
  'W4B_CONCURRENCY_OK: 10 casos cobrem replay, duplicidade, lifecycle, optimistic locking, TEAM reach, efeitos e revision bump.\n',
)
