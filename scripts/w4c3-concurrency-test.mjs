import { randomUUID } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { spawn, spawnSync } from 'node:child_process'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const config = readFileSync(path.join(root, 'supabase', 'config.toml'), 'utf8')
const projectId = /^project_id\s*=\s*"([a-z0-9-]+)"\s*$/mu.exec(config)?.[1]
if (projectId === undefined) fail('W4C3_CONCURRENCY_BLOCKER: projeto Supabase local não identificado.')
const container = `supabase_db_${projectId}`
const suffix = randomUUID().replaceAll('-', '')
const users = Array.from({ length: 3 }, () => randomUUID())
const tenants = Array.from({ length: 3 }, () => randomUUID())
const tenantRefs = Array.from({ length: 3 }, () => randomUUID())
const memberships = Array.from({ length: 3 }, () => randomUUID())
const correlations = Array.from({ length: 48 }, () => randomUUID())

function fail(message) { process.stderr.write(`${message}\n`); process.exit(1) }
function args(sql) { return ['exec','-i',container,'psql','-X','-q','-A','-t','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres','-c',sql] }
function run(sql) {
  const result = spawnSync('docker', args(sql), { cwd: root, encoding: 'utf8', stdio: 'pipe' })
  if (result.error !== undefined || result.status !== 0) fail(`W4C3_CONCURRENCY_BLOCKER: ${result.error?.message ?? result.stderr.trim()}`)
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
  const ok=results.filter((result)=>result.status==='fulfilled')
  const bad=results.filter((result)=>result.status==='rejected')
  if(ok.length!==1||bad.length!==1||!String(bad[0].reason).includes(error))
    fail(`W4C3_CONCURRENCY_FAIL: ${label} (${results.map((result)=>result.status).join(',')}).`)
}
async function stagger(first,second) {
  const firstRun=runAsync(first)
  await new Promise((resolve)=>setTimeout(resolve,100))
  const secondRun=runAsync(second)
  return Promise.allSettled([firstRun,secondRun])
}

const running=spawnSync('docker',['inspect','--format','{{.State.Running}}',container],{cwd:root,encoding:'utf8',stdio:'pipe'})
if(running.status!==0||running.stdout.trim()!=='true') fail('W4C3_CONCURRENCY_BLOCKER: PostgreSQL do Supabase LOCAL não está em execução.')

run(`
insert into auth.users(id,aud,role,email,email_confirmed_at,created_at,updated_at)
select id,'authenticated','authenticated','w4c3-race-'||id||'@example.invalid',statement_timestamp(),statement_timestamp(),statement_timestamp()
from pg_catalog.unnest(array[${users.map((id)=>`'${id}'::uuid`).join(',')}]) fixture(id);
${tenants.map((tenant,index)=>`insert into public.tenants(id,tenant_ref,display_name,status,created_by) values('${tenant}','${tenantRefs[index]}','W4C3 Race ${suffix} ${index}','active','${users[index]}');
insert into public.tenant_entitlements(tenant_id,module_key,enabled,created_by) values('${tenant}','maintenance',true,'${users[index]}');
select * from private.provision_tenant_authorization('${tenant}',null,'${users[index]}','${randomUUID()}');
insert into public.tenant_memberships(id,tenant_id,user_id,status,joined_at,created_by,profile_id,profile_assigned_at,profile_assigned_by)
select '${memberships[index]}','${tenant}','${users[index]}','active',statement_timestamp(),'${users[index]}',id,statement_timestamp(),'${users[index]}'
from public.tenant_profiles where tenant_id='${tenant}' and template_key='manager';`).join('\n')}
insert into public.tenant_permission_overrides(tenant_id,membership_id,permission_id,effect,created_by,updated_by)
select m.tenant_id,m.id,p.id,'allow',m.user_id,m.user_id
from public.tenant_memberships m cross join public.permission_catalog p
where m.id=any(array[${memberships.map((id)=>`'${id}'::uuid`).join(',')}]) and p.code in (
  'maintenance.maintenance_categories.reactivate.all_tenant',
  'maintenance.maintenance_reasons.reactivate.all_tenant',
  'maintenance.document_types.create.all_tenant','maintenance.document_types.update.all_tenant',
  'maintenance.document_types.inactivate.all_tenant','maintenance.document_types.reactivate.all_tenant',
  'maintenance.checklist_templates.create.all_tenant','maintenance.checklist_templates.update.all_tenant',
  'maintenance.checklist_templates.inactivate.all_tenant','maintenance.checklist_templates.reactivate.all_tenant'
);`)

