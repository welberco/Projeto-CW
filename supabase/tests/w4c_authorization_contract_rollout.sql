begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

create temporary table w4c_expected_permissions (
  code text primary key,
  resource_code text not null,
  action_code text not null
);

insert into w4c_expected_permissions (code, resource_code, action_code)
select
  'maintenance.' || permission.resource_code || '.' || permission.action_code || '.all_tenant',
  permission.resource_code,
  permission.action_code
from (values
  ('maintenance_categories','read'), ('maintenance_categories','lookup'),
  ('maintenance_categories','create'), ('maintenance_categories','update'),
  ('maintenance_categories','inactivate'), ('maintenance_categories','reactivate'),
  ('maintenance_subcategories','read'), ('maintenance_subcategories','lookup'),
  ('maintenance_subcategories','create'), ('maintenance_subcategories','update'),
  ('maintenance_subcategories','inactivate'), ('maintenance_subcategories','reactivate'),
  ('maintenance_reasons','read'), ('maintenance_reasons','lookup'),
  ('maintenance_reasons','create'), ('maintenance_reasons','update'),
  ('maintenance_reasons','inactivate'), ('maintenance_reasons','reactivate'),
  ('document_types','read'), ('document_types','lookup'),
  ('document_types','create'), ('document_types','update'),
  ('document_types','inactivate'), ('document_types','reactivate'),
  ('checklist_templates','read'), ('checklist_templates','lookup'),
  ('checklist_templates','create'), ('checklist_templates','update'),
  ('checklist_templates','inactivate'), ('checklist_templates','reactivate'),
  ('catalog_templates','apply')
) as permission(resource_code, action_code);

create temporary table w4c_expected_template_permissions (
  template_key text not null,
  permission_code text not null,
  primary key (template_key, permission_code)
);

insert into w4c_expected_template_permissions (template_key, permission_code)
values
  ('manager','maintenance.maintenance_categories.read.all_tenant'),
  ('manager','maintenance.maintenance_categories.lookup.all_tenant'),
  ('manager','maintenance.maintenance_categories.create.all_tenant'),
  ('manager','maintenance.maintenance_categories.update.all_tenant'),
  ('manager','maintenance.maintenance_categories.inactivate.all_tenant'),
  ('manager','maintenance.maintenance_subcategories.read.all_tenant'),
  ('manager','maintenance.maintenance_subcategories.lookup.all_tenant'),
  ('manager','maintenance.maintenance_subcategories.create.all_tenant'),
  ('manager','maintenance.maintenance_subcategories.update.all_tenant'),
  ('manager','maintenance.maintenance_subcategories.inactivate.all_tenant'),
  ('manager','maintenance.maintenance_reasons.read.all_tenant'),
  ('manager','maintenance.maintenance_reasons.lookup.all_tenant'),
  ('manager','maintenance.maintenance_reasons.create.all_tenant'),
  ('manager','maintenance.maintenance_reasons.update.all_tenant'),
  ('manager','maintenance.maintenance_reasons.inactivate.all_tenant'),
  ('manager','maintenance.document_types.read.all_tenant'),
  ('manager','maintenance.document_types.lookup.all_tenant'),
  ('manager','maintenance.checklist_templates.read.all_tenant'),
  ('manager','maintenance.checklist_templates.lookup.all_tenant'),
  ('manager','maintenance.catalog_templates.apply.all_tenant'),
  ('technician','maintenance.maintenance_categories.lookup.all_tenant'),
  ('technician','maintenance.maintenance_subcategories.lookup.all_tenant'),
  ('technician','maintenance.maintenance_reasons.lookup.all_tenant'),
  ('technician','maintenance.document_types.lookup.all_tenant'),
  ('technician','maintenance.checklist_templates.lookup.all_tenant'),
  ('assistant','maintenance.maintenance_categories.lookup.all_tenant'),
  ('assistant','maintenance.maintenance_subcategories.lookup.all_tenant'),
  ('assistant','maintenance.maintenance_reasons.lookup.all_tenant'),
  ('assistant','maintenance.document_types.lookup.all_tenant'),
  ('assistant','maintenance.checklist_templates.lookup.all_tenant'),
  ('requester','maintenance.maintenance_categories.lookup.all_tenant'),
  ('requester','maintenance.maintenance_subcategories.lookup.all_tenant');

