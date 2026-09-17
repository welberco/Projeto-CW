import { randomUUID } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { spawn, spawnSync } from 'node:child_process'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const config = readFileSync(path.join(projectRoot, 'supabase', 'config.toml'), 'utf8')
const projectId = /^project_id\s*=\s*"([a-z0-9-]+)"\s*$/mu.exec(config)?.[1]
if (projectId === undefined) fail('W4A_CONCURRENCY_BLOCKER: projeto Supabase local não identificado.')

const containerName = `supabase_db_${projectId}`
const suffix = randomUUID().replaceAll('-', '')
const actorId = randomUUID()
const tenantId = randomUUID()
const tenantRef = randomUUID()
const key = `w4a-race-${suffix}`
const sectorName = `W4A Race ${suffix}`

function fail(message) { process.stderr.write(`${message}\n`); process.exit(1) }
function args(sql) { return ['exec','-i',containerName,'psql','-X','-q','-A','-t','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres','-c',sql] }
function run(sql) {
  const result=spawnSync('docker',args(sql),{cwd:projectRoot,encoding:'utf8',stdio:'pipe'})
  if(result.error!==undefined||result.status!==0) fail(`W4A_CONCURRENCY_BLOCKER: ${result.error?.message??result.stderr.trim()}`)
  return result.stdout.trim()
}
function runAsync(sql) { return new Promise((resolve,reject)=>{
  const child=spawn('docker',args(sql),{cwd:projectRoot,stdio:['ignore','pipe','pipe']}); let out=''; let err=''
  child.stdout.setEncoding('utf8'); child.stderr.setEncoding('utf8'); child.stdout.on('data',(c)=>{out+=c}); child.stderr.on('data',(c)=>{err+=c})
  child.on('error',reject); child.on('close',(code)=>code===0?resolve(out.trim()):reject(new Error(err.trim()||`psql exited ${code}`)))
}) }

const running=spawnSync('docker',['inspect','--format','{{.State.Running}}',containerName],{cwd:projectRoot,encoding:'utf8',stdio:'pipe'})
if(running.status!==0||running.stdout.trim()!=='true') fail('W4A_CONCURRENCY_BLOCKER: PostgreSQL do Supabase LOCAL não está em execução.')

run(`
insert into auth.users(id,aud,role,email,email_confirmed_at,created_at,updated_at) values('${actorId}','authenticated','authenticated','w4a-race-${suffix}@example.invalid',statement_timestamp(),statement_timestamp(),statement_timestamp());
insert into public.tenants(id,tenant_ref,display_name,status,created_by) values('${tenantId}','${tenantRef}','W4A Race ${suffix}','active','${actorId}');
select * from private.provision_tenant_authorization('${tenantId}',null,'${actorId}','${randomUUID()}');
insert into public.tenant_memberships(tenant_id,user_id,status,joined_at,created_by,profile_id,profile_assigned_at,profile_assigned_by)
select '${tenantId}','${actorId}','active',statement_timestamp(),'${actorId}',id,statement_timestamp(),'${actorId}' from public.tenant_profiles where tenant_id='${tenantId}' and template_key='manager';`)

function command(correlationId) { return `begin; set local "request.jwt.claim.sub"='${actorId}'; set local role authenticated;
select public.create_sector('RACE','${sectorName}',null,'concurrent W4A proof','${correlationId}','${key}')::text;
select pg_catalog.pg_sleep(1); commit;` }

const first=runAsync(command(randomUUID())); await new Promise((resolve)=>setTimeout(resolve,100)); const second=runAsync(command(randomUUID()))
let outputs
try { outputs=await Promise.all([first,second]) } catch(error) { fail(`W4A_CONCURRENCY_FAIL: ${error instanceof Error?error.message:String(error)}`) }
const results=outputs.map((output)=>output.split(/\r?\n/u).map((line)=>line.trim()).find((line)=>line.startsWith('{')&&line.endsWith('}')))
if(results[0]===undefined||results[0]!==results[1]) fail('W4A_CONCURRENCY_FAIL: replay concorrente não retornou resultado estável.')

const counts=run(`select
(select count(*) from public.sectors where tenant_id='${tenantId}' and name='${sectorName}'),
(select count(*) from private.command_idempotency where tenant_id='${tenantId}' and idempotency_key_hash=private.semantic_fingerprint(pg_catalog.to_jsonb('${key}'::text))),
(select count(*) from public.audit_events where tenant_id='${tenantId}' and event_type='cadastros.sector.created'),
(select count(*) from public.history_entries where tenant_id='${tenantId}' and history_type='cadastros.sector.created'),
(select count(*) from private.outbox_events where tenant_id='${tenantId}' and event_type='cadastros.sector.created');`)
if(counts!=='1|1|1|1|1') fail(`W4A_CONCURRENCY_FAIL: efeitos concorrentes inesperados (${counts}).`)

run(`set session_replication_role=replica;
delete from public.sectors where tenant_id='${tenantId}'; delete from private.command_idempotency where tenant_id='${tenantId}'; delete from private.outbox_events where tenant_id='${tenantId}'; delete from public.history_entries where tenant_id='${tenantId}'; delete from public.audit_events where tenant_id='${tenantId}'; delete from private.authorization_profile_rollouts where tenant_id='${tenantId}'; delete from public.tenant_permission_overrides where tenant_id='${tenantId}'; delete from public.tenant_profile_permissions where tenant_id='${tenantId}'; delete from public.tenant_memberships where tenant_id='${tenantId}'; delete from public.tenant_profiles where tenant_id='${tenantId}'; delete from public.tenant_entitlements where tenant_id='${tenantId}'; delete from public.tenants where id='${tenantId}'; delete from public.app_users where id='${actorId}'; delete from auth.users where id='${actorId}'; set session_replication_role=origin;`)

process.stdout.write('W4A_CONCURRENCY_OK: 2 sessões, 1 mutation, 1 idempotency row, 1 Audit, 1 History e 1 Event.\n')
