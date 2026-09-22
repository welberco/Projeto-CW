import { randomUUID } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { spawn, spawnSync } from 'node:child_process'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const config = readFileSync(path.join(root, 'supabase', 'config.toml'), 'utf8')
const projectId = /^project_id\s*=\s*"([a-z0-9-]+)"\s*$/mu.exec(config)?.[1]
if (projectId === undefined) fail('W4C_CONCURRENCY_BLOCKER: projeto Supabase local não identificado.')
const container = `supabase_db_${projectId}`
const suffix = randomUUID().replaceAll('-', '')
const users = Array.from({ length: 5 }, () => randomUUID())
const tenants = Array.from({ length: 5 }, () => randomUUID())
const tenantRefs = Array.from({ length: 5 }, () => randomUUID())
const memberships = Array.from({ length: 5 }, () => randomUUID())
const correlations = Array.from({ length: 48 }, () => randomUUID())

function fail(message) { process.stderr.write(`${message}\n`); process.exit(1) }
function args(sql) { return ['exec','-i',container,'psql','-X','-q','-A','-t','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres','-c',sql] }
function run(sql) {
  const result = spawnSync('docker', args(sql), { cwd: root, encoding: 'utf8', stdio: 'pipe' })
  if (result.error !== undefined || result.status !== 0) fail(`W4C_CONCURRENCY_BLOCKER: ${result.error?.message ?? result.stderr.trim()}`)
  return result.stdout.trim()
}
function runAsync(sql) {
  return new Promise((resolve,reject) => {
    const child = spawn('docker', args(sql), { cwd: root, stdio: ['ignore','pipe','pipe'] })
    let out=''; let err=''
    child.stdout.setEncoding('utf8'); child.stderr.setEncoding('utf8')
    child.stdout.on('data',(chunk)=>{out+=chunk}); child.stderr.on('data',(chunk)=>{err+=chunk})
    child.on('error',reject); child.on('close',(code)=>code===0?resolve(out.trim()):reject(new Error(err.trim()||`psql exited ${code}`)))
  })
}
function auth(sql,index=0,hold=false) {
  return `begin; set local "request.jwt.claim.sub"='${users[index]}'; set local role authenticated; ${sql}; ${hold?'select pg_catalog.pg_sleep(1);':''} commit;`
}
function json(output) { return output.split(/\r?\n/u).map((line)=>line.trim()).find((line)=>line.startsWith('{')&&line.endsWith('}')) }
function oneSuccessOneFailure(results,error,label) {
  const ok=results.filter((r)=>r.status==='fulfilled'); const bad=results.filter((r)=>r.status==='rejected')
  if (ok.length!==1||bad.length!==1||!String(bad[0].reason).includes(error)) fail(`W4C_CONCURRENCY_FAIL: ${label} (${results.map((r)=>r.status).join(',')}).`)
}
async function stagger(first,second) {
  const a=runAsync(first); await new Promise((resolve)=>setTimeout(resolve,100)); const b=runAsync(second); return Promise.allSettled([a,b])
}

const running=spawnSync('docker',['inspect','--format','{{.State.Running}}',container],{cwd:root,encoding:'utf8',stdio:'pipe'})
if(running.status!==0||running.stdout.trim()!=='true') fail('W4C_CONCURRENCY_BLOCKER: PostgreSQL do Supabase LOCAL não está em execução.')

run(`
insert into auth.users(id,aud,role,email,email_confirmed_at,created_at,updated_at)
select id,'authenticated','authenticated','w4c-race-'||id||'@example.invalid',statement_timestamp(),statement_timestamp(),statement_timestamp()
from pg_catalog.unnest(array[${users.map((id)=>`'${id}'::uuid`).join(',')}]) fixture(id);
${tenants.map((tenant,index)=>`insert into public.tenants(id,tenant_ref,display_name,status,created_by) values('${tenant}','${tenantRefs[index]}','W4C Race ${suffix} ${index}','active','${users[index]}');
insert into public.tenant_entitlements(tenant_id,module_key,enabled,created_by) values('${tenant}','maintenance',true,'${users[index]}');
select * from private.provision_tenant_authorization('${tenant}',null,'${users[index]}','${randomUUID()}');
insert into public.tenant_memberships(id,tenant_id,user_id,status,joined_at,created_by,profile_id,profile_assigned_at,profile_assigned_by)
select '${memberships[index]}','${tenant}','${users[index]}','active',statement_timestamp(),'${users[index]}',id,statement_timestamp(),'${users[index]}'
from public.tenant_profiles where tenant_id='${tenant}' and template_key='manager';`).join('\n')}
insert into public.tenant_permission_overrides(tenant_id,membership_id,permission_id,effect,created_by,updated_by)
select m.tenant_id,m.id,p.id,'allow',m.user_id,m.user_id from public.tenant_memberships m cross join public.permission_catalog p
where m.id='${memberships[0]}' and p.code in ('maintenance.maintenance_categories.reactivate.all_tenant','maintenance.maintenance_subcategories.reactivate.all_tenant');
`)