select is(
  (select count(*) from public.permission_catalog where module_code = 'maintenance'),
  31::bigint,
  'W4C.1 publishes exactly thirty-one maintenance permissions'
);
select is(
  (select count(*) from (
    select code, resource_code, action_code
    from public.permission_catalog where module_code = 'maintenance'
    except
    select code, resource_code, action_code from w4c_expected_permissions
  ) as unexpected),
  0::bigint,
  'the W4C.1 permission catalog contains no unexpected combination'
);
select is(
  (select count(*) from (
    select code, resource_code, action_code from w4c_expected_permissions
    except
    select code, resource_code, action_code
    from public.permission_catalog where module_code = 'maintenance'
  ) as missing),
  0::bigint,
  'every frozen W4C.1 permission combination exists'
);
select is(
  (select count(*) from public.permission_catalog
   where module_code = 'maintenance'
     and (scope <> 'ALL_TENANT' or required_entitlement_key <> 'maintenance'
       or not tenant_delegable or status <> 'active')),
  0::bigint,
  'all W4C.1 permissions are active delegable maintenance capabilities with exact ALL_TENANT scope'
);
select is(
  (select count(*) from public.permission_catalog
   where module_code = 'maintenance' and scope in ('TEAM','OWN','ASSIGNED')),
  0::bigint,
  'W4C.1 creates no TEAM, OWN or ASSIGNED scope'
);
select is(
  (select count(*) from public.permission_catalog
   where module_code = 'maintenance'
     and (action_code in ('use','manage') or code like '%*%')),
  0::bigint,
  'W4C.1 creates no generic use, manage or wildcard capability'
);
select is(
  (select array_agg(action_code order by action_code)
   from public.permission_catalog
   where module_code = 'maintenance' and resource_code = 'catalog_templates'),
  array['apply']::text[],
  'catalog_templates exposes only the frozen apply capability'
);
select is(
  (select count(*) from public.permission_catalog
   where module_code = 'maintenance' and action_code = 'reactivate'),
  5::bigint,
  'all five granular reactivate permissions are catalogued'
);

select is(
  (select count(*) from private.authorization_profile_templates
   where template_key in ('manager','technician','assistant','requester')
     and template_version = 4 and status = 'active'),
  4::bigint,
  'all four official templates advance from version three to version four'
);
select is(
  (select count(*) from (
    select template.template_key, permission.code
    from private.authorization_profile_template_permissions as mapping
    join private.authorization_profile_templates as template on template.id = mapping.template_id
    join public.permission_catalog as permission on permission.id = mapping.permission_id
    where template.template_key in ('manager','technician','assistant','requester')
      and permission.module_code = 'maintenance'
    except
    select template_key, permission_code from w4c_expected_template_permissions
  ) as unexpected),
  0::bigint,
  'official templates contain no W4C.1 grant outside the frozen matrix'
);
select is(
  (select count(*) from (
    select template_key, permission_code from w4c_expected_template_permissions
    except
    select template.template_key, permission.code
    from private.authorization_profile_template_permissions as mapping
    join private.authorization_profile_templates as template on template.id = mapping.template_id
    join public.permission_catalog as permission on permission.id = mapping.permission_id
    where permission.module_code = 'maintenance'
  ) as missing),
  0::bigint,
  'official templates contain every frozen W4C.1 baseline grant'
);
select is(
  (select array_agg(grant_count order by template_key) from (
    select template.template_key, count(*)::integer as grant_count
    from private.authorization_profile_template_permissions as mapping
    join private.authorization_profile_templates as template on template.id = mapping.template_id
    join public.permission_catalog as permission on permission.id = mapping.permission_id
    where template.template_key in ('assistant','manager','requester','technician')
      and permission.module_code = 'maintenance'
    group by template.template_key
  ) as counts),
  array[5,20,2,5]::integer[],
  'Assistant, Manager, Requester and Technician receive exactly 5, 20, 2 and 5 grants'
);
select is(
  (select count(*)
   from private.authorization_profile_template_permissions as mapping
   join public.permission_catalog as permission on permission.id = mapping.permission_id
   where permission.module_code = 'maintenance' and permission.action_code = 'reactivate'),
  0::bigint,
  'no official baseline receives a W4C.1 reactivate permission'
);
select is(
  (select count(*)
   from private.authorization_profile_template_permissions as mapping
   join private.authorization_profile_templates as template on template.id = mapping.template_id
   join public.permission_catalog as permission on permission.id = mapping.permission_id
   where permission.code = 'maintenance.catalog_templates.apply.all_tenant'
     and template.template_key = 'manager'),
  1::bigint,
  'Manager receives catalog_templates.apply exactly once'
);
select is(
  (select count(*)
   from private.authorization_profile_template_permissions as mapping
   join private.authorization_profile_templates as template on template.id = mapping.template_id
   join public.permission_catalog as permission on permission.id = mapping.permission_id
   where permission.code = 'maintenance.catalog_templates.apply.all_tenant'
     and template.template_key <> 'manager'),
  0::bigint,
  'no subordinate official baseline receives catalog_templates.apply'
);
select is(
  (select count(*) from (
    select subordinate.permission_code
    from w4c_expected_template_permissions as subordinate
    where subordinate.template_key in ('technician','assistant','requester')
    except
    select manager.permission_code
    from w4c_expected_template_permissions as manager
    where manager.template_key = 'manager'
  ) as undelegable),
  0::bigint,
  'Manager owns every exact W4C.1 capability delegated by subordinate templates'
);

