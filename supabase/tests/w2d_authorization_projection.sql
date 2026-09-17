begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select has_function(
  'public', 'resolve_my_authorization', array[]::text[],
  'the W2D self projection RPC exists without target arguments'
);
select ok(
  has_function_privilege('authenticated', 'public.resolve_my_authorization()', 'EXECUTE'),
  'authenticated can execute the self projection'
);
select is(
  has_function_privilege('anon', 'public.resolve_my_authorization()', 'EXECUTE'),
  false,
  'anon cannot execute the self projection'
);
select is(
  has_function_privilege('service_role', 'public.resolve_my_authorization()', 'EXECUTE'),
  false,
  'service_role is not modeled as a functional projection principal'
);
select is(
  (
    select procedure.prosecdef
    from pg_catalog.pg_proc as procedure
    where procedure.oid = 'public.resolve_my_authorization()'::regprocedure
  ),
  true,
  'the closed authorization tables justify a narrow SECURITY DEFINER projection'
);
select ok(
  exists (
    select 1
    from pg_catalog.pg_proc as procedure
    cross join pg_catalog.unnest(coalesce(procedure.proconfig, array[]::text[])) as configuration(setting)
    where procedure.oid = 'public.resolve_my_authorization()'::regprocedure
      and pg_catalog.split_part(configuration.setting, '=', 1) = 'search_path'
      and pg_catalog.replace(pg_catalog.split_part(configuration.setting, '=', 2), '"', '') = ''
  ),
  'the projection fixes an empty search_path'
);
select is(
  (
    select owner_role.rolname
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_roles as owner_role on owner_role.oid = procedure.proowner
    where procedure.oid = 'public.resolve_my_authorization()'::regprocedure
  ) in ('anon', 'authenticated', 'service_role'),
  false,
  'the projection owner is not a client-facing role'
);

set local role authenticated;
select is(
  (select projection_status from public.resolve_my_authorization()),
  'unauthenticated',
  'an authenticated role without a principal receives a fail-closed status'
);
reset role;

insert into auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
values
  ('18000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'w2d-manager@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp()),
  ('18000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'w2d-unbound@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp());

create temporary table w2d_bootstrap as
select * from public.bootstrap_initial_tenant(
  '18000000-0000-4000-8000-000000000001',
  'W2D Tenant',
  '58000000-0000-4000-8000-000000000001'
);
grant select on w2d_bootstrap to authenticated;

create temporary table w2d_expected_permissions as
with approved_w2(code) as (
  values
    ('core.users.read.all_tenant'),
    ('core.users.invite.all_tenant'),
    ('core.users.assign_profile.all_tenant'),
    ('core.users.manage_overrides.all_tenant'),
    ('core.users.change_status.all_tenant'),
    ('core.profiles.read.all_tenant'),
    ('core.profiles.create.all_tenant'),
    ('core.profiles.update.all_tenant'),
    ('core.profiles.activate.all_tenant'),
    ('core.profiles.inactivate.all_tenant'),
    ('core.profiles.change_permissions.all_tenant')
), approved_w4a(code) as (
  values
    ('shared.location_types.read.all_tenant'),
    ('shared.location_types.lookup.all_tenant'),
    ('shared.location_types.create.all_tenant'),
    ('shared.location_types.update.all_tenant'),
    ('shared.location_types.inactivate.all_tenant'),
    ('shared.locations.read.all_tenant'),
    ('shared.locations.lookup.all_tenant'),
    ('shared.locations.create.all_tenant'),
    ('shared.locations.update.all_tenant'),
    ('shared.locations.move.all_tenant'),
    ('shared.locations.inactivate.all_tenant'),
    ('shared.cost_centers.read.all_tenant'),
    ('shared.cost_centers.lookup.all_tenant'),
    ('shared.cost_centers.create.all_tenant'),
    ('shared.cost_centers.update.all_tenant'),
    ('shared.cost_centers.move.all_tenant'),
    ('shared.cost_centers.inactivate.all_tenant'),
    ('shared.sectors.read.all_tenant'),
    ('shared.sectors.lookup.all_tenant'),
    ('shared.sectors.create.all_tenant'),
    ('shared.sectors.update.all_tenant'),
    ('shared.sectors.inactivate.all_tenant')
)
select
  pg_catalog.array_agg(approved.code order by approved.code) as codes,
  count(*)::integer as permission_count,
  count(*) filter (where approved.source_wave = 'W2')::integer as w2_permission_count,
  count(*) filter (where approved.source_wave = 'W4A')::integer as w4a_permission_count
from (
  select code, 'W2'::text as source_wave from approved_w2
  union all
  select code, 'W4A'::text as source_wave from approved_w4a
) as approved;
grant select on w2d_expected_permissions to authenticated;

select is((select w2_permission_count from w2d_expected_permissions), 11, 'the projection fixture preserves the exact W2 permission allowlist');
select is((select w4a_permission_count from w2d_expected_permissions), 22, 'the projection fixture recognizes only the approved W4A manager extension');

