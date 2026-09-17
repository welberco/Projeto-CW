begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select has_table('public','location_types','W4A creates location types');
select has_table('public','locations','W4A creates locations');
select has_table('public','cost_centers','W4A creates cost centers');
select has_table('public','sectors','W4A creates sectors');
select has_table('private','authorization_profile_rollouts','W4A records deterministic baseline rollout');

select is((select count(*) from public.permission_catalog where module_code='shared' and resource_code in ('location_types','locations','cost_centers','sectors')),26::bigint,'W4A publishes exactly twenty-six granular permissions');
select is((select count(*) from public.permission_catalog where module_code='shared' and resource_code='locations'),7::bigint,'locations publishes exactly seven actions');
select is((select count(*) from public.permission_catalog where module_code='shared' and resource_code='location_types'),6::bigint,'location_types publishes exactly six actions');
select is((select count(*) from public.permission_catalog where module_code='shared' and resource_code='cost_centers'),7::bigint,'cost_centers publishes exactly seven actions');
select is((select count(*) from public.permission_catalog where module_code='shared' and resource_code='sectors'),6::bigint,'sectors publishes exactly six actions');
select is((select count(*) from public.permission_catalog where code in ('shared.locations.use.all_tenant','shared.location_types.use.all_tenant','shared.cost_centers.use.all_tenant','shared.sectors.use.all_tenant')),0::bigint,'generic W4A use permissions do not exist');
select is((select count(*) from private.authorization_profile_templates where template_key in ('manager','technician','assistant','requester') and template_version=2),4::bigint,'all official templates advance to version two');
select is((select count(*) from private.authorization_profile_template_permissions m join private.authorization_profile_templates t on t.id=m.template_id join public.permission_catalog p on p.id=m.permission_id where p.module_code='shared' and t.template_key='manager'),22::bigint,'manager baseline receives exact W4A grants without use or reactivate');
select is((select count(*) from private.authorization_profile_template_permissions m join private.authorization_profile_templates t on t.id=m.template_id join public.permission_catalog p on p.id=m.permission_id where p.module_code='shared' and t.template_key='technician'),3::bigint,'technician receives only the approved W4A lookup grants');
select is((select count(*) from private.authorization_profile_template_permissions m join private.authorization_profile_templates t on t.id=m.template_id join public.permission_catalog p on p.id=m.permission_id where p.module_code='shared' and t.template_key='assistant'),3::bigint,'assistant receives only the approved W4A lookup grants');
select is((select count(*) from private.authorization_profile_template_permissions m join private.authorization_profile_templates t on t.id=m.template_id join public.permission_catalog p on p.id=m.permission_id where p.module_code='shared' and t.template_key='requester'),2::bigint,'requester receives only location and sector lookup grants');
select is((select count(*) from private.authorization_profile_template_permissions m left join public.permission_catalog p on p.id=m.permission_id where p.id is null),0::bigint,'template baselines contain no orphan permission grants');
select is((select count(*) from public.permission_catalog where module_code='shared' and resource_code in ('location_types','locations','cost_centers','sectors') and action_code in ('read','lookup')),8::bigint,'read and lookup remain distinct permissions for every W4A resource');

select is((select count(*) from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname in ('location_types','locations','cost_centers','sectors') and c.relrowsecurity and c.relforcerowsecurity),4::bigint,'all W4A tables enforce RLS');
select is((select count(*) from information_schema.table_privileges where table_schema='public' and table_name in ('location_types','locations','cost_centers','sectors') and grantee in ('PUBLIC','anon','service_role','cw_worker')),0::bigint,'PUBLIC anon service_role and cw_worker have no W4A table grants');
select is((select count(*) from information_schema.table_privileges where table_schema='public' and table_name in ('location_types','locations','cost_centers','sectors') and grantee='authenticated' and privilege_type<>'SELECT'),0::bigint,'authenticated receives no direct W4A mutation grants');
select is((select count(*) from pg_catalog.pg_policies where schemaname='public' and tablename in ('location_types','locations','cost_centers','sectors') and cmd='SELECT'),4::bigint,'W4A exposes exactly one read policy per table');

