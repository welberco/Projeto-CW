begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

create temporary table w2a_expected_permissions (
  id uuid primary key,
  code text not null unique,
  module_code text not null,
  resource_code text not null,
  action_code text not null,
  scope public.authorization_scope not null
);

insert into w2a_expected_permissions (
  id, code, module_code, resource_code, action_code, scope
)
values
  ('91000000-0000-4000-8000-000000000001', 'core.users.read.all_tenant', 'core', 'users', 'read', 'ALL_TENANT'),
  ('91000000-0000-4000-8000-000000000002', 'core.users.invite.all_tenant', 'core', 'users', 'invite', 'ALL_TENANT'),
  ('91000000-0000-4000-8000-000000000003', 'core.users.assign_profile.all_tenant', 'core', 'users', 'assign_profile', 'ALL_TENANT'),
  ('91000000-0000-4000-8000-000000000004', 'core.users.manage_overrides.all_tenant', 'core', 'users', 'manage_overrides', 'ALL_TENANT'),
  ('91000000-0000-4000-8000-000000000005', 'core.users.change_status.all_tenant', 'core', 'users', 'change_status', 'ALL_TENANT'),
  ('91000000-0000-4000-8000-000000000006', 'core.profiles.read.all_tenant', 'core', 'profiles', 'read', 'ALL_TENANT'),
  ('91000000-0000-4000-8000-000000000007', 'core.profiles.create.all_tenant', 'core', 'profiles', 'create', 'ALL_TENANT'),
  ('91000000-0000-4000-8000-000000000008', 'core.profiles.update.all_tenant', 'core', 'profiles', 'update', 'ALL_TENANT'),
  ('91000000-0000-4000-8000-000000000009', 'core.profiles.activate.all_tenant', 'core', 'profiles', 'activate', 'ALL_TENANT'),
  ('91000000-0000-4000-8000-000000000010', 'core.profiles.inactivate.all_tenant', 'core', 'profiles', 'inactivate', 'ALL_TENANT'),
  ('91000000-0000-4000-8000-000000000011', 'core.profiles.change_permissions.all_tenant', 'core', 'profiles', 'change_permissions', 'ALL_TENANT');

-- Physical model and exact scope taxonomy.
select has_table('public', 'permission_catalog', 'permission catalog exists');
select has_table('private', 'authorization_catalog_state', 'catalog revision state exists');
select has_table('private', 'authorization_profile_templates', 'platform profile templates exist');
select has_table('private', 'authorization_profile_template_permissions', 'platform template grants exist');

select is(
  (
    select enum_values::text
    from (
      select pg_catalog.enum_range(null::public.authorization_scope) as enum_values
    ) as scope_taxonomy
  ),
  '{OWN,ASSIGNED,TEAM,ALL_TENANT}',
  'the four official scopes exist exactly and remain distinct'
);

select isnt('OWN'::public.authorization_scope, 'ASSIGNED'::public.authorization_scope, 'OWN is distinct from ASSIGNED');
select isnt('ASSIGNED'::public.authorization_scope, 'TEAM'::public.authorization_scope, 'ASSIGNED is distinct from TEAM');
select isnt('TEAM'::public.authorization_scope, 'ALL_TENANT'::public.authorization_scope, 'TEAM is distinct from ALL_TENANT');

select is(
  (
    select count(*)
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname in ('public', 'private')
      and relation.relname in (
        'authorization_scope_hierarchy',
        'authorization_scope_precedence',
        'authorization_scope_implications'
      )
  ),
  0::bigint,
  'no hierarchy, precedence or implication relation exists between scopes'
);

select ok(
  (
    select relation.relrowsecurity
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = 'permission_catalog'
  ),
  'permission catalog has RLS enabled from creation'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'permission_catalog'
  ),
  0::bigint,
  'permission catalog has no permissive client policy in W2A'
);

-- Deterministic W2 platform seed. Later waves may extend the global catalog.
select is(
  (
    select count(*)
    from w2a_expected_permissions as expected
    join public.permission_catalog as permission
      on permission.id = expected.id
     and permission.code = expected.code
     and permission.module_code = expected.module_code
     and permission.resource_code = expected.resource_code
     and permission.action_code = expected.action_code
     and permission.scope = expected.scope
  ),
  11::bigint,
  'the exact eleven W2 permission identities and combinations remain present'
);