select is(
  (select procedure.prosecdef from pg_catalog.pg_proc as procedure
   where procedure.oid = 'private.apply_w4c_authorization_rollout(uuid)'::regprocedure),
  true,
  'the W4C.1 rollout has its approved SECURITY DEFINER mode'
);
select ok(
  exists (
    select 1
    from pg_catalog.pg_proc as procedure
    cross join pg_catalog.unnest(coalesce(procedure.proconfig,array[]::text[])) as setting(value)
    where procedure.oid = 'private.apply_w4c_authorization_rollout(uuid)'::regprocedure
      and pg_catalog.split_part(setting.value,'=',1) = 'search_path'
      and pg_catalog.replace(pg_catalog.split_part(setting.value,'=',2),'"','') = ''
  ),
  'the W4C.1 rollout fixes an empty search_path'
);
select is(
  (select owner_role.rolname
   from pg_catalog.pg_proc as procedure
   join pg_catalog.pg_roles as owner_role on owner_role.oid = procedure.proowner
   where procedure.oid = 'private.apply_w4c_authorization_rollout(uuid)'::regprocedure),
  'postgres',
  'the W4C.1 rollout has the controlled owner'
);
select is(
  (select count(*) from information_schema.routine_privileges
   where routine_schema = 'private'
     and routine_name = 'apply_w4c_authorization_rollout'
     and grantee in ('PUBLIC','anon','authenticated','service_role','cw_worker')),
  0::bigint,
  'the W4C.1 rollout is not callable by client or technical API roles'
);
select is(
  (select count(*)
   from pg_catalog.pg_class as relation
   join pg_catalog.pg_namespace as namespace on namespace.oid = relation.relnamespace
   where namespace.nspname in ('public','private')
     and relation.relkind in ('r','p')
     and relation.relname in (
       'maintenance_categories','maintenance_subcategories','maintenance_reasons',
       'document_types','checklist_templates','checklist_template_items',
       'catalog_templates','catalog_template_entries','catalog_template_applications'
     )),
  5::bigint,
  'the later W4C.2 wave adds only its two taxonomy and three private template tables'
);
select is(
  (select count(*)
   from pg_catalog.pg_proc as procedure
   join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
   where namespace.nspname = 'public'
     and procedure.proname ~ '(maintenance_categor|maintenance_subcategor|maintenance_reason|document_type|checklist_template|cw_catalog_template)'),
  16::bigint,
  'the later W4C.2 wave adds exactly its nine commands and seven read boundaries'
);
select is(
  (select count(*) from pg_catalog.pg_class as relation
   join pg_catalog.pg_namespace as namespace on namespace.oid = relation.relnamespace
   where namespace.nspname = 'public' and relation.relkind in ('r','p')
     and relation.relname in ('maintenance_reasons','document_types','checklist_templates','checklist_template_items')),
  0::bigint,
  'the W4C.2 boundary still does not anticipate W4C.3 tables'
);
select is(
  has_table_privilege('service_role', 'public.permission_catalog', 'SELECT'),
  false,
  'W4C.1 does not broaden the service-role permission-catalog boundary'
);
select is(
  has_table_privilege('authenticated', 'public.permission_catalog', 'SELECT'),
  false,
  'W4C.1 does not expose the permission catalog directly to frontend principals'
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
     and resource_code in ('location_types','locations','cost_centers','sectors')),
  26::bigint,
  'the W4A authorization catalog remains intact'
);
select is(
  (select count(*) from public.permission_catalog
   where module_code = 'shared' and resource_code in ('teams','team_memberships')),
  11::bigint,
  'the W4B authorization catalog remains intact'
);

