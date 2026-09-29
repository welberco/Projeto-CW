begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

create temporary table w5a_expected_permissions (
  id uuid primary key,
  code text unique not null,
  resource_code text not null,
  action_code text not null
);

insert into w5a_expected_permissions (id, code, resource_code, action_code)
select
  ('97000000-0000-4000-8000-' || pg_catalog.lpad(permission.ordinal::text, 12, '0'))::uuid,
  'shared.' || permission.resource_code || '.' || permission.action_code || '.all_tenant',
  permission.resource_code,
  permission.action_code
from (values
  ('asset_types','read',1),
  ('asset_types','lookup',2),
  ('asset_types','create',3),
  ('asset_types','update',4),
  ('asset_types','inactivate',5),
  ('asset_types','reactivate',6),
  ('assets','read',7),
  ('assets','lookup',8),
  ('assets','create',9),
  ('assets','update',10),
  ('assets','move',11),
  ('assets','inactivate',12),
  ('assets','reactivate',13),
  ('assets','decommission',14),
  ('asset_files','read',15),
  ('asset_files','reserve',16),
  ('asset_files','finalize',17),
  ('asset_files','delete',18),
  ('asset_files','retry',19)
) as permission(resource_code, action_code, ordinal);

create temporary table w5a_expected_template_permissions (
  template_key text not null,
  permission_code text not null,
  primary key (template_key, permission_code)
);

insert into w5a_expected_template_permissions (template_key, permission_code)
values
  ('manager','shared.asset_types.read.all_tenant'),
  ('manager','shared.asset_types.lookup.all_tenant'),
  ('manager','shared.asset_types.create.all_tenant'),
  ('manager','shared.asset_types.update.all_tenant'),
  ('manager','shared.asset_types.inactivate.all_tenant'),
  ('manager','shared.asset_types.reactivate.all_tenant'),
  ('manager','shared.assets.read.all_tenant'),
  ('manager','shared.assets.lookup.all_tenant'),
  ('manager','shared.assets.create.all_tenant'),
  ('manager','shared.assets.update.all_tenant'),
  ('manager','shared.assets.move.all_tenant'),
  ('manager','shared.assets.inactivate.all_tenant'),
  ('manager','shared.assets.reactivate.all_tenant'),
  ('manager','shared.assets.decommission.all_tenant'),
  ('manager','shared.asset_files.read.all_tenant'),
  ('manager','shared.asset_files.reserve.all_tenant'),
  ('manager','shared.asset_files.finalize.all_tenant'),
  ('manager','shared.asset_files.delete.all_tenant'),
  ('manager','shared.asset_files.retry.all_tenant'),
  ('technician','shared.asset_types.lookup.all_tenant'),
  ('technician','shared.assets.read.all_tenant'),
  ('technician','shared.assets.lookup.all_tenant'),
  ('technician','shared.asset_files.read.all_tenant'),
  ('technician','shared.asset_files.reserve.all_tenant'),
  ('technician','shared.asset_files.finalize.all_tenant'),
  ('technician','shared.asset_files.retry.all_tenant'),
  ('assistant','shared.asset_types.lookup.all_tenant'),
  ('assistant','shared.assets.read.all_tenant'),
  ('assistant','shared.assets.lookup.all_tenant'),
  ('assistant','shared.asset_files.read.all_tenant'),
  ('requester','shared.assets.lookup.all_tenant');

select is(
  (select count(*) from public.permission_catalog where resource_code in ('asset_types','assets','asset_files')),
  19::bigint,
  'W5A publishes exactly nineteen permissions'
);
select is(
  (select count(*) from (
    select id, code, resource_code, action_code
    from public.permission_catalog
    where resource_code in ('asset_types','assets','asset_files')
    except
    select id, code, resource_code, action_code from w5a_expected_permissions
  ) as unexpected),
  0::bigint,
  'W5A publishes no unexpected permission identity or combination'
);
select is(
  (select count(*) from (
    select id, code, resource_code, action_code from w5a_expected_permissions
    except
    select id, code, resource_code, action_code
    from public.permission_catalog
    where resource_code in ('asset_types','assets','asset_files')
  ) as missing),
  0::bigint,
  'all approved W5A permission IDs and codes exist'
);
select is(
  (select count(*) from public.permission_catalog
   where resource_code in ('asset_types','assets','asset_files')
     and module_code = 'shared'
     and scope = 'ALL_TENANT'
     and tenant_delegable
     and required_entitlement_key is null
     and status = 'active'),
  19::bigint,
  'all W5A permissions have the frozen shared ALL_TENANT metadata'
);
select is(
  (select count(*) from public.permission_catalog
   where resource_code in ('asset_types','assets','asset_files')
     and (scope in ('OWN','ASSIGNED','TEAM') or action_code = 'manage' or code like '%*%')),
  0::bigint,
  'W5A adds no OWN, ASSIGNED, TEAM, manage or wildcard capability'
);
select is(
  (select count(*) from public.permission_catalog
   where code in ('shared.assets.move.all_tenant','shared.assets.update.all_tenant')),
  2::bigint,
  'Asset move and update remain separate exact capabilities'
);