// 1. Same-key Category create replays one stable result.
const sameKey=`w4c-category-same-${suffix}`
const sameOutputs=await Promise.all([
  runAsync(auth(`select public.create_maintenance_category('RACE-A','Race A',null,'same key','${correlations[0]}','${sameKey}')::text`,0,true)),
  (async()=>{await new Promise((r)=>setTimeout(r,100)); return runAsync(auth(`select public.create_maintenance_category('RACE-A','Race A',null,'same key','${correlations[1]}','${sameKey}')::text`))})(),
])
const sameResults=sameOutputs.map(json)
if(sameResults[0]===undefined||sameResults[0]!==sameResults[1]) fail('W4C_CONCURRENCY_FAIL: same-key Category create não retornou resultado estável.')
const categoryA=JSON.parse(sameResults[0])

// 2. Different keys against Category business uniqueness produce one winner.
oneSuccessOneFailure(await Promise.allSettled([0,1].map((i)=>runAsync(auth(
  `select public.create_maintenance_category('RACE-DUP','Duplicate ${i}',null,'different keys','${correlations[2+i]}','w4c-category-different-${suffix}-${i}')`,0,true)))),
  'maintenance_categories_tenant_code_uq','different-key Category uniqueness')

// 3. Two updates with one expected version produce one winner.
oneSuccessOneFailure(await Promise.allSettled([0,1].map((i)=>runAsync(auth(
  `select public.update_maintenance_category('${categoryA.id}',1,'RACE-A','Race A ${i}',null,'version race','${correlations[4+i]}','w4c-category-update-${suffix}-${i}')`,0,true)))),
  'MAINTENANCE_TAXONOMY_VERSION_CONFLICT','Category expected-version race')

// 4. Update held first makes a concurrent inactivate stale.
const currentVersion=run(`select version from public.maintenance_categories where id='${categoryA.id}'`)
oneSuccessOneFailure(await stagger(
  auth(`select public.update_maintenance_category('${categoryA.id}',${currentVersion},'RACE-A','Race A held',null,'update first','${correlations[6]}','w4c-update-inactivate-u-${suffix}')`,0,true),
  auth(`select public.inactivate_maintenance_category('${categoryA.id}',${currentVersion},'inactivate second','${correlations[7]}','w4c-update-inactivate-i-${suffix}')`,0)),
  'MAINTENANCE_TAXONOMY_STATE_OR_VERSION_CONFLICT','update versus inactivate')

// 5. Create Subcategory held first prevents concurrent Category inactivation.
const parent5=JSON.parse(run(auth(`select public.create_maintenance_category('PARENT-5','Parent 5',null,'fixture','${correlations[8]}','w4c-parent5-${suffix}')::text`)))
oneSuccessOneFailure(await stagger(
  auth(`select public.create_maintenance_subcategory('${parent5.id}','CHILD-5','Child 5',null,'create child','${correlations[9]}','w4c-child5-${suffix}')`,0,true),
  auth(`select public.inactivate_maintenance_category('${parent5.id}',1,'inactivate parent','${correlations[10]}','w4c-parent5-off-${suffix}')`,0)),
  'ACTIVE_MAINTENANCE_SUBCATEGORY_DEPENDENCY','create Subcategory versus inactivate Category')

// 6. Reactivate Subcategory held first prevents concurrent Category inactivation.
const parent6=JSON.parse(run(auth(`select public.create_maintenance_category('PARENT-6','Parent 6',null,'fixture','${correlations[11]}','w4c-parent6-${suffix}')::text`)))
const child6=JSON.parse(run(auth(`select public.create_maintenance_subcategory('${parent6.id}','CHILD-6','Child 6',null,'fixture','${correlations[12]}','w4c-child6-${suffix}')::text`)))
run(auth(`select public.inactivate_maintenance_subcategory('${child6.id}',1,'prepare inactive','${correlations[13]}','w4c-child6-off-${suffix}')`))
oneSuccessOneFailure(await stagger(
  auth(`select public.reactivate_maintenance_subcategory('${child6.id}',2,'reactivate child','${correlations[14]}','w4c-child6-on-${suffix}')`,0,true),
  auth(`select public.inactivate_maintenance_category('${parent6.id}',1,'inactivate parent','${correlations[15]}','w4c-parent6-off-${suffix}')`,0)),
  'ACTIVE_MAINTENANCE_SUBCATEGORY_DEPENDENCY','reactivate Subcategory versus inactivate Category')

