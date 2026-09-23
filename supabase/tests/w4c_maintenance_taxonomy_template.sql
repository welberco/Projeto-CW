begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select has_table('public','maintenance_categories','W4C.2 creates maintenance categories');
select has_table('public','maintenance_subcategories','W4C.2 creates maintenance subcategories');
select has_table('private','catalog_templates','W4C.2 creates the private template catalog');
select has_table('private','catalog_template_entries','W4C.2 creates deterministic private template entries');
select has_table('private','catalog_template_applications','W4C.2 creates the private application ledger');
select col_is_null('public','maintenance_categories','code','category code is optional');
select col_is_null('public','maintenance_subcategories','code','subcategory code is optional');
select ok(exists(select 1 from pg_catalog.pg_constraint where conname='maintenance_subcategories_category_fk'
  and conrelid='public.maintenance_subcategories'::regclass and confrelid='public.maintenance_categories'::regclass and contype='f'),
  'subcategory relation is structurally tenant-safe');
select is((select count(*) from pg_catalog.pg_class r join pg_catalog.pg_namespace n on n.oid=r.relnamespace
  where n.nspname='public' and r.relname in ('maintenance_categories','maintenance_subcategories')
    and r.relrowsecurity and r.relforcerowsecurity),2::bigint,'both public W4C.2 tables enable and force RLS');
