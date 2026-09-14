begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

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

-- Deterministic minimal platform seed.
select is((select count(*) from public.permission_catalog), 11::bigint, 'exactly eleven administrative combinations are seeded');

select is(
  (
    with expected(id, code) as (
      values
        ('91000000-0000-4000-8000-000000000001'::uuid, 'core.users.read.all_tenant'),
        ('91000000-0000-4000-8000-000000000002'::uuid, 'core.users.invite.all_tenant'),
        ('91000000-0000-4000-8000-000000000003'::uuid, 'core.users.assign_profile.all_tenant'),
        ('91000000-0000-4000-8000-000000000004'::uuid, 'core.users.manage_overrides.all_tenant'),
        ('91000000-0000-4000-8000-000000000005'::uuid, 'core.users.change_status.all_tenant'),
        ('91000000-0000-4000-8000-000000000006'::uuid, 'core.profiles.read.all_tenant'),
        ('91000000-0000-4000-8000-000000000007'::uuid, 'core.profiles.create.all_tenant'),
        ('91000000-0000-4000-8000-000000000008'::uuid, 'core.profiles.update.all_tenant'),
        ('91000000-0000-4000-8000-000000000009'::uuid, 'core.profiles.activate.all_tenant'),
        ('91000000-0000-4000-8000-000000000010'::uuid, 'core.profiles.inactivate.all_tenant'),
        ('91000000-0000-4000-8000-000000000011'::uuid, 'core.profiles.change_permissions.all_tenant')
    )
    select count(*)
    from expected
    join public.permission_catalog as permission
      using (id, code)
  ),
  11::bigint,
  'permission IDs and codes are deterministic across environments'
);

select is(
  (select count(distinct (module_code, resource_code, action_code, scope)) from public.permission_catalog),
  11::bigint,
  'every seeded Resource + Action + Scope combination is structurally unique'
);

select is((select count(distinct code) from public.permission_catalog), 11::bigint, 'every permission code is unique');
select is((select count(*) from public.permission_catalog where scope <> 'ALL_TENANT'), 0::bigint, 'administrative seed uses only ALL_TENANT inside the current tenant');
select is((select count(*) from public.permission_catalog where module_code <> 'core'), 0::bigint, 'no future module catalog is seeded');
select is((select count(*) from public.permission_catalog where resource_code not in ('users', 'profiles')), 0::bigint, 'only users and profiles resources are seeded');
select is((select count(*) from public.permission_catalog where required_entitlement_key is not null), 0::bigint, 'core administrative permissions do not duplicate entitlement');
select is((select count(*) from public.permission_catalog where not tenant_delegable), 0::bigint, 'the eleven approved tenant combinations carry delegability metadata');
select is((select count(*) from public.permission_catalog where status <> 'active'), 0::bigint, 'all seeded combinations start active');
select is((select count(*) from public.permission_catalog where code like '%global_admin%' or code like '%platform%'), 0::bigint, 'Global Admin is absent from the tenant permission catalog');

select is((select count(*) from private.authorization_profile_templates), 4::bigint, 'four platform profile templates are seeded');
select is(
  (
    select count(*)
    from private.authorization_profile_templates
    where (id, template_key, template_version, default_name) in (
      ('92000000-0000-4000-8000-000000000001', 'manager', 1, 'Gestor'),
      ('92000000-0000-4000-8000-000000000002', 'technician', 1, 'Técnico'),
      ('92000000-0000-4000-8000-000000000003', 'assistant', 1, 'Auxiliar'),
      ('92000000-0000-4000-8000-000000000004', 'requester', 1, 'Solicitante')
    )
  ),
  4::bigint,
  'template identities, versions and initial labels are deterministic'
);
select is(
  (
    select count(*)
    from private.authorization_profile_template_permissions as template_permission
    join private.authorization_profile_templates as template
      on template.id = template_permission.template_id
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
    where template.template_key in ('technician', 'assistant', 'requester')
  ),
  0::bigint,
  'technician, assistant and requester receive no premature functional grants'
);

select is(to_regclass('public.tenant_profiles'), null::regclass, 'tenant profiles remain deferred to W2B');
select is(to_regclass('public.tenant_profile_permissions'), null::regclass, 'tenant baseline grants remain deferred to W2B');
select is(to_regclass('public.tenant_permission_overrides'), null::regclass, 'individual overrides remain deferred to W2B');

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
      '93000000-0000-4000-8000-000000000001',
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
      '93000000-0000-4000-8000-000000000002',
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
      '93000000-0000-4000-8000-000000000003',
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

select is((select catalog_revision from w2a_revision_snapshot), 12::bigint, 'initial catalog revision deterministically reflects the eleven seeded rows');

insert into public.permission_catalog (
  id, code, module_code, resource_code, action_code, scope,
  tenant_delegable, label_key
)
values (
  '93000000-0000-4000-8000-000000000010',
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
where id = '93000000-0000-4000-8000-000000000010';

select is(
  (select catalog_revision from private.authorization_catalog_state),
  (select catalog_revision + 2 from w2a_revision_snapshot),
  'deprecating a catalog combination increments the persistent revision'
);

select throws_ok(
  $$
    update public.permission_catalog
    set code = 'core.users.update.assigned'
    where id = '93000000-0000-4000-8000-000000000010'
  $$,
  'P0001',
  'PERMISSION_CATALOG_IDENTITY_IMMUTABLE',
  'stable permission identity cannot be rewritten'
);

select throws_ok(
  $$
    delete from public.permission_catalog
    where id = '93000000-0000-4000-8000-000000000010'
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
      '93000000-0000-4000-8000-000000000020',
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