insert into auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
values
  ('4c100000-0000-4000-8000-000000000001','authenticated','authenticated','w4c-manager@example.invalid',statement_timestamp(),statement_timestamp(),statement_timestamp()),
  ('4c100000-0000-4000-8000-000000000002','authenticated','authenticated','w4c-new-manager@example.invalid',statement_timestamp(),statement_timestamp(),statement_timestamp());

create temporary table w4c_bootstrap as
select * from public.bootstrap_initial_tenant(
  '4c100000-0000-4000-8000-000000000001',
  'W4C Existing Tenant',
  '4c200000-0000-4000-8000-000000000001'
);

update public.tenant_profiles
set name = 'Manager W4C renamed',
    updated_by = '4c100000-0000-4000-8000-000000000001'
where tenant_id = (select tenant_id from w4c_bootstrap)
  and template_key = 'manager';

insert into public.tenant_profiles (id, tenant_id, name, status, created_by, updated_by)
values (
  '4c300000-0000-4000-8000-000000000001',
  (select tenant_id from w4c_bootstrap),
  'Manager',
  'active',
  '4c100000-0000-4000-8000-000000000001',
  '4c100000-0000-4000-8000-000000000001'
);

insert into public.tenant_profile_permissions (tenant_id, profile_id, permission_id, created_by)
select bootstrap.tenant_id, '4c300000-0000-4000-8000-000000000001', permission.id,
       '4c100000-0000-4000-8000-000000000001'
from w4c_bootstrap as bootstrap
join public.permission_catalog as permission on permission.code = 'shared.teams.read.team';

insert into public.tenant_permission_overrides (
  id, tenant_id, membership_id, permission_id, effect, created_by, updated_by
)
select
  '4c500000-0000-4000-8000-000000000001',
  bootstrap.tenant_id,
  membership.id,
  permission.id,
  'allow',
  '4c100000-0000-4000-8000-000000000001',
  '4c100000-0000-4000-8000-000000000001'
from w4c_bootstrap as bootstrap
join public.tenant_memberships as membership
  on membership.tenant_id = bootstrap.tenant_id
 and membership.user_id = '4c100000-0000-4000-8000-000000000001'
join public.permission_catalog as permission
  on permission.code = 'shared.teams.lookup.team';

create temporary table w4c_override_snapshot as
select id, tenant_id, membership_id, permission_id, effect, version, created_by, updated_by
from public.tenant_permission_overrides
where tenant_id = (select tenant_id from w4c_bootstrap);

delete from public.tenant_profile_permissions as baseline
using public.tenant_profiles as profile, public.permission_catalog as permission
where profile.id = baseline.profile_id
  and permission.id = baseline.permission_id
  and profile.tenant_id = (select tenant_id from w4c_bootstrap)
  and profile.template_key in ('manager','technician','assistant','requester')
  and permission.module_code = 'maintenance';