// 1. Same-key Reason create is one stable command.
const reasonSameKey=`w4c3-reason-same-${suffix}`
const reasonSame=await Promise.all([
  runAsync(auth(`select public.create_maintenance_reason('CANCEL_REQUEST','SAME','Same reason',null,'same key','${correlations[0]}','${reasonSameKey}')::text`,0,true)),
  (async()=>{await new Promise((resolve)=>setTimeout(resolve,100)); return runAsync(auth(`select public.create_maintenance_reason('CANCEL_REQUEST','SAME','Same reason',null,'same key','${correlations[1]}','${reasonSameKey}')::text`,0))})(),
])
if(json(reasonSame[0])===undefined||json(reasonSame[0])!==json(reasonSame[1])) fail('W4C3_CONCURRENCY_FAIL: same-key Reason create não foi estável.')
const reason=JSON.parse(json(reasonSame[0]))

// 2. Different keys cannot duplicate a Reason inside the same context.
oneSuccessOneFailure(await Promise.allSettled([0,1].map((index)=>runAsync(auth(
  `select public.create_maintenance_reason('PAUSE_WORK_ORDER','DUP','Duplicate ${index}',null,'uniqueness','${correlations[2+index]}','w4c3-reason-dup-${suffix}-${index}')`,0,true)))),
  'maintenance_reasons_tenant_context_code_uq','Reason contextual uniqueness')

// 3. The same Reason code remains independently valid in different contexts.
const contexts=await Promise.all([['REJECT_REQUEST',4],['RETURN_WORK_ORDER',5]].map(([context,offset])=>runAsync(auth(
  `select public.create_maintenance_reason('${context}','CROSS-CONTEXT','${context}',null,'context independence','${correlations[offset]}','w4c3-reason-context-${suffix}-${offset}')`,0,true))))
if(contexts.length!==2) fail('W4C3_CONCURRENCY_FAIL: Reason contexts não permaneceram independentes.')

// 4. Two Reason updates with one expected version have one winner.
oneSuccessOneFailure(await Promise.allSettled([0,1].map((index)=>runAsync(auth(
  `select public.update_maintenance_reason('${reason.id}',1,'SAME','Reason update ${index}',null,'version race','${correlations[6+index]}','w4c3-reason-update-${suffix}-${index}')`,0,true)))),
  'SUPPORTING_CATALOG_VERSION_CONFLICT','Reason expected-version race')

// 5. A held Reason update makes concurrent inactivation stale.
const reasonVersion=run(`select version from public.maintenance_reasons where id='${reason.id}'`)
oneSuccessOneFailure(await stagger(
  auth(`select public.update_maintenance_reason('${reason.id}',${reasonVersion},'SAME','Reason held',null,'update first','${correlations[8]}','w4c3-reason-held-${suffix}')`,0,true),
  auth(`select public.inactivate_maintenance_reason('${reason.id}',${reasonVersion},'inactivate second','${correlations[9]}','w4c3-reason-off-${suffix}')`,0)),
  'SUPPORTING_CATALOG_STATE_OR_VERSION_CONFLICT','Reason update versus inactivate')

// 6. Different keys cannot duplicate a Document Type.
oneSuccessOneFailure(await Promise.allSettled([0,1].map((index)=>runAsync(auth(
  `select public.create_document_type('DOC-DUP','Document ${index}',null,'uniqueness','${correlations[10+index]}','w4c3-document-dup-${suffix}-${index}')`,1,true)))),
  'document_types_tenant_code_uq','Document Type uniqueness')