select is((select count(*) from information_schema.table_privileges where table_schema='public'
  and table_name in ('maintenance_categories','maintenance_subcategories') and grantee='authenticated'
  and privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE','TRIGGER')),0::bigint,'authenticated has no direct mutation privilege');
select is((select count(*) from information_schema.table_privileges where table_schema='private'
  and table_name in ('catalog_templates','catalog_template_entries','catalog_template_applications')
  and grantee in ('PUBLIC','anon','authenticated','service_role','cw_worker')),0::bigint,'private template tables are not exposed');

select has_function('public','create_maintenance_category',array['text','text','text','text','uuid','text'],'category create exists');
select has_function('public','update_maintenance_category',array['uuid','bigint','text','text','text','text','uuid','text'],'category update exists');
select has_function('public','inactivate_maintenance_category',array['uuid','bigint','text','uuid','text'],'category inactivate exists');
select has_function('public','reactivate_maintenance_category',array['uuid','bigint','text','uuid','text'],'category reactivate exists');
select has_function('public','create_maintenance_subcategory',array['uuid','text','text','text','text','uuid','text'],'subcategory create exists');
select has_function('public','update_maintenance_subcategory',array['uuid','bigint','uuid','text','text','text','text','uuid','text'],'subcategory update exists');
select has_function('public','inactivate_maintenance_subcategory',array['uuid','bigint','text','uuid','text'],'subcategory inactivate exists');
select has_function('public','reactivate_maintenance_subcategory',array['uuid','bigint','text','uuid','text'],'subcategory reactivate exists');
select has_function('public','list_maintenance_categories',array['text','text','integer','integer'],'category list exists');
select has_function('public','get_maintenance_category',array['uuid'],'category detail exists');
select has_function('public','lookup_maintenance_categories',array['text','integer'],'category lookup exists');
select has_function('public','list_maintenance_subcategories',array['uuid','text','text','integer','integer'],'subcategory list exists');
select has_function('public','get_maintenance_subcategory',array['uuid'],'subcategory detail exists');
select has_function('public','lookup_maintenance_subcategories',array['uuid','text','integer'],'subcategory lookup exists');
select has_function('public','get_cw_catalog_template_preview',array['text','bigint'],'template preview exists');
select has_function('public','apply_cw_catalog_template',array['text','bigint','text','uuid','text'],'template apply exists');

select is((select count(*) from private.catalog_templates where template_key='cw_maintenance_taxonomy' and template_version=1 and status='active'),1::bigint,'one active Template CW v1 exists');
select is((select count(*) from private.catalog_template_entries e join private.catalog_templates t on t.id=e.template_id
  where t.template_key='cw_maintenance_taxonomy' and e.entry_kind='maintenance_category'),11::bigint,'Template CW has exactly eleven categories');
select is((select count(*) from private.catalog_template_entries e join private.catalog_templates t on t.id=e.template_id
  where t.template_key='cw_maintenance_taxonomy' and e.entry_kind='maintenance_subcategory'),39::bigint,'Template CW has exactly thirty-nine subcategories');
select is((select count(*) from private.catalog_template_entries where name='Iluminação de emergência'),2::bigint,'legitimate repeated label is preserved in two categories');
select is((select name from private.catalog_template_entries where entry_key='other_residual'),'classificação genérica residual','the frozen residual classification is exact');

insert into auth.users(id,aud,role,email,email_confirmed_at,created_at,updated_at) values
('4c600000-0000-4000-8000-000000000001','authenticated','authenticated','w4c2-manager-a@example.invalid',statement_timestamp(),statement_timestamp(),statement_timestamp()),
('4c600000-0000-4000-8000-000000000002','authenticated','authenticated','w4c2-requester-a@example.invalid',statement_timestamp(),statement_timestamp(),statement_timestamp()),
('4c600000-0000-4000-8000-000000000003','authenticated','authenticated','w4c2-manager-b@example.invalid',statement_timestamp(),statement_timestamp(),statement_timestamp()),
('4c600000-0000-4000-8000-000000000004','authenticated','authenticated','w4c2-technician-a@example.invalid',statement_timestamp(),statement_timestamp(),statement_timestamp()),
('4c600000-0000-4000-8000-000000000005','authenticated','authenticated','w4c2-assistant-a@example.invalid',statement_timestamp(),statement_timestamp(),statement_timestamp());

create temporary table w4c2_tenant_a as select * from public.bootstrap_initial_tenant(
  '4c600000-0000-4000-8000-000000000001','W4C.2 Tenant A','4c610000-0000-4000-8000-000000000001');
insert into public.tenant_memberships(id,tenant_id,user_id,status,joined_at,created_by,profile_id,profile_assigned_at,profile_assigned_by)
select fixture.membership_id,b.tenant_id,fixture.user_id,'active',statement_timestamp(),
  '4c600000-0000-4000-8000-000000000001',p.id,statement_timestamp(),'4c600000-0000-4000-8000-000000000001'
from w4c2_tenant_a b
cross join (values
  ('4c620000-0000-4000-8000-000000000002'::uuid,'4c600000-0000-4000-8000-000000000002'::uuid,'requester'::text),
  ('4c620000-0000-4000-8000-000000000004'::uuid,'4c600000-0000-4000-8000-000000000004'::uuid,'technician'::text),
  ('4c620000-0000-4000-8000-000000000005'::uuid,'4c600000-0000-4000-8000-000000000005'::uuid,'assistant'::text)
) fixture(membership_id,user_id,template_key)
join public.tenant_profiles p on p.tenant_id=b.tenant_id and p.template_key=fixture.template_key;

insert into public.tenants(id,tenant_ref,display_name,status,created_by) values
('4c630000-0000-4000-8000-000000000002','4c640000-0000-4000-8000-000000000002','W4C.2 Tenant B','active','4c600000-0000-4000-8000-000000000003');
insert into public.tenant_entitlements(tenant_id,module_key,enabled,created_by)
values('4c630000-0000-4000-8000-000000000002','maintenance',true,'4c600000-0000-4000-8000-000000000003');
do $$ declare manager_profile_id uuid; begin
  perform * from private.provision_tenant_authorization('4c630000-0000-4000-8000-000000000002',null,
    '4c600000-0000-4000-8000-000000000003','4c610000-0000-4000-8000-000000000002');
  select id into strict manager_profile_id from public.tenant_profiles where tenant_id='4c630000-0000-4000-8000-000000000002' and template_key='manager';
  insert into public.tenant_memberships(id,tenant_id,user_id,status,joined_at,created_by,profile_id,profile_assigned_at,profile_assigned_by)
  values('4c620000-0000-4000-8000-000000000003','4c630000-0000-4000-8000-000000000002','4c600000-0000-4000-8000-000000000003',
    'active',statement_timestamp(),'4c600000-0000-4000-8000-000000000003',manager_profile_id,statement_timestamp(),'4c600000-0000-4000-8000-000000000003');
end $$;

-- Reactivate is deliberately absent from baselines; grant it explicitly only for lifecycle coverage.
insert into public.tenant_permission_overrides(tenant_id,membership_id,permission_id,effect,created_by,updated_by)
select b.tenant_id,m.id,p.id,'allow',m.user_id,m.user_id from w4c2_tenant_a b
join public.tenant_memberships m on m.tenant_id=b.tenant_id and m.user_id='4c600000-0000-4000-8000-000000000001'
join public.permission_catalog p on p.code in ('maintenance.maintenance_categories.reactivate.all_tenant','maintenance.maintenance_subcategories.reactivate.all_tenant');

create temporary table w4c2_results(kind text primary key,result jsonb not null);
grant select,insert,update on table w4c2_results to authenticated;
grant select on table w4c2_tenant_a to authenticated;
set local "request.jwt.claim.sub"='4c600000-0000-4000-8000-000000000001';
set local role authenticated;
insert into w4c2_results values ('category',public.create_maintenance_category('ELEC','Electrical',null,'create category',
  '4c650000-0000-4000-8000-000000000001','w4c2-category-create-0001'));
insert into w4c2_results values ('subcategory',public.create_maintenance_subcategory(
  (select (result->>'id')::uuid from w4c2_results where kind='category'),'LIGHT','Lighting',null,'create subcategory',
  '4c650000-0000-4000-8000-000000000002','w4c2-subcategory-create-0001'));
reset role;

select is((select array_agg(k order by k) from jsonb_object_keys((select result from w4c2_results where kind='category')) k),
  array['command_correlation_id','id','status','version']::text[],'category command result is strict');
select is((select array_agg(k order by k) from jsonb_object_keys((select result from w4c2_results where kind='subcategory')) k),
  array['command_correlation_id','id','status','version']::text[],'subcategory command result is strict');
select is((select count(*) from public.maintenance_subcategories s join public.maintenance_categories c
  on c.tenant_id=s.tenant_id and c.id=s.category_id where s.id=(select (result->>'id')::uuid from w4c2_results where kind='subcategory')),
  1::bigint,'subcategory belongs to a category in the same tenant');

set local "request.jwt.claim.sub"='4c600000-0000-4000-8000-000000000001';
set local role authenticated;
select throws_ok($$select public.create_maintenance_category('ELEC','Duplicate',null,'duplicate code',
  '4c650000-0000-4000-8000-000000000003','w4c2-category-duplicate-0001')$$,'23505',null,'normalized category code is unique per tenant');
select throws_ok($$select public.update_maintenance_category(
  (select (result->>'id')::uuid from w4c2_results where kind='category'),99,'ELEC','Stale',null,'stale update',
  '4c650000-0000-4000-8000-000000000004','w4c2-category-stale-0001')$$,'P0001','MAINTENANCE_TAXONOMY_VERSION_CONFLICT','optimistic locking rejects stale category update');
select throws_ok($$select public.inactivate_maintenance_category(
  (select (result->>'id')::uuid from w4c2_results where kind='category'),1,'active child guard',
  '4c650000-0000-4000-8000-000000000005','w4c2-category-guard-0001')$$,'23514','ACTIVE_MAINTENANCE_SUBCATEGORY_DEPENDENCY','category cannot inactivate with active subcategory');
select lives_ok($$select public.inactivate_maintenance_subcategory(
  (select (result->>'id')::uuid from w4c2_results where kind='subcategory'),1,'inactivate child',
  '4c650000-0000-4000-8000-000000000006','w4c2-subcategory-inactivate-0001')$$,'subcategory can be inactivated');
select lives_ok($$select public.inactivate_maintenance_category(
  (select (result->>'id')::uuid from w4c2_results where kind='category'),1,'inactivate parent',
  '4c650000-0000-4000-8000-000000000007','w4c2-category-inactivate-0001')$$,'category can be inactivated after children');
select is((select count(*) from public.lookup_maintenance_categories(null,20)),0::bigint,'inactive categories leave normal lookup');
select is((select count(*) from public.lookup_maintenance_subcategories(null,null,20)),0::bigint,'inactive subcategories leave normal lookup');
select is((select count(*) from public.list_maintenance_categories(null,'inactive',50,0)),1::bigint,'administrative list represents inactive categories');
select throws_ok($$select public.reactivate_maintenance_subcategory(
  (select (result->>'id')::uuid from w4c2_results where kind='subcategory'),2,'inactive parent guard',
  '4c650000-0000-4000-8000-000000000008','w4c2-subcategory-reactivate-guard-0001')$$,'23514','MAINTENANCE_CATEGORY_INACTIVE','subcategory cannot reactivate under inactive category');
select lives_ok($$select public.reactivate_maintenance_category(
  (select (result->>'id')::uuid from w4c2_results where kind='category'),2,'reactivate parent',
  '4c650000-0000-4000-8000-000000000009','w4c2-category-reactivate-0001')$$,'category can be reactivated with exact permission');
select lives_ok($$select public.reactivate_maintenance_subcategory(
  (select (result->>'id')::uuid from w4c2_results where kind='subcategory'),2,'reactivate child',
  '4c650000-0000-4000-8000-000000000010','w4c2-subcategory-reactivate-0001')$$,'subcategory can be reactivated under active category');
select is((select count(*) from public.lookup_maintenance_categories(null,20)),1::bigint,'category lookup exposes active records only');
select is((select count(*) from public.lookup_maintenance_subcategories(
  (select (result->>'id')::uuid from w4c2_results where kind='category'),null,20)),1::bigint,'subcategory lookup applies the tenant-safe category filter');
select is((select count(*) from public.get_maintenance_category('4c660000-0000-4000-8000-000000000099')),0::bigint,'get is anti-enumerating for unavailable ids');
reset role;

insert into public.tenant_permission_overrides(tenant_id,membership_id,permission_id,effect,created_by,updated_by)
select b.tenant_id,m.id,p.id,'deny',m.user_id,m.user_id from w4c2_tenant_a b
join public.tenant_memberships m on m.tenant_id=b.tenant_id and m.user_id='4c600000-0000-4000-8000-000000000001'
join public.permission_catalog p on p.code='maintenance.maintenance_categories.lookup.all_tenant';
set local "request.jwt.claim.sub"='4c600000-0000-4000-8000-000000000001';
set local role authenticated;
select lives_ok($$select public.create_maintenance_category('NO-LOOKUP','Mutation without lookup',null,'reference authorization proof',
  '4c650000-0000-4000-8000-000000000015','w4c2-category-no-lookup-0001')$$,'category create does not require lookup authority');
select throws_ok($$select * from public.lookup_maintenance_categories(null,20)$$,'42501','AUTHORIZATION_DENIED','the exact lookup deny remains effective');
select throws_ok($$select public.apply_cw_catalog_template('cw_maintenance_taxonomy',1,'no merge',
  '4c650000-0000-4000-8000-000000000016','w4c2-template-nonempty-0001')$$,'23514','MAINTENANCE_TAXONOMY_NOT_EMPTY',
  'Template CW cannot merge into a partially populated taxonomy');
reset role;

set local "request.jwt.claim.sub"='4c600000-0000-4000-8000-000000000002';
set local role authenticated;
select throws_ok($$select public.create_maintenance_category('DENIED','Denied',null,'no permission',
  '4c650000-0000-4000-8000-000000000011','w4c2-category-denied-0001')$$,'42501','AUTHORIZATION_DENIED','actor without create permission is denied');
-- Requester has category/subcategory lookup but no create: lookup is discovery, not mutation authority.
select is((select count(*) from public.lookup_maintenance_categories(null,20)),2::bigint,'lookup permission works independently');
select throws_ok($$select public.get_cw_catalog_template_preview()$$,'42501','AUTHORIZATION_DENIED','Requester cannot preview the Template CW without apply');
select throws_ok($$select count(*) from private.catalog_templates$$,'42501',null,'Requester cannot read private template tables directly');
reset role;

set local "request.jwt.claim.sub"='4c600000-0000-4000-8000-000000000004';
set local role authenticated;
select throws_ok($$select public.get_cw_catalog_template_preview()$$,'42501','AUTHORIZATION_DENIED','Technician cannot preview the Template CW without apply');
reset role;

set local "request.jwt.claim.sub"='4c600000-0000-4000-8000-000000000005';
set local role authenticated;
select throws_ok($$select public.get_cw_catalog_template_preview()$$,'42501','AUTHORIZATION_DENIED','Assistant cannot preview the Template CW without apply');
reset role;

set local "request.jwt.claim.sub"='4c600000-0000-4000-8000-000000000003';
set local role authenticated;
select is((public.get_cw_catalog_template_preview()->>'category_count')::integer,11,'preview returns eleven categories');
select is((public.get_cw_catalog_template_preview()->>'subcategory_count')::integer,39,'preview returns thirty-nine subcategories');
insert into w4c2_results values ('application',public.apply_cw_catalog_template('cw_maintenance_taxonomy',1,'apply template',
  '4c650000-0000-4000-8000-000000000012','w4c2-template-apply-0001'));
select is((select (result->>'category_count')::integer from w4c2_results where kind='application'),11,'application creates eleven categories');
select is((select (result->>'subcategory_count')::integer from w4c2_results where kind='application'),39,'application creates thirty-nine subcategories');
select is((select array_agg(k order by k) from jsonb_object_keys((select result from w4c2_results where kind='application')) k),
  array['category_count','category_ids','command_correlation_id','id','status','subcategory_count','subcategory_ids','template_key','template_version','version']::text[],
  'template application result preserves the command contract and only allowlisted specialization');
select is((select count(*) from public.list_maintenance_categories(null,null,100,0)),11::bigint,'authorized category read model returns all tenant-owned template copies');
select is((select count(*) from public.list_maintenance_subcategories(null,null,null,100,0)),39::bigint,'authorized subcategory read model returns all tenant-owned template copies');
select is(public.apply_cw_catalog_template('cw_maintenance_taxonomy',1,'apply template',
  '4c650000-0000-4000-8000-000000000013','w4c2-template-apply-0001'),
  (select result from w4c2_results where kind='application'),'same-key apply replay is stable');
reset role;

select is((select count(*) from private.catalog_template_applications where tenant_id='4c630000-0000-4000-8000-000000000002'),1::bigint,'application ledger is unique per tenant and template');
select is((select count(*) from public.audit_events where tenant_id='4c630000-0000-4000-8000-000000000002'
  and event_type='cadastros.catalog_template.applied'),1::bigint,'template application emits one Audit fact');
select is((select count(*) from public.history_entries where tenant_id='4c630000-0000-4000-8000-000000000002'
  and command_name='maintenance.apply_cw_catalog_template'),50::bigint,'template application emits History for every copied record');
select is((select count(*) from private.outbox_events where tenant_id='4c630000-0000-4000-8000-000000000002'
  and correlation_id='4c650000-0000-4000-8000-000000000012'),51::bigint,'template application emits record and application Events atomically');

set local "request.jwt.claim.sub"='4c600000-0000-4000-8000-000000000003';
set local role authenticated;
select throws_ok($$select public.apply_cw_catalog_template('unknown_template',1,'invalid template',
  '4c650000-0000-4000-8000-000000000014','w4c2-template-invalid-0001')$$,'P0001','CW_CATALOG_TEMPLATE_UNAVAILABLE','unknown templates fail closed without partial writes');
reset role;

set local "request.jwt.claim.sub"='4c600000-0000-4000-8000-000000000001';
set local role authenticated;
select is((select count(*) from public.get_maintenance_category(
  (select (result->'category_ids'->>0)::uuid from w4c2_results where kind='application'))),0::bigint,
  'cross-tenant category detail fails closed as unavailable');
reset role;

select throws_ok(format('delete from public.maintenance_categories where id=%L::uuid',
  (select result->>'id' from w4c2_results where kind='category')),'42501','MAINTENANCE_TAXONOMY_DELETE_FORBIDDEN',
  'taxonomy rows cannot be physically deleted even by the migration owner');
select is((select count(*) from pg_catalog.pg_constraint c join pg_catalog.pg_class r on r.oid=c.conrelid
  join pg_catalog.pg_namespace n on n.oid=r.relnamespace where n.nspname='public'
  and r.relname in ('maintenance_categories','maintenance_subcategories') and c.contype='f'
  and c.confrelid in ('private.catalog_templates'::regclass,'private.catalog_template_entries'::regclass)),0::bigint,
  'tenant-owned copies have no runtime FK to global templates');
select is((select count(*) from pg_catalog.pg_class r join pg_catalog.pg_namespace n on n.oid=r.relnamespace
  where n.nspname='public' and r.relname in ('maintenance_reasons','document_types','checklist_templates','checklist_template_items')),4::bigint,
  'the later W4C.3 wave adds exactly its four supporting catalog tables');
select is((select count(*) from public.maintenance_reasons),0::bigint,
  'W4C.3 does not mutate Template CW v1 by seeding maintenance reasons');

select * from finish();
rollback;
