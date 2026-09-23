begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select has_table('public','maintenance_reasons','W4C.3 creates maintenance reasons');
select has_table('public','document_types','W4C.3 creates document types');
select has_table('public','checklist_templates','W4C.3 creates checklist templates');
select has_table('public','checklist_template_items','W4C.3 creates ordered checklist items');
select col_not_null('public','maintenance_reasons','usage_context','reason context is required');
select col_not_null('public','checklist_templates','category_id','checklist category is required');
select ok(exists(select 1 from pg_catalog.pg_constraint where conname='checklist_templates_category_fk'
  and conrelid='public.checklist_templates'::regclass and confrelid='public.maintenance_categories'::regclass),
  'checklist category relation is tenant-safe');
select ok(exists(select 1 from pg_catalog.pg_constraint where conname='checklist_template_items_template_fk'
  and conrelid='public.checklist_template_items'::regclass and confrelid='public.checklist_templates'::regclass),
  'checklist item relation is tenant-safe');
select is((select count(*) from pg_catalog.pg_class r join pg_catalog.pg_namespace n on n.oid=r.relnamespace
  where n.nspname='public' and r.relname in ('maintenance_reasons','document_types','checklist_templates','checklist_template_items')
    and r.relrowsecurity and r.relforcerowsecurity),4::bigint,'all W4C.3 tables enable and force RLS');