select is(
  (
    select count(*)
    from w2a_expected_permissions as expected
    join public.permission_catalog as permission
      using (id, code)
  ),
  11::bigint,
  'permission IDs and codes are deterministic across environments'
);

select is(
  (select count(distinct (module_code, resource_code, action_code, scope)) from public.permission_catalog),
  (select count(*) from public.permission_catalog),
  'every global Resource + Action + Scope combination remains structurally unique'
);

select is((select count(distinct code) from public.permission_catalog), (select count(*) from public.permission_catalog), 'every global permission code remains unique');
select is((select count(*) from public.permission_catalog where id in (select id from w2a_expected_permissions) and scope <> 'ALL_TENANT'), 0::bigint, 'W2 administrative seed uses only ALL_TENANT inside the current tenant');
select is((select count(*) from public.permission_catalog where id in (select id from w2a_expected_permissions) and module_code <> 'core'), 0::bigint, 'W2 seed contains no module outside core');
select is((select count(*) from public.permission_catalog where id in (select id from w2a_expected_permissions) and resource_code not in ('users', 'profiles')), 0::bigint, 'W2 seed contains only users and profiles resources');
select is((select count(*) from public.permission_catalog where id in (select id from w2a_expected_permissions) and required_entitlement_key is not null), 0::bigint, 'W2 core administrative permissions do not duplicate entitlement');
select is((select count(*) from public.permission_catalog where id in (select id from w2a_expected_permissions) and not tenant_delegable), 0::bigint, 'the eleven approved W2 combinations carry delegability metadata');
select is((select count(*) from public.permission_catalog where id in (select id from w2a_expected_permissions) and status <> 'active'), 0::bigint, 'all W2 combinations remain active');
select is((select count(*) from public.permission_catalog where code like '%global_admin%' or code like '%platform%'), 0::bigint, 'Global Admin is absent from the tenant permission catalog');

select is((select count(*) from private.authorization_profile_templates), 4::bigint, 'four platform profile templates are seeded');
select is(
  (
    select count(*)
    from private.authorization_profile_templates
    where (id, template_key, default_name) in (
      ('92000000-0000-4000-8000-000000000001', 'manager', 'Gestor'),
      ('92000000-0000-4000-8000-000000000002', 'technician', 'Técnico'),
      ('92000000-0000-4000-8000-000000000003', 'assistant', 'Auxiliar'),
      ('92000000-0000-4000-8000-000000000004', 'requester', 'Solicitante')
    )
      and template_version >= 1
  ),
  4::bigint,
  'template identities and initial labels remain deterministic across versioned extensions'
);
select is(
  (
    select count(*)
    from private.authorization_profile_template_permissions as template_permission
    join private.authorization_profile_templates as template
      on template.id = template_permission.template_id
    join w2a_expected_permissions as expected on expected.id = template_permission.permission_id
    where template.template_key = 'manager'
  ),
  11::bigint,
  'manager template contains the approved eleven platform-seed grants'
);
select is(
  (
    select count(*)
    from private.authorization_profile_template_permissions as template_permission
    join private.authorization_profile_templates as template
      on template.id = template_permission.template_id
    join w2a_expected_permissions as expected on expected.id = template_permission.permission_id
    where template.template_key in ('technician', 'assistant', 'requester')
  ),
  0::bigint,
  'technician, assistant and requester receive no premature functional grants'
);

select is(to_regclass('public.tenant_profiles'), 'public.tenant_profiles'::regclass, 'W2B now owns tenant profiles');
select is(to_regclass('public.tenant_profile_permissions'), 'public.tenant_profile_permissions'::regclass, 'W2B now owns tenant baseline grants');
select is(to_regclass('public.tenant_permission_overrides'), 'public.tenant_permission_overrides'::regclass, 'W2B now owns individual overrides');

-- Structural integrity and catalog lifecycle.
select is(
  (
    select count(*)
    from pg_catalog.pg_constraint
    where conrelid = 'public.permission_catalog'::regclass
      and conname in (
        'permission_catalog_code_key',
        'permission_catalog_combination_key'
      )
      and contype = 'u'
  ),
  2::bigint,
  'code and exact structural combination have independent unique constraints'
);