const document=JSON.parse(run(auth(`select public.create_document_type('DOC','Document',null,'fixture','${correlations[12]}','w4c3-document-${suffix}')::text`,1)))

// 7. Two Document Type updates with one expected version have one winner.
oneSuccessOneFailure(await Promise.allSettled([0,1].map((index)=>runAsync(auth(
  `select public.update_document_type('${document.id}',1,'DOC','Document update ${index}',null,'version race','${correlations[13+index]}','w4c3-document-update-${suffix}-${index}')`,1,true)))),
  'SUPPORTING_CATALOG_VERSION_CONFLICT','Document Type expected-version race')

// 8. A held Document Type update makes concurrent inactivation stale.
const documentVersion=run(`select version from public.document_types where id='${document.id}'`)
oneSuccessOneFailure(await stagger(
  auth(`select public.update_document_type('${document.id}',${documentVersion},'DOC','Document held',null,'update first','${correlations[15]}','w4c3-document-held-${suffix}')`,1,true),
  auth(`select public.inactivate_document_type('${document.id}',${documentVersion},'inactivate second','${correlations[16]}','w4c3-document-off-${suffix}')`,1)),
  'SUPPORTING_CATALOG_STATE_OR_VERSION_CONFLICT','Document Type update versus inactivate')

const category=JSON.parse(run(auth(`select public.create_maintenance_category('CHECK','Checklist category',null,'fixture','${correlations[17]}','w4c3-category-${suffix}')::text`,2)))
const items=`[{"position":1,"prompt":"Inspect","response_type":"YES_NO","required":true}]`

// 9. Same-key Checklist create returns one stable definition.
const checklistSameKey=`w4c3-checklist-same-${suffix}`
const checklistSame=await Promise.all([
  runAsync(auth(`select public.create_checklist_template('${category.id}','SAME','Same checklist',null,'${items}'::jsonb,'same key','${correlations[18]}','${checklistSameKey}')::text`,2,true)),
  (async()=>{await new Promise((resolve)=>setTimeout(resolve,100)); return runAsync(auth(`select public.create_checklist_template('${category.id}','SAME','Same checklist',null,'${items}'::jsonb,'same key','${correlations[19]}','${checklistSameKey}')::text`,2))})(),
])
if(json(checklistSame[0])===undefined||json(checklistSame[0])!==json(checklistSame[1])) fail('W4C3_CONCURRENCY_FAIL: same-key Checklist create não foi estável.')
const checklist=JSON.parse(json(checklistSame[0]))

// 10. Different keys cannot duplicate a Checklist code.
oneSuccessOneFailure(await Promise.allSettled([0,1].map((index)=>runAsync(auth(
  `select public.create_checklist_template('${category.id}','CHK-DUP','Checklist ${index}',null,'${items}'::jsonb,'uniqueness','${correlations[20+index]}','w4c3-checklist-dup-${suffix}-${index}')`,2,true)))),
  'checklist_templates_tenant_code_uq','Checklist uniqueness')

// 11. Two complete definition replacements with one version have one winner and no mixed items.
oneSuccessOneFailure(await Promise.allSettled([0,1].map((index)=>runAsync(auth(
  `select public.update_checklist_template_definition('${checklist.id}',1,'${category.id}','SAME','Checklist update ${index}',null,
   '[{"position":1,"prompt":"Winner ${index}","response_type":"TEXT","required":true},{"position":2,"prompt":"Only ${index}","response_type":"NUMBER","required":false}]'::jsonb,
   'definition race','${correlations[22+index]}','w4c3-checklist-update-${suffix}-${index}')`,2,true)))),
  'CHECKLIST_TEMPLATE_VERSION_CONFLICT','Checklist atomic definition race')
if(run(`select count(*) from public.checklist_template_items where template_id='${checklist.id}'`) !== '2')
  fail('W4C3_CONCURRENCY_FAIL: definição concorrente deixou itens misturados.')