select is(
  (select count(*) from private.authorization_profile_templates
   where template_key in ('manager','technician','assistant','requester')
     and template_version = 5 and status = 'active'),
  4::bigint,
  'all official templates advance from version four to version five'
);
select is(
  (select count(*) from w5a_expected_template_permissions),
  31::bigint,
  'the frozen W5A baseline contains exactly thirty-one mappings'
);
select is(
  (select count(*) from (
    select template.template_key, permission.code
    from private.authorization_profile_template_permissions as mapping
    join private.authorization_profile_templates as template on template.id = mapping.template_id
    join public.permission_catalog as permission on permission.id = mapping.permission_id
    where permission.resource_code in ('asset_types','assets','asset_files')
    except
    select template_key, permission_code from w5a_expected_template_permissions
  ) as unexpected),
  0::bigint,
  'official templates contain no W5A mapping outside the frozen matrix'
);
select is(
  (select count(*) from (
    select template_key, permission_code from w5a_expected_template_permissions
    except
    select template.template_key, permission.code
    from private.authorization_profile_template_permissions as mapping
    join private.authorization_profile_templates as template on template.id = mapping.template_id
    join public.permission_catalog as permission on permission.id = mapping.permission_id
    where permission.resource_code in ('asset_types','assets','asset_files')
  ) as missing),
  0::bigint,
  'official templates contain every frozen W5A mapping'
);
select is(
  (select array_agg(grant_count order by template_key) from (
    select template.template_key, count(*)::integer as grant_count
    from private.authorization_profile_template_permissions as mapping
    join private.authorization_profile_templates as template on template.id = mapping.template_id
    join public.permission_catalog as permission on permission.id = mapping.permission_id
    where permission.resource_code in ('asset_types','assets','asset_files')
    group by template.template_key
  ) as counts),
  array[4,19,1,7]::integer[],
  'Assistant, Manager, Requester and Technician receive exactly 4, 19, 1 and 7 grants'
);
select is(
  (select count(*) from (
    select permission_code from w5a_expected_template_permissions where template_key in ('technician','assistant','requester')
    except
    select permission_code from w5a_expected_template_permissions where template_key = 'manager'
  ) as undelegable),
  0::bigint,
  'Manager contains every exact capability delegated to subordinate baselines'
);
select is(
  (select count(*) from w5a_expected_template_permissions
   where template_key = 'requester' and permission_code = 'shared.assets.lookup.all_tenant'),
  1::bigint,
  'Requester receives assets.lookup exactly once'
);
select is(
  (select count(*) from w5a_expected_template_permissions
   where template_key = 'requester'
     and permission_code in ('shared.assets.read.all_tenant','shared.asset_files.read.all_tenant','shared.asset_types.lookup.all_tenant')),
  0::bigint,
  'Requester receives none of the forbidden W5 reads'
);
select is(
  (select count(*) from w5a_expected_template_permissions
   where template_key = 'technician'
     and permission_code in (
       'shared.assets.create.all_tenant','shared.assets.update.all_tenant','shared.assets.move.all_tenant',
       'shared.assets.inactivate.all_tenant','shared.assets.reactivate.all_tenant','shared.assets.decommission.all_tenant'
     )),
  0::bigint,
  'Technician receives no Asset mutation capability'
);
select is(
  (select count(*) from w5a_expected_template_permissions
   where template_key = 'assistant'
     and (permission_code like 'shared.assets.%.all_tenant' and permission_code <> 'shared.assets.read.all_tenant' and permission_code <> 'shared.assets.lookup.all_tenant'
       or permission_code in (
         'shared.asset_files.reserve.all_tenant','shared.asset_files.finalize.all_tenant',
         'shared.asset_files.delete.all_tenant','shared.asset_files.retry.all_tenant'
       ))),
  0::bigint,
  'Assistant receives no Asset or Asset File mutation capability'
);