// 7. Contextual Subcategory code uniqueness has one winner.
oneSuccessOneFailure(await Promise.allSettled([0,1].map((i)=>runAsync(auth(
  `select public.create_maintenance_subcategory('${parent6.id}','CONTEXT-DUP','Context duplicate ${i}',null,'context race','${correlations[16+i]}','w4c-context-${suffix}-${i}')`,0,true)))),
  'maintenance_subcategories_category_code_uq','Subcategory contextual uniqueness')

// 8. Same-key Template application returns one stable result.
const applySame=`w4c-template-same-${suffix}`
const applySameOutputs=await Promise.all([
  runAsync(auth(`select public.apply_cw_catalog_template('cw_maintenance_taxonomy',1,'same apply','${correlations[18]}','${applySame}')::text`,1,true)),
  (async()=>{await new Promise((r)=>setTimeout(r,100)); return runAsync(auth(`select public.apply_cw_catalog_template('cw_maintenance_taxonomy',1,'same apply','${correlations[19]}','${applySame}')::text`,1))})(),
])
if(json(applySameOutputs[0])!==json(applySameOutputs[1])) fail('W4C_CONCURRENCY_FAIL: same-key Template apply não retornou resultado estável.')

// 9. Different apply keys serialize to the same immutable application ledger.
const applyDifferent=await Promise.all([0,1].map((i)=>runAsync(auth(
  `select public.apply_cw_catalog_template('cw_maintenance_taxonomy',1,'different apply','${correlations[20+i]}','w4c-template-different-${suffix}-${i}')::text`,2,true))))
const differentIds=applyDifferent.map((out)=>JSON.parse(json(out)).id)
if(differentIds[0]!==differentIds[1]||run(`select count(*) from private.catalog_template_applications where tenant_id='${tenants[2]}'`) !== '1')
  fail('W4C_CONCURRENCY_FAIL: different-key Template apply duplicou o ledger.')

// 10. Manual Category creation held first makes Template application fail closed.
oneSuccessOneFailure(await stagger(
  auth(`select public.create_maintenance_category('MANUAL-10','Manual 10',null,'manual wins','${correlations[22]}','w4c-manual10-${suffix}')`,3,true),
  auth(`select public.apply_cw_catalog_template('cw_maintenance_taxonomy',1,'apply loses','${correlations[23]}','w4c-apply10-${suffix}')`,3)),
  'MAINTENANCE_TAXONOMY_NOT_EMPTY','Template apply versus manual Category')

// 11. With an existing Category, manual Subcategory and Template application cannot merge.
const parent11=JSON.parse(run(auth(`select public.create_maintenance_category('PARENT-11','Parent 11',null,'fixture','${correlations[24]}','w4c-parent11-${suffix}')::text`,4)))
oneSuccessOneFailure(await stagger(
  auth(`select public.create_maintenance_subcategory('${parent11.id}','MANUAL-11','Manual 11',null,'manual child','${correlations[25]}','w4c-child11-${suffix}')`,4,true),
  auth(`select public.apply_cw_catalog_template('cw_maintenance_taxonomy',1,'no merge','${correlations[26]}','w4c-apply11-${suffix}')`,4)),
  'MAINTENANCE_TAXONOMY_NOT_EMPTY','Template apply versus manual Subcategory')