set local "request.jwt.claim.sub" = '18000000-0000-4000-8000-000000000002';
set local role authenticated;
select is(
  (select projection_status from public.resolve_my_authorization()),
  'no_membership',
  'a principal without a membership receives no authorization data'
);
select is(
  (select permission_codes from public.resolve_my_authorization()),
  array[]::text[],
  'an unavailable projection exposes no permission payload'
);
reset role;

set local "request.jwt.claim.sub" = '18000000-0000-4000-8000-000000000001';
set local role authenticated;
select is(
  (select projection_status from public.resolve_my_authorization()),
  'ready',
  'an active principal receives a ready self projection'
);
select is(
  (select principal_id from public.resolve_my_authorization()),
  '18000000-0000-4000-8000-000000000001'::uuid,
  'the principal always derives from auth.uid()'
);
select is(
  (select tenant_id from public.resolve_my_authorization()),
  (select tenant_id from w2d_bootstrap),
  'the projection contains only the current membership tenant'
);
select is(
  (select tenant_ref from public.resolve_my_authorization()),
  (select tenant_ref from w2d_bootstrap),
  'the projection includes the current public route selector'
);
select is(
  (select cardinality(permission_codes) from public.resolve_my_authorization()),
  (select permission_count from w2d_expected_permissions),
  'the manager receives exactly the allowlisted W2 plus W4A permission codes'
);
select is(
  (
    select permission_codes = (
      select codes
      from w2d_expected_permissions
    )
    from public.resolve_my_authorization()
  ),
  true,
  'permission codes are exact, deterministic and sorted'
);
select is(
  (select enabled_entitlements from public.resolve_my_authorization()),
  array['maintenance']::text[],
  'enabled entitlements are projected separately from permissions'
);
select is(
  (
    select authorization_revision = pg_catalog.format(
      'm%s:p%s:c%s', membership_version, profile_version, catalog_revision
    )
    from public.resolve_my_authorization()
  ),
  true,
  'the revision serialization is canonical membership/profile/catalog'
);
reset role;

create temporary table w2d_initial_projection as
select * from public.resolve_my_authorization();
grant select on w2d_initial_projection to authenticated;

update public.tenant_profiles
set name = 'Gestor W2D'
where id = (select profile_id from w2d_initial_projection);

set local role authenticated;
select isnt(
  (select authorization_revision from public.resolve_my_authorization()),
  (select authorization_revision from w2d_initial_projection),
  'profile.version changes invalidate the revision without membership fanout'
);
reset role;

create temporary table w2d_profile_projection as
select * from public.resolve_my_authorization();
grant select on w2d_profile_projection to authenticated;

insert into public.tenant_permission_overrides (
  tenant_id, membership_id, permission_id, effect, created_by, updated_by
)
select
  projection.tenant_id,
  projection.membership_id,
  '91000000-0000-4000-8000-000000000001',
  'deny',
  projection.principal_id,
  projection.principal_id
from w2d_profile_projection as projection;

set local role authenticated;
select isnt(
  (select authorization_revision from public.resolve_my_authorization()),
  (select authorization_revision from w2d_profile_projection),
  'override mutation changes membership.version in the revision'
);
select is(
  (select 'core.users.read.all_tenant' = any(permission_codes) from public.resolve_my_authorization()),
  false,
  'the fresh projection reflects the exact override DENY'
);
reset role;

create temporary table w2d_membership_projection as
select * from public.resolve_my_authorization();
grant select on w2d_membership_projection to authenticated;

update public.permission_catalog
set label_key = 'authorization.permissions.core.users.read.all_tenant.updated'
where id = '91000000-0000-4000-8000-000000000001';

set local role authenticated;
select isnt(
  (select authorization_revision from public.resolve_my_authorization()),
  (select authorization_revision from w2d_membership_projection),
  'catalog revision changes invalidate the projection'
);
reset role;

update public.tenant_entitlements
set enabled = false
where tenant_id = (select tenant_id from w2d_bootstrap)
  and module_key = 'maintenance';

set local role authenticated;
select is(
  (select enabled_entitlements from public.resolve_my_authorization()),
  array[]::text[],
  'entitlement changes are visible on refresh without a JWT change'
);
reset role;

update public.tenant_memberships
set status = 'blocked', blocked_at = statement_timestamp()
where user_id = '18000000-0000-4000-8000-000000000001';

set local role authenticated;
select is(
  (select projection_status from public.resolve_my_authorization()),
  'membership_unavailable',
  'blocked membership fails closed immediately'
);
select is(
  (select tenant_id from public.resolve_my_authorization()),
  null::uuid,
  'unavailable lifecycle state omits tenant internals'
);
select is(
  (select permission_codes from public.resolve_my_authorization()),
  array[]::text[],
  'unavailable lifecycle state clears capabilities'
);
reset role;

select is(
  (
    select count(*)
    from pg_catalog.pg_proc as procedure
    cross join pg_catalog.unnest(
      coalesce(procedure.proargnames, array[]::text[])
    ) as argument(name)
    where procedure.oid = 'public.resolve_my_authorization()'::regprocedure
      and argument.name in (
        'token_hash', 'recipient_email_hash', 'audit', 'override_effect',
        'created_by', 'updated_by'
      )
  ),
  0::bigint,
  'the projection contract omits secrets, audit and authorization internals'
);

select * from finish();
rollback;