select is(
  private.apply_w4c_authorization_rollout((select tenant_id from w4c_bootstrap)),
  32,
  'the first rollout adds exactly the thirty-two approved grants across official profiles'
);
select is(
  (select count(*) from private.authorization_profile_rollouts
   where rollout_key = 'w4c_maintenance_catalogs_v1'
     and tenant_id = (select tenant_id from w4c_bootstrap)),
  4::bigint,
  'the W4C.1 ledger records one row per official profile identity'
);
select is(
  (select sum(grants_added)::integer from private.authorization_profile_rollouts
   where rollout_key = 'w4c_maintenance_catalogs_v1'
     and tenant_id = (select tenant_id from w4c_bootstrap)),
  32,
  'the W4C.1 ledger records the exact add-only grant count'
);
select is(
  (select count(*) from (
    select profile.template_key, permission.code
    from public.tenant_profile_permissions as baseline
    join public.tenant_profiles as profile on profile.id = baseline.profile_id
    join public.permission_catalog as permission on permission.id = baseline.permission_id
    where profile.tenant_id = (select tenant_id from w4c_bootstrap)
      and profile.template_key in ('manager','technician','assistant','requester')
      and permission.module_code = 'maintenance'
    except
    select template_key, permission_code from w4c_expected_template_permissions
  ) as unexpected),
  0::bigint,
  'existing-tenant rollout adds no W4C.1 grant outside the frozen matrix'
);
select is(
  (select count(*) from (
    select template_key, permission_code from w4c_expected_template_permissions
    except
    select profile.template_key, permission.code
    from public.tenant_profile_permissions as baseline
    join public.tenant_profiles as profile on profile.id = baseline.profile_id
    join public.permission_catalog as permission on permission.id = baseline.permission_id
    where profile.tenant_id = (select tenant_id from w4c_bootstrap)
      and permission.module_code = 'maintenance'
  ) as missing),
  0::bigint,
  'existing-tenant rollout adds every W4C.1 grant in the frozen matrix'
);
select is(
  (select name from public.tenant_profiles
   where tenant_id = (select tenant_id from w4c_bootstrap) and template_key = 'manager'),
  'Manager W4C renamed',
  'rollout identifies official profiles by template_key and preserves display names'
);
select is(
  (select count(*) from public.tenant_profiles
   where id = '4c300000-0000-4000-8000-000000000001' and template_key is null),
  1::bigint,
  'a custom profile named Manager remains a custom profile'
);
select is(
  (select count(*) from public.tenant_profile_permissions
   where profile_id = '4c300000-0000-4000-8000-000000000001'
     and permission_id = (select id from public.permission_catalog where code = 'shared.teams.read.team')),
  1::bigint,
  'the rollout preserves a pre-existing custom-profile grant'
);
select is(
  (select count(*) from (
    select * from w4c_override_snapshot
    except
    select id, tenant_id, membership_id, permission_id, effect, version, created_by, updated_by
    from public.tenant_permission_overrides
    where tenant_id = (select tenant_id from w4c_bootstrap)
  ) as changed),
  0::bigint,
  'the rollout preserves every pre-existing exact override'
);
select is(
  private.apply_w4c_authorization_rollout((select tenant_id from w4c_bootstrap)),
  32,
  'rollout replay returns the recorded result without adding grants again'
);
select is(
  (select count(*) from public.audit_events
   where tenant_id = (select tenant_id from w4c_bootstrap)
     and event_type = 'authorization.profile.baseline_rolled_out'
     and actor_ref = 'w4c.authorization_rollout'
     and metadata->>'rollout_key' = 'w4c_maintenance_catalogs_v1'),
  4::bigint,
  'first rollout emits one Audit fact per official profile and replay emits none'
);

insert into public.tenants (id, tenant_ref, display_name, status, created_by)
values (
  '4c200000-0000-4000-8000-000000000002',
  '4c210000-0000-4000-8000-000000000002',
  'W4C Newly Provisioned Tenant',
  'active',
  '4c100000-0000-4000-8000-000000000001'
);

create temporary table w4c_new_provisioning as
select * from private.provision_tenant_authorization(
  '4c200000-0000-4000-8000-000000000002',
  null,
  '4c100000-0000-4000-8000-000000000001',
  '4c220000-0000-4000-8000-000000000002'
);

select is(
  (select count(*) from public.tenant_profiles
   where tenant_id = '4c200000-0000-4000-8000-000000000002'
     and template_key in ('manager','technician','assistant','requester')
     and template_version = 4),
  4::bigint,
  'a new tenant is provisioned directly with all four template instances at version four'
);
select is(
  (select count(*) from public.tenant_profile_permissions as baseline
   join public.tenant_profiles as profile on profile.id = baseline.profile_id
   join public.permission_catalog as permission on permission.id = baseline.permission_id
   where profile.tenant_id = '4c200000-0000-4000-8000-000000000002'
     and permission.module_code = 'maintenance'),
  32::bigint,
  'a new tenant receives the exact current W4C.1 baseline during provisioning'
);

set local "request.jwt.claim.sub" = '4c100000-0000-4000-8000-000000000001';
select is(
  private.has_effective_permission('maintenance_categories','lookup','ALL_TENANT'),
  true,
  'the exact Manager W4C.1 lookup grant resolves normally'
);
select is(
  private.has_effective_permission('maintenance_categories','lookup','TEAM'),
  false,
  'ALL_TENANT does not imply a nonexistent TEAM W4C.1 grant'
);
select is(
  private.has_effective_permission('maintenance_categories','reactivate','ALL_TENANT'),
  false,
  'absence of reactivate in the Manager baseline remains fail-closed'
);

select * from finish();
rollback;