if(run(`select count(distinct pg_catalog.right(prompt,1)) from public.checklist_template_items where template_id='${checklist.id}'`) !== '1')
  fail('W4C3_CONCURRENCY_FAIL: definição concorrente combinou itens de vencedores distintos.')
if(run(`select usage_context from public.maintenance_reasons where id='${reason.id}'`) !== 'CANCEL_REQUEST')
  fail('W4C3_CONCURRENCY_FAIL: updates concorrentes alteraram o contexto imutável do Reason.')

// 12. Checklist creation and Category inactivation serialize without an orphaned active definition.
const categoryRace=JSON.parse(run(auth(`select public.create_maintenance_category('RACE-CATEGORY','Race category',null,'fixture','${correlations[24]}','w4c3-category-race-${suffix}')::text`,2)))
oneSuccessOneFailure(await stagger(
  auth(`select public.create_checklist_template('${categoryRace.id}','RACE-CHK','Race checklist',null,'${items}'::jsonb,'create first','${correlations[25]}','w4c3-checklist-race-${suffix}')`,2,true),
  auth(`select public.inactivate_maintenance_category('${categoryRace.id}',1,'inactivate second','${correlations[26]}','w4c3-category-off-${suffix}')`,2)),
  'ACTIVE_CHECKLIST_TEMPLATE_DEPENDENCY','Checklist create versus Category inactivate')

run(`set session_replication_role=replica;
delete from public.checklist_template_items where tenant_id=any(array[${tenants.map((id)=>`'${id}'::uuid`).join(',')}]);
delete from public.checklist_templates where tenant_id=any(array[${tenants.map((id)=>`'${id}'::uuid`).join(',')}]);
delete from public.document_types where tenant_id=any(array[${tenants.map((id)=>`'${id}'::uuid`).join(',')}]);
delete from public.maintenance_reasons where tenant_id=any(array[${tenants.map((id)=>`'${id}'::uuid`).join(',')}]);
delete from public.maintenance_subcategories where tenant_id=any(array[${tenants.map((id)=>`'${id}'::uuid`).join(',')}]);
delete from public.maintenance_categories where tenant_id=any(array[${tenants.map((id)=>`'${id}'::uuid`).join(',')}]);
delete from private.command_idempotency where tenant_id=any(array[${tenants.map((id)=>`'${id}'::uuid`).join(',')}]);
delete from private.outbox_events where tenant_id=any(array[${tenants.map((id)=>`'${id}'::uuid`).join(',')}]);
delete from public.history_entries where tenant_id=any(array[${tenants.map((id)=>`'${id}'::uuid`).join(',')}]);
delete from public.audit_events where tenant_id=any(array[${tenants.map((id)=>`'${id}'::uuid`).join(',')}]);
delete from private.authorization_profile_rollouts where tenant_id=any(array[${tenants.map((id)=>`'${id}'::uuid`).join(',')}]);
delete from public.tenant_permission_overrides where tenant_id=any(array[${tenants.map((id)=>`'${id}'::uuid`).join(',')}]);
delete from public.tenant_profile_permissions where tenant_id=any(array[${tenants.map((id)=>`'${id}'::uuid`).join(',')}]);
delete from public.tenant_memberships where tenant_id=any(array[${tenants.map((id)=>`'${id}'::uuid`).join(',')}]);
delete from public.tenant_profiles where tenant_id=any(array[${tenants.map((id)=>`'${id}'::uuid`).join(',')}]);
delete from public.tenant_entitlements where tenant_id=any(array[${tenants.map((id)=>`'${id}'::uuid`).join(',')}]);
delete from public.tenants where id=any(array[${tenants.map((id)=>`'${id}'::uuid`).join(',')}]);
delete from public.app_users where id=any(array[${users.map((id)=>`'${id}'::uuid`).join(',')}]);
delete from auth.users where id=any(array[${users.map((id)=>`'${id}'::uuid`).join(',')}]);`)

process.stdout.write('W4C3_CONCURRENCY_OK: 12 casos cobrem replay, unicidade contextual, optimistic locking, lifecycle e definição atômica sob concorrência real.\n')