select has_function(
  'private', 'apply_w5a_authorization_rollout', array['uuid'],
  'the W5A rollout function exists only in the private boundary'
);
select is(
  (select procedure.prosecdef from pg_catalog.pg_proc as procedure
   where procedure.oid = 'private.apply_w5a_authorization_rollout(uuid)'::regprocedure),
  true,
  'the W5A rollout is SECURITY DEFINER'
);
select ok(
  exists (
    select 1
    from pg_catalog.pg_proc as procedure
    cross join pg_catalog.unnest(coalesce(procedure.proconfig,array[]::text[])) as setting(value)
    where procedure.oid = 'private.apply_w5a_authorization_rollout(uuid)'::regprocedure
      and pg_catalog.split_part(setting.value,'=',1) = 'search_path'
      and pg_catalog.replace(pg_catalog.split_part(setting.value,'=',2),'"','') = ''
  ),
  'the W5A rollout fixes an empty search_path'
);
select is(
  (select owner_role.rolname
   from pg_catalog.pg_proc as procedure
   join pg_catalog.pg_roles as owner_role on owner_role.oid = procedure.proowner
   where procedure.oid = 'private.apply_w5a_authorization_rollout(uuid)'::regprocedure),
  'postgres',
  'the W5A rollout has the controlled postgres owner'
);
select is(
  (select count(*) from information_schema.routine_privileges
   where routine_schema = 'private'
     and routine_name = 'apply_w5a_authorization_rollout'
     and grantee in ('PUBLIC','anon','authenticated','service_role','cw_worker')),
  0::bigint,
  'the W5A rollout is not executable by API or technical roles'
);
select is(has_table_privilege('authenticated','public.permission_catalog','SELECT'), false,
  'W5A does not expose the permission catalog to authenticated users');
select is(has_table_privilege('service_role','public.permission_catalog','SELECT'), false,
  'W5A does not broaden the service-role permission catalog boundary');
select is(
  (select count(*) from public.permission_catalog where code like '%global_admin%' or code like '%platform%'),
  0::bigint,
  'Global Admin remains outside the tenant permission catalog'
);
select is(
  (select count(*) from pg_catalog.pg_class as relation
   join pg_catalog.pg_namespace as namespace on namespace.oid = relation.relnamespace
   where namespace.nspname in ('public','private','storage')
     and relation.relkind in ('r','p')
     and relation.relname in (
       'asset_types','assets','asset_aliases','asset_allocators','asset_specification_values',
       'storage_reservations','storage_objects','storage_quotas','asset_files'
     )),
  0::bigint,
  'W5A creates no Asset or Storage domain table'
);

insert into auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
values
  ('5a100000-0000-4000-8000-000000000001','authenticated','authenticated','w5a-manager@example.invalid',statement_timestamp(),statement_timestamp(),statement_timestamp()),
  ('5a100000-0000-4000-8000-000000000002','authenticated','authenticated','w5a-requester@example.invalid',statement_timestamp(),statement_timestamp(),statement_timestamp()),
  ('5a100000-0000-4000-8000-000000000003','authenticated','authenticated','w5a-new-tenant@example.invalid',statement_timestamp(),statement_timestamp(),statement_timestamp());

create temporary table w5a_bootstrap as
select * from public.bootstrap_initial_tenant(
  '5a100000-0000-4000-8000-000000000001',
  'W5A Existing Tenant',
  '5a200000-0000-4000-8000-000000000001'
);

update public.tenant_profiles
set name = 'Manager W5A renamed',
    updated_by = '5a100000-0000-4000-8000-000000000001'
where tenant_id = (select tenant_id from w5a_bootstrap)
  and template_key = 'manager';

insert into public.tenant_profiles (id, tenant_id, name, status, created_by, updated_by)
values (
  '5a300000-0000-4000-8000-000000000001',
  (select tenant_id from w5a_bootstrap),
  'Manager',
  'active',
  '5a100000-0000-4000-8000-000000000001',
  '5a100000-0000-4000-8000-000000000001'
);

insert into public.tenant_profile_permissions (tenant_id, profile_id, permission_id, created_by)
select bootstrap.tenant_id, '5a300000-0000-4000-8000-000000000001', permission.id,
       '5a100000-0000-4000-8000-000000000001'
from w5a_bootstrap as bootstrap
join public.permission_catalog as permission on permission.code = 'shared.teams.read.team';