select throws_ok(
  $$
    insert into public.permission_catalog (
      id, code, module_code, resource_code, action_code, scope,
      tenant_delegable, label_key
    ) values (
      'f2a00000-0000-4000-8000-000000000001',
      'core.users.update.own', 'core', 'users', 'update', 'ASSIGNED',
      true, 'authorization.permissions.test.label'
    )
  $$,
  '23514',
  null,
  'permission code must exactly match module, resource, action and scope'
);

select throws_ok(
  $$
    insert into public.permission_catalog (
      id, code, module_code, resource_code, action_code, scope,
      required_entitlement_key, tenant_delegable, label_key
    ) values (
      'f2a00000-0000-4000-8000-000000000002',
      'core.users.update.own', 'core', 'users', 'update', 'OWN',
      'Invalid Entitlement', true, 'authorization.permissions.test.label'
    )
  $$,
  '23514',
  null,
  'entitlement metadata uses a stable lowercase machine key'
);

select throws_ok(
  $$
    insert into public.permission_catalog (
      id, code, module_code, resource_code, action_code, scope,
      tenant_delegable, label_key, status
    ) values (
      'f2a00000-0000-4000-8000-000000000003',
      'core.users.update.own', 'core', 'users', 'update', 'OWN',
      true, 'authorization.permissions.test.label', 'deprecated'
    )
  $$,
  '23514',
  null,
  'deprecated catalog entries require a deprecation timestamp'
);

select is((select count(*) from public.permission_catalog where code = 'core.users.update.own'), 0::bigint, 'an unapproved combination is absent instead of cartesian-seeded');
select is((select count(*) from public.permission_catalog where code = 'core.profiles.manage.all_tenant'), 0::bigint, 'no wildcard-like manage combination is invented');

create temporary table w2a_revision_snapshot as
select catalog_revision
from private.authorization_catalog_state;

select ok((select catalog_revision > 0 from w2a_revision_snapshot), 'catalog revision is initialized before mutation checks');

insert into public.permission_catalog (
  id, code, module_code, resource_code, action_code, scope,
  tenant_delegable, label_key
)
values (
  'f2a00000-0000-4000-8000-000000000010',
  'core.users.update.own', 'core', 'users', 'update', 'OWN',
  true, 'authorization.permissions.test.label'
);

select is(
  (select catalog_revision from private.authorization_catalog_state),
  (select catalog_revision + 1 from w2a_revision_snapshot),
  'adding a catalog combination increments the persistent revision'
);

update public.permission_catalog
set status = 'deprecated', deprecated_at = statement_timestamp()
where id = 'f2a00000-0000-4000-8000-000000000010';

select is(
  (select catalog_revision from private.authorization_catalog_state),
  (select catalog_revision + 2 from w2a_revision_snapshot),
  'deprecating a catalog combination increments the persistent revision'
);

select throws_ok(
  $$
    update public.permission_catalog
    set code = 'core.users.update.assigned'
    where id = 'f2a00000-0000-4000-8000-000000000010'
  $$,
  'P0001',
  'PERMISSION_CATALOG_IDENTITY_IMMUTABLE',
  'stable permission identity cannot be rewritten'
);

select throws_ok(
  $$
    delete from public.permission_catalog
    where id = 'f2a00000-0000-4000-8000-000000000010'
  $$,
  'P0001',
  'PERMISSION_CATALOG_HARD_DELETE_FORBIDDEN',
  'catalog entries are deprecated rather than hard deleted'
);

select throws_ok(
  $$
    update private.authorization_catalog_state
    set catalog_revision = catalog_revision
    where singleton
  $$,
  'P0001',
  'AUTHORIZATION_CATALOG_REVISION_MUST_INCREASE',
  'catalog revision cannot stay unchanged or decrease'
);

-- Least privilege, ownership and function hardening.
select is(
  (
    select count(*)
    from information_schema.table_privileges
    where table_schema in ('public', 'private')
      and table_name in (
        'permission_catalog',
        'authorization_catalog_state',
        'authorization_profile_templates',
        'authorization_profile_template_permissions'
      )
      and grantee in ('PUBLIC', 'anon', 'authenticated', 'service_role')
  ),
  0::bigint,
  'client and technical API roles have no direct W2A table privileges'
);