// 12. A transaction failure after apply rolls back every copy, ledger and effect.
const atomicUser=randomUUID(); const atomicTenant=randomUUID(); const atomicRef=randomUUID(); const atomicMembership=randomUUID()
run(`insert into auth.users(id,aud,role,email,email_confirmed_at,created_at,updated_at) values('${atomicUser}','authenticated','authenticated','w4c-atomic-${suffix}@example.invalid',statement_timestamp(),statement_timestamp(),statement_timestamp());
insert into public.tenants(id,tenant_ref,display_name,status,created_by) values('${atomicTenant}','${atomicRef}','W4C Atomic ${suffix}','active','${atomicUser}');
insert into public.tenant_entitlements(tenant_id,module_key,enabled,created_by) values('${atomicTenant}','maintenance',true,'${atomicUser}');
select * from private.provision_tenant_authorization('${atomicTenant}',null,'${atomicUser}','${randomUUID()}');
insert into public.tenant_memberships(id,tenant_id,user_id,status,joined_at,created_by,profile_id,profile_assigned_at,profile_assigned_by)
select '${atomicMembership}','${atomicTenant}','${atomicUser}','active',statement_timestamp(),'${atomicUser}',id,statement_timestamp(),'${atomicUser}' from public.tenant_profiles where tenant_id='${atomicTenant}' and template_key='manager';`)
const forcedRollback=await Promise.allSettled([runAsync(`begin; set local "request.jwt.claim.sub"='${atomicUser}'; set local role authenticated;
select public.apply_cw_catalog_template('cw_maintenance_taxonomy',1,'atomic rollback','${correlations[27]}','w4c-atomic-${suffix}');
do $$begin raise exception 'FORCED_ATOMIC_ROLLBACK'; end$$; commit;`)])
if(forcedRollback[0].status!=='rejected'||!String(forcedRollback[0].reason).includes('FORCED_ATOMIC_ROLLBACK')) fail('W4C_CONCURRENCY_FAIL: falha atômica controlada não ocorreu.')
if(run(`select (select count(*) from public.maintenance_categories where tenant_id='${atomicTenant}')||'|'||(select count(*) from public.maintenance_subcategories where tenant_id='${atomicTenant}')||'|'||(select count(*) from private.catalog_template_applications where tenant_id='${atomicTenant}')`) !== '0|0|0')
  fail('W4C_CONCURRENCY_FAIL: aplicação falha deixou estado parcial.')

run(`set session_replication_role=replica;
delete from private.catalog_template_applications where tenant_id=any(array[${[...tenants,atomicTenant].map((id)=>`'${id}'::uuid`).join(',')}]);
delete from public.maintenance_subcategories where tenant_id=any(array[${[...tenants,atomicTenant].map((id)=>`'${id}'::uuid`).join(',')}]);
delete from public.maintenance_categories where tenant_id=any(array[${[...tenants,atomicTenant].map((id)=>`'${id}'::uuid`).join(',')}]);
delete from private.command_idempotency where tenant_id=any(array[${[...tenants,atomicTenant].map((id)=>`'${id}'::uuid`).join(',')}]);
delete from private.outbox_events where tenant_id=any(array[${[...tenants,atomicTenant].map((id)=>`'${id}'::uuid`).join(',')}]);
delete from public.history_entries where tenant_id=any(array[${[...tenants,atomicTenant].map((id)=>`'${id}'::uuid`).join(',')}]);
delete from public.audit_events where tenant_id=any(array[${[...tenants,atomicTenant].map((id)=>`'${id}'::uuid`).join(',')}]);
delete from private.authorization_profile_rollouts where tenant_id=any(array[${[...tenants,atomicTenant].map((id)=>`'${id}'::uuid`).join(',')}]);
delete from public.tenant_permission_overrides where tenant_id=any(array[${[...tenants,atomicTenant].map((id)=>`'${id}'::uuid`).join(',')}]);
delete from public.tenant_profile_permissions where tenant_id=any(array[${[...tenants,atomicTenant].map((id)=>`'${id}'::uuid`).join(',')}]);
delete from public.tenant_memberships where tenant_id=any(array[${[...tenants,atomicTenant].map((id)=>`'${id}'::uuid`).join(',')}]);
delete from public.tenant_profiles where tenant_id=any(array[${[...tenants,atomicTenant].map((id)=>`'${id}'::uuid`).join(',')}]);
delete from public.tenant_entitlements where tenant_id=any(array[${[...tenants,atomicTenant].map((id)=>`'${id}'::uuid`).join(',')}]);
delete from public.tenants where id=any(array[${[...tenants,atomicTenant].map((id)=>`'${id}'::uuid`).join(',')}]);
delete from public.app_users where id=any(array[${[...users,atomicUser].map((id)=>`'${id}'::uuid`).join(',')}]);
delete from auth.users where id=any(array[${[...users,atomicUser].map((id)=>`'${id}'::uuid`).join(',')}]);`)

process.stdout.write('W4C_CONCURRENCY_OK: 12 casos cobrem uniqueness, optimistic locking, lifecycle pai-filho, aplicação concorrente, não-merge e atomicidade do Template CW.\n')