insert into public.tenant_memberships (
  id, tenant_id, user_id, status, joined_at, created_by,
  profile_id, profile_assigned_at, profile_assigned_by
)
select
  '5a400000-0000-4000-8000-000000000002',
  bootstrap.tenant_id,
  '5a100000-0000-4000-8000-000000000002',
  'active',
  statement_timestamp(),
  '5a100000-0000-4000-8000-000000000001',
  profile.id,
  statement_timestamp(),
  '5a100000-0000-4000-8000-000000000001'
from w5a_bootstrap as bootstrap
join public.tenant_profiles as profile
  on profile.tenant_id = bootstrap.tenant_id and profile.template_key = 'requester';

insert into public.tenant_permission_overrides (
  id, tenant_id, membership_id, permission_id, effect, created_by, updated_by
)
select fixture.id, bootstrap.tenant_id, membership.id, permission.id, fixture.effect,
       '5a100000-0000-4000-8000-000000000001',
       '5a100000-0000-4000-8000-000000000001'
from w5a_bootstrap as bootstrap
cross join (values
  ('5a500000-0000-4000-8000-000000000001'::uuid,'5a100000-0000-4000-8000-000000000001'::uuid,'shared.asset_types.lookup.all_tenant','deny'),
  ('5a500000-0000-4000-8000-000000000002'::uuid,'5a100000-0000-4000-8000-000000000001'::uuid,'shared.teams.read.team','deny'),
  ('5a500000-0000-4000-8000-000000000003'::uuid,'5a100000-0000-4000-8000-000000000002'::uuid,'shared.asset_files.read.all_tenant','allow')
) as fixture(id, user_id, permission_code, effect)
join public.tenant_memberships as membership
  on membership.tenant_id = bootstrap.tenant_id and membership.user_id = fixture.user_id
join public.permission_catalog as permission on permission.code = fixture.permission_code;

create temporary table w5a_override_snapshot as
select id, tenant_id, membership_id, permission_id, effect, version, created_by, updated_by
from public.tenant_permission_overrides
where tenant_id = (select tenant_id from w5a_bootstrap);

create temporary table w5a_profile_snapshot as
select id, template_key, template_version
from public.tenant_profiles
where tenant_id = (select tenant_id from w5a_bootstrap);

delete from public.tenant_profile_permissions as baseline
using public.tenant_profiles as profile, public.permission_catalog as permission
where profile.id = baseline.profile_id
  and permission.id = baseline.permission_id
  and profile.tenant_id = (select tenant_id from w5a_bootstrap)
  and profile.template_key in ('manager','technician','assistant','requester')
  and permission.resource_code in ('asset_types','assets','asset_files');

select is(
  private.apply_w5a_authorization_rollout((select tenant_id from w5a_bootstrap)),
  31,
  'the first existing-tenant rollout adds exactly thirty-one W5 grants'
);
select is(
  (select count(*) from private.authorization_profile_rollouts
   where rollout_key = 'w5a_assets_storage_v1'
     and tenant_id = (select tenant_id from w5a_bootstrap)),
  4::bigint,
  'the W5A ledger records one row per official profile identity'
);
select is(
  (select sum(grants_added)::integer from private.authorization_profile_rollouts
   where rollout_key = 'w5a_assets_storage_v1'
     and tenant_id = (select tenant_id from w5a_bootstrap)),
  31,
  'the W5A ledger records exactly thirty-one added grants'
);
select is(
  (select count(*) from public.tenant_profile_permissions as baseline
   join public.tenant_profiles as profile on profile.id = baseline.profile_id
   join public.permission_catalog as permission on permission.id = baseline.permission_id
   where profile.tenant_id = (select tenant_id from w5a_bootstrap)
     and profile.template_key in ('manager','technician','assistant','requester')
     and permission.resource_code in ('asset_types','assets','asset_files')),
  31::bigint,
  'existing official profiles receive exactly the W5A baseline'
);
select is(
  (select name from public.tenant_profiles
   where tenant_id = (select tenant_id from w5a_bootstrap) and template_key = 'manager'),
  'Manager W5A renamed',
  'rollout uses template_key and preserves the official profile display name'
);
select is(
  (select count(*) from public.tenant_profiles
   where id = '5a300000-0000-4000-8000-000000000001' and template_key is null),
  1::bigint,
  'a custom profile named Manager remains custom'
);
select is(
  (select count(*) from public.tenant_profile_permissions
   where profile_id = '5a300000-0000-4000-8000-000000000001'),
  1::bigint,
  'the rollout preserves a custom profile grant without adding W5 baselines'
);
select is(
  (select count(*) from (
    select * from w5a_override_snapshot
    except
    select id, tenant_id, membership_id, permission_id, effect, version, created_by, updated_by
    from public.tenant_permission_overrides
    where tenant_id = (select tenant_id from w5a_bootstrap)
  ) as changed),
  0::bigint,
  'the rollout preserves every exact ALLOW and DENY override'
);
select is(
  (select count(*) from (
    select id, template_key, template_version from w5a_profile_snapshot
    except
    select id, template_key, template_version from public.tenant_profiles
    where tenant_id = (select tenant_id from w5a_bootstrap)
  ) as changed),
  0::bigint,
  'the rollout preserves tenant profile provenance versions'
);
select is(
  private.apply_w5a_authorization_rollout((select tenant_id from w5a_bootstrap)),
  31,
  'rollout replay returns the ledger result without adding effects again'
);
select is(
  (select count(*) from public.audit_events
   where tenant_id = (select tenant_id from w5a_bootstrap)
     and event_type = 'authorization.profile.baseline_rolled_out'
     and actor_ref = 'w5a.authorization_rollout'
     and metadata->>'rollout_key' = 'w5a_assets_storage_v1'),
  4::bigint,
  'first rollout emits four technical Audit facts and replay emits none'
);