select has_function('public','create_location_type',array['text','text','text','text','uuid','text'],'explicit location type create boundary exists');
select has_function('public','create_location',array['uuid','uuid','text','text','text','text','uuid','text'],'explicit location create boundary exists');
select has_function('public','move_location',array['uuid','bigint','uuid','text','uuid','text'],'explicit location move boundary exists');
select has_function('public','create_cost_center',array['uuid','text','text','text','text','uuid','text'],'explicit cost center create boundary exists');
select has_function('public','move_cost_center',array['uuid','bigint','uuid','text','uuid','text'],'explicit cost center move boundary exists');
select has_function('public','create_sector',array['text','text','text','text','uuid','text'],'explicit sector create boundary exists');
select has_function('public','lookup_locations',array['text','integer'],'narrow location lookup exists');
select has_function('public','list_locations',array['text','text','integer','integer'],'administrative location list exists');
select has_function('public','list_location_children',array['uuid'],'direct location children query exists');
select has_function('public','list_cost_center_children',array['uuid'],'direct cost center children query exists');

select is((select count(*) from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private') and (p.proname like '%location%' or p.proname like '%cost_center%' or p.proname like '%sector%' or p.proname like '%w4a%') and not exists(select 1 from pg_catalog.unnest(coalesce(p.proconfig,array[]::text[])) s(value) where pg_catalog.split_part(s.value,'=',1)='search_path' and pg_catalog.replace(pg_catalog.split_part(s.value,'=',2),'"','')='')),0::bigint,'all W4A functions fix an empty search_path');
select is((select count(*) from information_schema.routine_privileges where specific_schema='private' and routine_name in ('apply_w4a_authorization_rollout','can_access_w4a_catalog','assert_w4a_catalog_access','execute_w4a_catalog_command','protect_w4a_catalog_mutation') and grantee in ('PUBLIC','anon','authenticated','service_role','cw_worker')),0::bigint,'private W4A helpers are not client or worker RPCs');

insert into auth.users(id,aud,role,email,email_confirmed_at,created_at,updated_at) values
('4a000000-0000-4000-8000-000000000001','authenticated','authenticated','w4a-a@example.invalid',statement_timestamp(),statement_timestamp(),statement_timestamp()),
('4a000000-0000-4000-8000-000000000002','authenticated','authenticated','w4a-b@example.invalid',statement_timestamp(),statement_timestamp(),statement_timestamp()),
('4a000000-0000-4000-8000-000000000003','authenticated','authenticated','w4a-lookup-only@example.invalid',statement_timestamp(),statement_timestamp(),statement_timestamp()),
('4a000000-0000-4000-8000-000000000004','authenticated','authenticated','w4a-mutation-only@example.invalid',statement_timestamp(),statement_timestamp(),statement_timestamp());

create temporary table w4a_tenant_a as select * from public.bootstrap_initial_tenant('4a000000-0000-4000-8000-000000000001','W4A Tenant A','4b000000-0000-4000-8000-000000000001');

insert into public.tenants (id, tenant_ref, display_name, status, created_by)
values ('f4a00000-0000-4000-8000-000000000002','f4b00000-0000-4000-8000-000000000002','W4A Tenant B','active','4a000000-0000-4000-8000-000000000002');
do $$
declare
  tenant_b_manager_profile_id uuid;
begin
  perform * from private.provision_tenant_authorization(
    'f4a00000-0000-4000-8000-000000000002',
    null,
    '4a000000-0000-4000-8000-000000000002',
    '4b000000-0000-4000-8000-000000000002'
  );

  select profile.id
  into strict tenant_b_manager_profile_id
  from public.tenant_profiles as profile
  join private.authorization_profile_templates as template
    on template.template_key = profile.template_key
   and template.template_version = profile.template_version
   and template.status = 'active'
  where profile.tenant_id = 'f4a00000-0000-4000-8000-000000000002'
    and template.template_key = 'manager'
    and profile.status = 'active';

  insert into public.tenant_memberships (
    id,
    tenant_id,
    user_id,
    status,
    joined_at,
    created_by,
    profile_id,
    profile_assigned_at,
    profile_assigned_by
  ) values (
    'f4c00000-0000-4000-8000-000000000002',
    'f4a00000-0000-4000-8000-000000000002',
    '4a000000-0000-4000-8000-000000000002',
    'active',
    statement_timestamp(),
    '4a000000-0000-4000-8000-000000000002',
    tenant_b_manager_profile_id,
    statement_timestamp(),
    '4a000000-0000-4000-8000-000000000002'
  );
end;
$$;
insert into public.tenant_entitlements (tenant_id, module_key, enabled, created_by)
values ('f4a00000-0000-4000-8000-000000000002','maintenance',true,'4a000000-0000-4000-8000-000000000002');
create temporary table w4a_tenant_b as
select id as tenant_id, tenant_ref from public.tenants where id='f4a00000-0000-4000-8000-000000000002';
grant select on table w4a_tenant_a,w4a_tenant_b to authenticated;

insert into public.tenant_profiles (id,tenant_id,name,status,created_by,updated_by)
values ('f4d00000-0000-4000-8000-000000000001',(select tenant_id from w4a_tenant_a),'W4A Mutation Only','active','4a000000-0000-4000-8000-000000000001','4a000000-0000-4000-8000-000000000001');
insert into public.tenant_profile_permissions (tenant_id,profile_id,permission_id,created_by)
select (select tenant_id from w4a_tenant_a),'f4d00000-0000-4000-8000-000000000001',permission.id,'4a000000-0000-4000-8000-000000000001'
from public.permission_catalog permission
where permission.code in ('shared.locations.create.all_tenant','shared.locations.update.all_tenant');
insert into public.tenant_memberships (id,tenant_id,user_id,status,joined_at,created_by,profile_id,profile_assigned_at,profile_assigned_by) values
('f4c00000-0000-4000-8000-000000000003',(select tenant_id from w4a_tenant_a),'4a000000-0000-4000-8000-000000000003','active',statement_timestamp(),'4a000000-0000-4000-8000-000000000001',(select id from public.tenant_profiles where tenant_id=(select tenant_id from w4a_tenant_a) and template_key='requester'),statement_timestamp(),'4a000000-0000-4000-8000-000000000001'),
('f4c00000-0000-4000-8000-000000000004',(select tenant_id from w4a_tenant_a),'4a000000-0000-4000-8000-000000000004','active',statement_timestamp(),'4a000000-0000-4000-8000-000000000001','f4d00000-0000-4000-8000-000000000001',statement_timestamp(),'4a000000-0000-4000-8000-000000000001');
insert into public.tenant_permission_overrides (id,tenant_id,membership_id,permission_id,effect,created_by,updated_by)
select 'f4e00000-0000-4000-8000-000000000001',(select tenant_id from w4a_tenant_a),'f4c00000-0000-4000-8000-000000000004',permission.id,'deny','4a000000-0000-4000-8000-000000000001','4a000000-0000-4000-8000-000000000001'
from public.permission_catalog permission
where permission.code='shared.locations.move.all_tenant';

select is(private.apply_w4a_authorization_rollout((select tenant_id from w4a_tenant_a)),0,'rollout replay is idempotent for newly provisioned tenant');
select is((select count(*) from public.tenant_profile_permissions where profile_id='f4d00000-0000-4000-8000-000000000001'),2::bigint,'rollout does not silently expand a custom profile');
select is((select effect from public.tenant_permission_overrides where id='f4e00000-0000-4000-8000-000000000001'),'deny','rollout preserves an exact membership override');
select is((select count(*) from private.authorization_profile_rollouts where tenant_id=(select tenant_id from w4a_tenant_a) and rollout_key='w4_catalog_baseline_v1'),4::bigint,'rollout remains versioned once per official profile');

create temporary table w4a_results(kind text,result jsonb);
grant insert,select on table w4a_results to authenticated;
set local "request.jwt.claim.sub"='4a000000-0000-4000-8000-000000000001';
set local role authenticated;
insert into w4a_results values ('type',public.create_location_type('BUILDING','Edificação',null,'create structural fixture','4c000000-0000-4000-8000-000000000001','w4a-type-key-0001'));
insert into w4a_results values ('type_replay',public.create_location_type('BUILDING','Edificação',null,'same semantic replay','4c000000-0000-4000-8000-000000000099','w4a-type-key-0001'));
insert into w4a_results values ('root',public.create_location(((select result->>'id' from w4a_results where kind='type'))::uuid,null,'ROOT','Sede',null,'create root location','4c000000-0000-4000-8000-000000000002','w4a-location-key-0001'));
insert into w4a_results values ('child',public.create_location(((select result->>'id' from w4a_results where kind='type'))::uuid,((select result->>'id' from w4a_results where kind='root'))::uuid,'ROOM','Sala técnica',null,'create child location','4c000000-0000-4000-8000-000000000003','w4a-location-key-0002'));
insert into w4a_results values ('cc',public.create_cost_center(null,'CC-001','Manutenção',null,'create cost center','4c000000-0000-4000-8000-000000000004','w4a-cc-key-0001'));
insert into w4a_results values ('sector',public.create_sector('OPS','Operações',null,'create sector','4c000000-0000-4000-8000-000000000005','w4a-sector-key-0001'));
reset role;

select is((select result from w4a_results where kind='type_replay'),(select result from w4a_results where kind='type'),'compatible replay returns the original stable result');
select ok((select result ? 'command_correlation_id' from w4a_results where kind='type'),'first result exposes the W3-compatible command correlation key');
select ok(not (select result ? 'correlation_id' from w4a_results where kind='type'),'first result omits the forbidden correlation key');
select is((select result->>'command_correlation_id' from w4a_results where kind='type'),'4c000000-0000-4000-8000-000000000001','first result preserves the original command correlation');
select is((select result->>'command_correlation_id' from w4a_results where kind='type_replay'),'4c000000-0000-4000-8000-000000000001','replay preserves the first execution correlation instead of the retry correlation');
select is((select count(*) from public.location_types where tenant_id=(select tenant_id from w4a_tenant_a)),1::bigint,'replay does not duplicate the mutation');
select is((select count(*) from public.audit_events where tenant_id=(select tenant_id from w4a_tenant_a) and event_type like 'cadastros.%'),5::bigint,'each logical W4A mutation writes one Audit fact');
select is((select count(*) from public.history_entries where tenant_id=(select tenant_id from w4a_tenant_a) and history_type like 'cadastros.%'),5::bigint,'each logical W4A mutation writes one History fact');
select is((select count(*) from private.outbox_events where tenant_id=(select tenant_id from w4a_tenant_a) and event_type like 'cadastros.%'),5::bigint,'each logical W4A mutation writes one Event fact');
select is((select count(*) from private.command_idempotency where tenant_id=(select tenant_id from w4a_tenant_a) and command_name like '%location_type' and status='completed'),1::bigint,'raw command replay completes one idempotency identity');

-- Reference authorization is owned by the mutated Resource. Lookup is discovery only;
-- the command revalidates referenced tenant, existence, lifecycle and eligibility.
set local "request.jwt.claim.sub"='4a000000-0000-4000-8000-000000000001';
set local role authenticated;
insert into w4a_results values ('inactive_type',public.create_location_type('INACTIVE','Tipo inativo',null,'create inactive reference fixture','4c000000-0000-4000-8000-000000000020','w4a-type-key-inactive-0001'));
insert into w4a_results values ('inactive_type_result',public.inactivate_location_type(((select result->>'id' from w4a_results where kind='inactive_type'))::uuid,1,'inactivate reference fixture','4c000000-0000-4000-8000-000000000021','w4a-type-inactivate-0001'));
reset role;

set local "request.jwt.claim.sub"='4a000000-0000-4000-8000-000000000002';
set local role authenticated;
insert into w4a_results values ('tenant_b_type',public.create_location_type('REMOTE','Tenant B type',null,'create cross-tenant reference fixture','4c000000-0000-4000-8000-000000000022','w4a-type-key-tenant-b-0001'));
reset role;

set local "request.jwt.claim.sub"='4a000000-0000-4000-8000-000000000003';
set local role authenticated;
select lives_ok(
  $$select * from public.lookup_locations(null,20)$$,
  'lookup-only actor can discover the narrow active location projection'
);
select throws_ok(
  format('select public.create_location(%L::uuid,null,%L,%L,null,%L,%L::uuid,%L)',(select result->>'id' from w4a_results where kind='type'),'LOOKUP-NO-CREATE','Forbidden','lookup does not authorize create','4c000000-0000-4000-8000-000000000023','w4a-lookup-no-create-0001'),
  '42501','AUTHORIZATION_DENIED','lookup without locations.create cannot create a location'
);
select throws_ok(
  format('select public.update_location(%L::uuid,1,%L::uuid,%L,%L,null,%L,%L::uuid,%L)',(select result->>'id' from w4a_results where kind='root'),(select result->>'id' from w4a_results where kind='type'),'ROOT-X','Forbidden update','lookup does not authorize update','4c000000-0000-4000-8000-000000000024','w4a-lookup-no-update-0001'),
  '42501','AUTHORIZATION_DENIED','lookup without locations.update cannot update a location'
);
reset role;

select is((select count(*) from public.tenant_profile_permissions mapping join public.permission_catalog permission on permission.id=mapping.permission_id where mapping.profile_id='f4d00000-0000-4000-8000-000000000001' and permission.action_code='lookup'),0::bigint,'mutation-only custom profile has no lookup permission');
set local "request.jwt.claim.sub"='4a000000-0000-4000-8000-000000000004';
set local role authenticated;
select lives_ok(
  format('insert into w4a_results values (%L,public.create_location(%L::uuid,null,%L,%L,null,%L,%L::uuid,%L))','mutation_only_location',(select result->>'id' from w4a_results where kind='type'),'MUT-ONLY','Mutation only','valid reference without lookup','4c000000-0000-4000-8000-000000000025','w4a-mutation-only-create-0001'),
  'locations.create accepts a valid reference without lookup or use permission'
);
select lives_ok(
  format('select public.update_location(%L::uuid,1,%L::uuid,%L,%L,null,%L,%L::uuid,%L)',(select result->>'id' from w4a_results where kind='mutation_only_location'),(select result->>'id' from w4a_results where kind='type'),'MUT-ONLY-2','Mutation only updated','valid update reference without lookup','4c000000-0000-4000-8000-000000000026','w4a-mutation-only-update-0001'),
  'locations.update accepts a valid reference without lookup or use permission'
);
reset role;

set local "request.jwt.claim.sub"='4a000000-0000-4000-8000-000000000001';
set local role authenticated;
select throws_ok(
  format('select public.create_location(%L::uuid,null,%L,%L,null,%L,%L::uuid,%L)',(select result->>'id' from w4a_results where kind='tenant_b_type'),'CROSS-TENANT','Cross tenant','reject cross-tenant type','4c000000-0000-4000-8000-000000000027','w4a-cross-tenant-type-0001'),
  'P0001','LOCATION_TYPE_UNAVAILABLE','cross-tenant location type reference fails closed'
);
select throws_ok(
  format('select public.update_location(%L::uuid,1,%L::uuid,%L,%L,null,%L,%L::uuid,%L)',(select result->>'id' from w4a_results where kind='root'),'f4f00000-0000-4000-8000-000000000001','ROOT','Sede','reject nonexistent type','4c000000-0000-4000-8000-000000000028','w4a-nonexistent-type-0001'),
  'P0001','LOCATION_TYPE_UNAVAILABLE','nonexistent location type reference fails closed'
);
select throws_ok(
  format('select public.update_location(%L::uuid,1,%L::uuid,%L,%L,null,%L,%L::uuid,%L)',(select result->>'id' from w4a_results where kind='root'),(select result->>'id' from w4a_results where kind='inactive_type'),'ROOT','Sede','reject inactive type','4c000000-0000-4000-8000-000000000029','w4a-inactive-type-0001'),
  'P0001','LOCATION_TYPE_UNAVAILABLE','inactive location type reference fails closed'
);
reset role;

set local "request.jwt.claim.sub"='4a000000-0000-4000-8000-000000000001';
set local role authenticated;
select throws_ok(
  $$select public.create_location_type('BUILDING','Outro nome',null,'conflicting replay','4c000000-0000-4000-8000-000000000008','w4a-type-key-0001')$$,
  'P0001','IDEMPOTENCY_FINGERPRINT_CONFLICT','semantic conflict fails closed without another mutation'
);
reset role;

create function pg_temp.fail_w4a_event() returns trigger language plpgsql as $$
begin
  if new.event_type='cadastros.sector.updated' then
    raise exception using errcode='P0001',message='W4A_TEST_EVENT_FAILURE';
  end if;
  return new;
end;
$$;
create trigger w4a_force_event_failure before insert on private.outbox_events for each row execute function pg_temp.fail_w4a_event();
set local role authenticated;
select throws_ok(
  format('select public.update_sector(%L::uuid,1,%L,%L,null,%L,%L::uuid,%L)',(select result->>'id' from w4a_results where kind='sector'),'OPS-2','Operações 2','force event rollback','4c000000-0000-4000-8000-000000000009','w4a-sector-update-0001'),
  'P0001','W4A_TEST_EVENT_FAILURE','mandatory Event failure rolls back the entire command'
);
reset role;
drop trigger w4a_force_event_failure on private.outbox_events;
select is((select version from public.sectors where id=((select result->>'id' from w4a_results where kind='sector'))::uuid),1::bigint,'Event failure rolls back the domain mutation');
select is((select count(*) from private.command_idempotency where idempotency_key_hash=private.semantic_fingerprint(pg_catalog.to_jsonb('w4a-sector-update-0001'::text))),0::bigint,'Event failure leaves no completed or orphan idempotency identity');

select throws_ok(format('select public.move_location(%L::uuid,1,%L::uuid,%L,%L::uuid,%L)',(select result->>'id' from w4a_results where kind='root'),(select result->>'id' from w4a_results where kind='child'),'attempt cycle','4c000000-0000-4000-8000-000000000006','w4a-location-move-0001'),'23514','LOCATION_CYCLE','location cycles fail closed in PostgreSQL');

set local "request.jwt.claim.sub"='4a000000-0000-4000-8000-000000000002';
set local role authenticated;
select throws_ok(format('select public.update_sector(%L::uuid,1,%L,%L,null,%L,%L::uuid,%L)',(select result->>'id' from w4a_results where kind='sector'),'OPS-X','Cross tenant','cross tenant attempt','4c000000-0000-4000-8000-000000000007','w4a-sector-cross-0001'),'P0001','CATALOG_VERSION_CONFLICT','cross-tenant IDOR is indistinguishable from an unavailable row');
reset role;

select is((select count(*) from public.locations where tenant_id=(select tenant_id from w4a_tenant_b)),0::bigint,'tenant B cannot observe tenant A catalog rows');
select throws_ok(format('delete from public.sectors where id=%L::uuid',(select result->>'id' from w4a_results where kind='sector')),'42501','STRUCTURAL_CATALOG_DELETE_FORBIDDEN','catalog rows cannot be physically deleted even by the migration owner');
select ok(not exists(select 1 from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname in ('teams','team_memberships','categories','subcategories','reasons')),'W4A does not anticipate W4B or W4C tables');

select * from finish();
rollback;