select is(
  (
    select count(*)
    from information_schema.usage_privileges
    where object_schema = 'public'
      and object_name = 'authorization_scope'
      and object_type = 'TYPE'
      and grantee = 'PUBLIC'
  ),
  0::bigint,
  'PUBLIC has no authorization-scope type usage'
);
select is(has_type_privilege('anon', 'public.authorization_scope', 'USAGE'), false, 'anon has no authorization-scope type usage');
select is(has_type_privilege('authenticated', 'public.authorization_scope', 'USAGE'), false, 'authenticated has no authorization-scope type usage');
select is(has_type_privilege('service_role', 'public.authorization_scope', 'USAGE'), false, 'service role has no direct authorization-scope type usage');
select is(has_table_privilege('service_role', 'public.permission_catalog', 'SELECT'), false, 'service role has no direct catalog read privilege');

select is(
  (
    select count(*)
    from information_schema.routine_privileges
    where routine_schema = 'private'
      and routine_name in (
        'protect_authorization_catalog_state',
        'protect_permission_catalog_mutation',
        'bump_authorization_catalog_revision'
      )
      and grantee in ('PUBLIC', 'anon', 'authenticated', 'service_role')
  ),
  0::bigint,
  'W2A trigger functions expose no EXECUTE capability to API roles'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'private'
      and procedure.proname in (
        'protect_authorization_catalog_state',
        'protect_permission_catalog_mutation',
        'bump_authorization_catalog_revision'
      )
      and procedure.prosecdef
  ),
  0::bigint,
  'W2A requires no SECURITY DEFINER function'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'private'
      and procedure.proname in (
        'protect_authorization_catalog_state',
        'protect_permission_catalog_mutation',
        'bump_authorization_catalog_revision'
      )
      and not exists (
        select 1
        from pg_catalog.unnest(coalesce(procedure.proconfig, array[]::text[])) as configuration(setting)
        where pg_catalog.split_part(configuration.setting, '=', 1) = 'search_path'
          and pg_catalog.replace(pg_catalog.split_part(configuration.setting, '=', 2), '"', '') = ''
      )
  ),
  0::bigint,
  'all W2A functions fix an empty search_path'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    join pg_catalog.pg_roles as owner_role
      on owner_role.oid = relation.relowner
    where namespace.nspname in ('public', 'private')
      and relation.relname in (
        'permission_catalog',
        'authorization_catalog_state',
        'authorization_profile_templates',
        'authorization_profile_template_permissions'
      )
      and owner_role.rolname in ('PUBLIC', 'anon', 'authenticated', 'service_role')
  ),
  0::bigint,
  'W2A tables are not owned by client-facing or technical API roles'
);

set local role authenticated;

select throws_ok(
  $$ select count(*) from public.permission_catalog $$,
  '42501', null, 'authenticated cannot read the structural catalog directly'
);
select throws_ok(
  $$
    insert into public.permission_catalog (
      id, code, module_code, resource_code, action_code, scope,
      tenant_delegable, label_key
    ) values (
      'f2a00000-0000-4000-8000-000000000020',
      'core.users.update.team', 'core', 'users', 'update', 'TEAM',
      true, 'authorization.permissions.test.label'
    )
  $$,
  '42501', null, 'authenticated cannot create structural permissions'
);
select throws_ok(
  $$ update public.permission_catalog set tenant_delegable = false $$,
  '42501', null, 'authenticated cannot alter structural permissions'
);
select throws_ok(
  $$ delete from public.permission_catalog $$,
  '42501', null, 'authenticated cannot delete structural permissions'
);
select throws_ok(
  $$ select catalog_revision from private.authorization_catalog_state $$,
  '42501', null, 'authenticated cannot read private catalog state directly'
);

reset role;
set local role anon;

select throws_ok(
  $$ select count(*) from public.permission_catalog $$,
  '42501', null, 'anon cannot read the structural catalog'
);
select throws_ok(
  $$ update public.permission_catalog set tenant_delegable = false $$,
  '42501', null, 'anon cannot alter the structural catalog'
);

reset role;

select * from finish();
rollback;