set local "request.jwt.claim.sub" = '5a100000-0000-4000-8000-000000000001';
select is(private.has_effective_permission('asset_types','lookup','ALL_TENANT'), false,
  'exact DENY wins over the same W5 baseline capability');
select is(private.has_effective_permission('assets','lookup','ALL_TENANT'), true,
  'an unaffected exact W5 baseline capability remains allowed');
select is(private.has_effective_permission('teams','read','TEAM'), false,
  'exact TEAM DENY removes only the exact TEAM combination');
select is(private.has_effective_permission('teams','read','ALL_TENANT'), true,
  'a DENY on TEAM does not subtract the independent ALL_TENANT capability');

set local "request.jwt.claim.sub" = '5a100000-0000-4000-8000-000000000002';
select is(private.has_effective_permission('assets','lookup','ALL_TENANT'), true,
  'Requester receives its exact assets.lookup baseline');
select is(private.has_effective_permission('asset_files','read','ALL_TENANT'), true,
  'an exact custom ALLOW adds only the requested Asset File capability');
select is(private.has_effective_permission('assets','read','ALL_TENANT'), false,
  'absence of assets.read remains deny/inherit for Requester');
select is(private.has_effective_permission('asset_types','lookup','ALL_TENANT'), false,
  'Requester does not inherit asset_types.lookup');
select is(private.has_effective_permission('asset_files','delete','ALL_TENANT'), false,
  'the custom Asset File read ALLOW does not imply mutation authority');

insert into public.tenants (id, tenant_ref, display_name, status, created_by)
values (
  '5a200000-0000-4000-8000-000000000002',
  '5a210000-0000-4000-8000-000000000002',
  'W5A Newly Provisioned Tenant',
  'active',
  '5a100000-0000-4000-8000-000000000003'
);

create temporary table w5a_new_provisioning as
select * from private.provision_tenant_authorization(
  '5a200000-0000-4000-8000-000000000002',
  null,
  '5a100000-0000-4000-8000-000000000003',
  '5a220000-0000-4000-8000-000000000002'
);

select is(
  (select count(*) from public.tenant_profiles
   where tenant_id = '5a200000-0000-4000-8000-000000000002'
     and template_key in ('manager','technician','assistant','requester')
     and template_version = 5),
  4::bigint,
  'new tenants are provisioned directly with all official templates at version five'
);
select is(
  (select count(*) from public.tenant_profile_permissions as baseline
   join public.tenant_profiles as profile on profile.id = baseline.profile_id
   join public.permission_catalog as permission on permission.id = baseline.permission_id
   where profile.tenant_id = '5a200000-0000-4000-8000-000000000002'
     and permission.resource_code in ('asset_types','assets','asset_files')),
  31::bigint,
  'new tenants receive the exact W5A baseline without a second rollout system'
);

select is(
  (select count(*) from public.permission_catalog
   where module_code = 'core' and resource_code in ('users','profiles')),
  11::bigint,
  'the W2 authorization catalog remains intact'
);
select is(
  (select count(*) from public.permission_catalog
   where module_code = 'shared'
     and resource_code in ('location_types','locations','cost_centers','sectors','teams','team_memberships')),
  37::bigint,
  'the W4 shared authorization catalog remains intact'
);
select is(
  (select count(*) from public.permission_catalog where module_code = 'maintenance'),
  31::bigint,
  'the W4 maintenance authorization catalog remains intact'
);

select * from finish();
rollback;