select is((select count(*) from information_schema.table_privileges where table_schema='public'
  and table_name in ('maintenance_reasons','document_types','checklist_templates','checklist_template_items')
  and grantee='authenticated' and privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE','TRIGGER')),0::bigint,
  'authenticated has no direct W4C.3 mutation privilege');
select is((select count(*) from information_schema.table_privileges where table_schema='public'
  and table_name='checklist_template_items' and grantee='authenticated'),0::bigint,
  'checklist items have no independent client table boundary');

select has_function('public','create_maintenance_reason',array['text','text','text','text','text','uuid','text'],'reason create exists');
select has_function('public','update_maintenance_reason',array['uuid','bigint','text','text','text','text','uuid','text'],'reason update exists');
select has_function('public','inactivate_maintenance_reason',array['uuid','bigint','text','uuid','text'],'reason inactivate exists');
select has_function('public','reactivate_maintenance_reason',array['uuid','bigint','text','uuid','text'],'reason reactivate exists');
select has_function('public','create_document_type',array['text','text','text','text','uuid','text'],'document type create exists');
select has_function('public','update_document_type',array['uuid','bigint','text','text','text','text','uuid','text'],'document type update exists');
select has_function('public','inactivate_document_type',array['uuid','bigint','text','uuid','text'],'document type inactivate exists');
select has_function('public','reactivate_document_type',array['uuid','bigint','text','uuid','text'],'document type reactivate exists');
select has_function('public','create_checklist_template',array['uuid','text','text','text','jsonb','text','uuid','text'],'checklist create exists');
select has_function('public','update_checklist_template_definition',array['uuid','bigint','uuid','text','text','text','jsonb','text','uuid','text'],'atomic checklist definition update exists');
select has_function('public','inactivate_checklist_template',array['uuid','bigint','text','uuid','text'],'checklist inactivate exists');
select has_function('public','reactivate_checklist_template',array['uuid','bigint','text','uuid','text'],'checklist reactivate exists');
select has_function('public','list_maintenance_reasons',array['text','text','text','integer','integer'],'reason list exists');
select has_function('public','get_maintenance_reason',array['uuid'],'reason detail exists');
select has_function('public','lookup_maintenance_reasons',array['text','text','integer'],'reason lookup exists');
select has_function('public','list_document_types',array['text','text','integer','integer'],'document type list exists');
select has_function('public','get_document_type',array['uuid'],'document type detail exists');
select has_function('public','lookup_document_types',array['text','integer'],'document type lookup exists');
select has_function('public','list_checklist_templates',array['uuid','text','text','integer','integer'],'checklist list exists');
select has_function('public','get_checklist_template',array['uuid'],'checklist detail exists');
select has_function('public','lookup_checklist_templates',array['uuid','text','integer'],'checklist lookup exists');

select is((select count(*) from public.maintenance_reasons),0::bigint,'W4C.3 deliberately creates no reason seeds');
select is((select count(*) from private.catalog_templates where template_key='cw_maintenance_taxonomy' and template_version=1),1::bigint,
  'Template CW v1 identity remains unchanged');
select is((select count(*) from private.catalog_template_entries e join private.catalog_templates t on t.id=e.template_id
  where t.template_key='cw_maintenance_taxonomy' and t.template_version=1 and e.entry_kind='maintenance_category'),11::bigint,
  'Template CW v1 still has exactly eleven categories');
select is((select count(*) from private.catalog_template_entries e join private.catalog_templates t on t.id=e.template_id
  where t.template_key='cw_maintenance_taxonomy' and t.template_version=1 and e.entry_kind='maintenance_subcategory'),39::bigint,
  'Template CW v1 still has exactly thirty-nine subcategories');

insert into auth.users(id,aud,role,email,email_confirmed_at,created_at,updated_at) values
('4c700000-0000-4000-8000-000000000001','authenticated','authenticated','w4c3-manager-a@example.invalid',statement_timestamp(),statement_timestamp(),statement_timestamp()),
('4c700000-0000-4000-8000-000000000002','authenticated','authenticated','w4c3-technician-a@example.invalid',statement_timestamp(),statement_timestamp(),statement_timestamp()),
('4c700000-0000-4000-8000-000000000003','authenticated','authenticated','w4c3-manager-b@example.invalid',statement_timestamp(),statement_timestamp(),statement_timestamp());

create temporary table w4c3_tenant_a as select * from public.bootstrap_initial_tenant(
  '4c700000-0000-4000-8000-000000000001','W4C.3 Tenant A','4c710000-0000-4000-8000-000000000001');
insert into public.tenant_memberships(id,tenant_id,user_id,status,joined_at,created_by,profile_id,profile_assigned_at,profile_assigned_by)
select '4c720000-0000-4000-8000-000000000002',b.tenant_id,'4c700000-0000-4000-8000-000000000002','active',statement_timestamp(),
  '4c700000-0000-4000-8000-000000000001',p.id,statement_timestamp(),'4c700000-0000-4000-8000-000000000001'
from w4c3_tenant_a b join public.tenant_profiles p on p.tenant_id=b.tenant_id and p.template_key='technician';

insert into public.tenants(id,tenant_ref,display_name,status,created_by) values
('4c730000-0000-4000-8000-000000000002','4c740000-0000-4000-8000-000000000002','W4C.3 Tenant B','active','4c700000-0000-4000-8000-000000000003');
insert into public.tenant_entitlements(tenant_id,module_key,enabled,created_by)
values('4c730000-0000-4000-8000-000000000002','maintenance',true,'4c700000-0000-4000-8000-000000000003');
do $$ declare manager_profile_id uuid; begin
  perform * from private.provision_tenant_authorization('4c730000-0000-4000-8000-000000000002',null,
    '4c700000-0000-4000-8000-000000000003','4c710000-0000-4000-8000-000000000002');
  select id into strict manager_profile_id from public.tenant_profiles
  where tenant_id='4c730000-0000-4000-8000-000000000002' and template_key='manager';
  insert into public.tenant_memberships(id,tenant_id,user_id,status,joined_at,created_by,profile_id,profile_assigned_at,profile_assigned_by)
  values('4c720000-0000-4000-8000-000000000003','4c730000-0000-4000-8000-000000000002','4c700000-0000-4000-8000-000000000003',
    'active',statement_timestamp(),'4c700000-0000-4000-8000-000000000003',manager_profile_id,statement_timestamp(),'4c700000-0000-4000-8000-000000000003');
end $$;

-- Manager intentionally receives only the non-baseline mutation authorities needed by this fixture.
insert into public.tenant_permission_overrides(tenant_id,membership_id,permission_id,effect,created_by,updated_by)
select b.tenant_id,m.id,p.id,'allow',m.user_id,m.user_id from w4c3_tenant_a b
join public.tenant_memberships m on m.tenant_id=b.tenant_id and m.user_id='4c700000-0000-4000-8000-000000000001'
join public.permission_catalog p on p.code in (
  'maintenance.maintenance_categories.reactivate.all_tenant',
  'maintenance.maintenance_reasons.reactivate.all_tenant',
  'maintenance.document_types.create.all_tenant','maintenance.document_types.update.all_tenant',
  'maintenance.document_types.inactivate.all_tenant','maintenance.document_types.reactivate.all_tenant',
  'maintenance.checklist_templates.create.all_tenant','maintenance.checklist_templates.update.all_tenant',
  'maintenance.checklist_templates.inactivate.all_tenant','maintenance.checklist_templates.reactivate.all_tenant'
);

create temporary table w4c3_results(kind text primary key,result jsonb not null);
grant select,insert,update on table w4c3_results to authenticated;
grant select on table w4c3_tenant_a to authenticated;
set local "request.jwt.claim.sub"='4c700000-0000-4000-8000-000000000001';
set local role authenticated;
insert into w4c3_results values('category',public.create_maintenance_category('W4C3','W4C3 category',null,'fixture category',
  '4c750000-0000-4000-8000-000000000001','w4c3-category-0001'));
insert into w4c3_results values('reason',public.create_maintenance_reason('CANCEL_REQUEST','DUP','Cancel reason',null,'fixture reason',
  '4c750000-0000-4000-8000-000000000002','w4c3-reason-0001'));
insert into w4c3_results values('reason-other-context',public.create_maintenance_reason('REJECT_REQUEST','DUP','Reject reason',null,'fixture reason',
  '4c750000-0000-4000-8000-000000000003','w4c3-reason-0002'));
insert into w4c3_results values('document',public.create_document_type('REPORT','Report',null,'fixture document',
  '4c750000-0000-4000-8000-000000000004','w4c3-document-0001'));
insert into w4c3_results values('checklist',public.create_checklist_template(
  (select (result->>'id')::uuid from w4c3_results where kind='category'),'CHK','Checklist',null,
  '[{"position":2,"prompt":"Second","response_type":"TEXT","required":false},{"position":1,"prompt":"First","response_type":"YES_NO","required":true}]',
  'fixture checklist','4c750000-0000-4000-8000-000000000005','w4c3-checklist-0001'));

select is((select array_agg(k order by k) from jsonb_object_keys((select result from w4c3_results where kind='reason')) k),
  array['command_correlation_id','id','status','version']::text[],'reason command result is strict');
select is((select array_agg(k order by k) from jsonb_object_keys((select result from w4c3_results where kind='document')) k),
  array['command_correlation_id','id','status','version']::text[],'document command result is strict');
select is((select array_agg(k order by k) from jsonb_object_keys((select result from w4c3_results where kind='checklist')) k),
  array['command_correlation_id','id','status','version']::text[],'checklist command result is strict');
select is((select array_agg(item->>'position' order by ordinal) from public.get_checklist_template(
  (select (result->>'id')::uuid from w4c3_results where kind='checklist')) detail
  cross join lateral jsonb_array_elements(detail.items) with ordinality element(item,ordinal)),array['1','2']::text[],
  'checklist detail returns the complete definition in position order');
select is(public.create_maintenance_reason('CANCEL_REQUEST','DUP','Cancel reason',null,'fixture reason',
  '4c750000-0000-4000-8000-000000000099','w4c3-reason-0001'),
  (select result from w4c3_results where kind='reason'),'same idempotency key replays the stable result');
select is((select count(*) from public.list_maintenance_reasons(null,null,null,50,0)),2::bigint,
  'reason administrative list returns both contexts');
select is((select count(*) from public.get_maintenance_reason(
  (select (result->>'id')::uuid from w4c3_results where kind='reason'))),1::bigint,'reason detail returns its tenant record');
select is((select count(*) from public.list_document_types(null,null,50,0)),1::bigint,'document type administrative list works');
select is((select count(*) from public.get_document_type(
  (select (result->>'id')::uuid from w4c3_results where kind='document'))),1::bigint,'document type detail works');
select is((select count(*) from public.list_checklist_templates(null,null,null,50,0)),1::bigint,'checklist administrative list works');
select throws_ok($$select public.create_maintenance_reason('UNKNOWN','BAD','Bad',null,'invalid context',
  '4c750000-0000-4000-8000-000000000006','w4c3-invalid-context-0001')$$,'22023','INVALID_MAINTENANCE_REASON_CONTEXT','reason context is closed');
select throws_ok($$select public.create_maintenance_reason('CANCEL_REQUEST','dup','Duplicate',null,'duplicate',
  '4c750000-0000-4000-8000-000000000007','w4c3-reason-duplicate-0001')$$,'23505',null,
  'reason code is unique only inside its tenant and context');
select throws_ok($$select public.update_document_type(
  (select (result->>'id')::uuid from w4c3_results where kind='document'),99,'REPORT','Stale',null,'stale',
  '4c750000-0000-4000-8000-000000000008','w4c3-document-stale-0001')$$,'P0001','SUPPORTING_CATALOG_VERSION_CONFLICT',
  'document optimistic locking rejects stale versions');
select lives_ok($$select public.update_maintenance_reason(
  (select (result->>'id')::uuid from w4c3_results where kind='reason'),1,'DUP','Cancel reason updated',null,'update reason',
  '4c750000-0000-4000-8000-000000000016','w4c3-reason-update-0001')$$,'reason update command works');
select lives_ok($$select public.inactivate_maintenance_reason(
  (select (result->>'id')::uuid from w4c3_results where kind='reason'),2,'inactivate reason',
  '4c750000-0000-4000-8000-000000000017','w4c3-reason-off-0001')$$,'reason inactivate command works');
select is((select count(*) from public.lookup_maintenance_reasons('CANCEL_REQUEST',null,20)),0::bigint,'inactive reason leaves lookup');
select lives_ok($$select public.reactivate_maintenance_reason(
  (select (result->>'id')::uuid from w4c3_results where kind='reason'),3,'reactivate reason',
  '4c750000-0000-4000-8000-000000000018','w4c3-reason-on-0001')$$,'reason reactivate command works');
select lives_ok($$select public.update_document_type(
  (select (result->>'id')::uuid from w4c3_results where kind='document'),1,'REPORT','Report updated',null,'update document',
  '4c750000-0000-4000-8000-000000000019','w4c3-document-update-0001')$$,'document update command works');
select lives_ok($$select public.inactivate_document_type(
  (select (result->>'id')::uuid from w4c3_results where kind='document'),2,'inactivate document',
  '4c750000-0000-4000-8000-000000000020','w4c3-document-off-0001')$$,'document inactivate command works');
select is((select count(*) from public.lookup_document_types(null,20)),0::bigint,'inactive document type leaves lookup');
select lives_ok($$select public.reactivate_document_type(
  (select (result->>'id')::uuid from w4c3_results where kind='document'),3,'reactivate document',
  '4c750000-0000-4000-8000-000000000021','w4c3-document-on-0001')$$,'document reactivate command works');
select lives_ok($$select public.update_checklist_template_definition(
  (select (result->>'id')::uuid from w4c3_results where kind='checklist'),1,
  (select (result->>'id')::uuid from w4c3_results where kind='category'),'CHK','Checklist updated',null,
  '[{"position":1,"prompt":"Updated","response_type":"DONE_NOT_DONE","required":true}]',
  'replace definition','4c750000-0000-4000-8000-000000000022','w4c3-checklist-update-0001')$$,
  'checklist definition update replaces items atomically');
select is((select jsonb_array_length(items) from public.get_checklist_template(
  (select (result->>'id')::uuid from w4c3_results where kind='checklist'))),1,
  'updated checklist exposes only the replacement definition');
reset role;
select throws_ok($$update public.maintenance_reasons set usage_context='PAUSE_WORK_ORDER'
  where id=(select (result->>'id')::uuid from w4c3_results where kind='reason')$$,'42501','MAINTENANCE_REASON_CONTEXT_IMMUTABLE',
  'reason context remains immutable even to the migration owner');
set local role authenticated;
select throws_ok($$select public.inactivate_maintenance_category(
  (select (result->>'id')::uuid from w4c3_results where kind='category'),1,'active checklist guard',
  '4c750000-0000-4000-8000-000000000009','w4c3-category-guard-0001')$$,'23514','ACTIVE_CHECKLIST_TEMPLATE_DEPENDENCY',
  'category cannot inactivate while an active checklist depends on it');
select lives_ok($$select public.inactivate_checklist_template(
  (select (result->>'id')::uuid from w4c3_results where kind='checklist'),2,'inactivate checklist',
  '4c750000-0000-4000-8000-000000000010','w4c3-checklist-off-0001')$$,'checklist can be inactivated');
select is((select count(*) from public.lookup_checklist_templates(null,null,20)),0::bigint,'inactive checklist leaves lookup');
select lives_ok($$select public.inactivate_maintenance_category(
  (select (result->>'id')::uuid from w4c3_results where kind='category'),1,'inactivate category',
  '4c750000-0000-4000-8000-000000000011','w4c3-category-off-0001')$$,'category can inactivate after checklist');
select throws_ok($$select public.reactivate_checklist_template(
  (select (result->>'id')::uuid from w4c3_results where kind='checklist'),3,'inactive category guard',
  '4c750000-0000-4000-8000-000000000012','w4c3-checklist-on-guard-0001')$$,'23514','MAINTENANCE_CATEGORY_INACTIVE',
  'checklist cannot reactivate under an inactive category');
select lives_ok($$select public.reactivate_maintenance_category(
  (select (result->>'id')::uuid from w4c3_results where kind='category'),2,'reactivate category',
  '4c750000-0000-4000-8000-000000000013','w4c3-category-on-0001')$$,'category can reactivate');
select lives_ok($$select public.reactivate_checklist_template(
  (select (result->>'id')::uuid from w4c3_results where kind='checklist'),3,'reactivate checklist',
  '4c750000-0000-4000-8000-000000000014','w4c3-checklist-on-0001')$$,'checklist can reactivate under active category');
reset role;

set local "request.jwt.claim.sub"='4c700000-0000-4000-8000-000000000002';
set local role authenticated;
select is((select count(*) from public.lookup_maintenance_reasons('CANCEL_REQUEST',null,20)),1::bigint,
  'Technician baseline can discover active reasons');
select is((select count(*) from public.lookup_document_types(null,20)),1::bigint,
  'Technician baseline can discover active document types');
select is((select count(*) from public.lookup_checklist_templates(null,null,20)),1::bigint,
  'Technician baseline can discover active checklist templates');
select throws_ok($$select public.create_document_type('DENIED','Denied',null,'no authority',
  '4c750000-0000-4000-8000-000000000015','w4c3-denied-0001')$$,'42501','AUTHORIZATION_DENIED',
  'lookup authority does not imply mutation authority');
select throws_ok($$select count(*) from public.checklist_template_items$$,'42501',null,
  'checklist items cannot be queried independently by clients');
select throws_ok($$select private.validate_checklist_template_items('[]')$$,'42501',null,
  'private W4C.3 helpers are not client callable');
reset role;

set local "request.jwt.claim.sub"='4c700000-0000-4000-8000-000000000003';
set local role authenticated;
select is((select count(*) from public.get_maintenance_reason(
  (select (result->>'id')::uuid from w4c3_results where kind='reason'))),0::bigint,
  'cross-tenant detail is anti-enumerating');
reset role;

update public.tenant_entitlements set enabled=false
where tenant_id='4c730000-0000-4000-8000-000000000002' and module_key='maintenance';
set local "request.jwt.claim.sub"='4c700000-0000-4000-8000-000000000003';
set local role authenticated;
select throws_ok($$select * from public.lookup_maintenance_reasons('CANCEL_REQUEST',null,20)$$,
  '42501','AUTHORIZATION_DENIED','disabled maintenance entitlement removes W4C.3 authority');
reset role;

select is((select count(*) from (
  (select audit.event_type,audit.entity_type,audit.entity_id,audit.correlation_id
   from public.audit_events audit where audit.correlation_id in (
     '4c750000-0000-4000-8000-000000000002','4c750000-0000-4000-8000-000000000003',
     '4c750000-0000-4000-8000-000000000004','4c750000-0000-4000-8000-000000000005'
   ) except all values
     ('maintenance.reason.created','maintenance_reason',(select (result->>'id')::uuid from w4c3_results where kind='reason'),'4c750000-0000-4000-8000-000000000002'::uuid),
     ('maintenance.reason.created','maintenance_reason',(select (result->>'id')::uuid from w4c3_results where kind='reason-other-context'),'4c750000-0000-4000-8000-000000000003'::uuid),
     ('cadastros.document_type.created','document_type',(select (result->>'id')::uuid from w4c3_results where kind='document'),'4c750000-0000-4000-8000-000000000004'::uuid),
     ('maintenance.checklist_template.created','checklist_template',(select (result->>'id')::uuid from w4c3_results where kind='checklist'),'4c750000-0000-4000-8000-000000000005'::uuid))
  union all
  (values
     ('maintenance.reason.created','maintenance_reason',(select (result->>'id')::uuid from w4c3_results where kind='reason'),'4c750000-0000-4000-8000-000000000002'::uuid),
     ('maintenance.reason.created','maintenance_reason',(select (result->>'id')::uuid from w4c3_results where kind='reason-other-context'),'4c750000-0000-4000-8000-000000000003'::uuid),
     ('cadastros.document_type.created','document_type',(select (result->>'id')::uuid from w4c3_results where kind='document'),'4c750000-0000-4000-8000-000000000004'::uuid),
     ('maintenance.checklist_template.created','checklist_template',(select (result->>'id')::uuid from w4c3_results where kind='checklist'),'4c750000-0000-4000-8000-000000000005'::uuid)
   except all select audit.event_type,audit.entity_type,audit.entity_id,audit.correlation_id
   from public.audit_events audit where audit.correlation_id in (
     '4c750000-0000-4000-8000-000000000002','4c750000-0000-4000-8000-000000000003',
     '4c750000-0000-4000-8000-000000000004','4c750000-0000-4000-8000-000000000005'
   ))
) mismatch),0::bigint,'the four supporting creates emit exactly one Audit fact each');
select is((select count(*) from public.history_entries where aggregate_type in (
  'maintenance_reason','document_type','checklist_template') and history_type like '%.created'),4::bigint,
  'the four supporting creates across three domains emit History facts');
select is((select count(*) from private.outbox_events where aggregate_type in (
  'maintenance_reason','document_type','checklist_template') and event_type like '%.created'),4::bigint,
  'the four supporting creates across three domains emit Event facts');
select is((select count(*) from private.command_idempotency where command_name in (
  'maintenance.create_maintenance_reason','maintenance.create_document_type','maintenance.create_checklist_template')),4::bigint,
  'the four supporting create commands persist idempotency state');

select * from finish();
rollback;
