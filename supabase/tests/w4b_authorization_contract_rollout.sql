begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

create temporary table w4b_expected_permissions (
  code text primary key,
  resource_code text not null,
  action_code text not null,
  scope public.authorization_scope not null
);

insert into w4b_expected_permissions (code, resource_code, action_code, scope)
values
  ('shared.teams.read.team','teams','read','TEAM'),
  ('shared.teams.read.all_tenant','teams','read','ALL_TENANT'),
  ('shared.teams.lookup.team','teams','lookup','TEAM'),
  ('shared.teams.lookup.all_tenant','teams','lookup','ALL_TENANT'),
  ('shared.teams.create.all_tenant','teams','create','ALL_TENANT'),
  ('shared.teams.update.all_tenant','teams','update','ALL_TENANT'),
  ('shared.teams.inactivate.all_tenant','teams','inactivate','ALL_TENANT'),
  ('shared.teams.reactivate.all_tenant','teams','reactivate','ALL_TENANT'),
  ('shared.team_memberships.read.all_tenant','team_memberships','read','ALL_TENANT'),
  ('shared.team_memberships.add.all_tenant','team_memberships','add','ALL_TENANT'),
  ('shared.team_memberships.end.all_tenant','team_memberships','end','ALL_TENANT');

create temporary table w4b_expected_template_permissions (
  template_key text not null,
  permission_code text not null,
  primary key (template_key, permission_code)
);

insert into w4b_expected_template_permissions (template_key, permission_code)
values
  ('manager','shared.teams.read.team'),
  ('manager','shared.teams.read.all_tenant'),
  ('manager','shared.teams.lookup.team'),
  ('manager','shared.teams.lookup.all_tenant'),
  ('manager','shared.teams.create.all_tenant'),
  ('manager','shared.teams.update.all_tenant'),
  ('manager','shared.teams.inactivate.all_tenant'),
  ('manager','shared.team_memberships.read.all_tenant'),
  ('manager','shared.team_memberships.add.all_tenant'),
  ('manager','shared.team_memberships.end.all_tenant'),
  ('technician','shared.teams.read.team'),
  ('technician','shared.teams.lookup.team'),
  ('assistant','shared.teams.read.team'),
  ('assistant','shared.teams.lookup.team'),
  ('requester','shared.teams.lookup.team');

select is(
  (select count(*) from public.permission_catalog where resource_code in ('teams','team_memberships')),
  11::bigint,
  'W4B.1 publishes exactly eleven Teams authorization permissions'
);
select is(
  (
    select count(*) from (
      select code, resource_code, action_code, scope
      from public.permission_catalog
      where resource_code in ('teams','team_memberships')
      except
      select code, resource_code, action_code, scope
      from w4b_expected_permissions
    ) as unexpected
  ),
  0::bigint,
  'the W4B.1 permission catalog contains no unknown combination'
);
select is(
  (
    select count(*) from (
      select code, resource_code, action_code, scope
      from w4b_expected_permissions
      except
      select code, resource_code, action_code, scope
      from public.permission_catalog
      where resource_code in ('teams','team_memberships')
    ) as missing
  ),
  0::bigint,
  'every approved W4B.1 permission combination exists'
);
select is(
  (select count(*) from public.permission_catalog where code = 'shared.teams.use.all_tenant'),
  0::bigint,
  'the superseded generic teams.use permission does not exist'
);
select is(
  (
    select count(*)
    from public.permission_catalog
    where resource_code in ('teams','team_memberships')
      and (scope in ('OWN','ASSIGNED') or action_code = 'manage' or code like '%*%')
  ),
  0::bigint,
  'W4B.1 adds no OWN, ASSIGNED, manage or wildcard permission'
);

select is(
  (
    select count(*)
    from private.authorization_profile_templates
    where template_key in ('manager','technician','assistant','requester')
      and template_version = 4
      and status = 'active'
  ),
  4::bigint,
  'the W4B.1 grants remain attached after W4C.1 advances all official templates to version four'
);
select is(
  (
    select count(*) from (
      select template.template_key, permission.code
      from private.authorization_profile_template_permissions as mapping
      join private.authorization_profile_templates as template on template.id = mapping.template_id
      join public.permission_catalog as permission on permission.id = mapping.permission_id
      where template.template_key in ('manager','technician','assistant','requester')
        and permission.resource_code in ('teams','team_memberships')
      except
      select template_key, permission_code from w4b_expected_template_permissions
    ) as unexpected
  ),
  0::bigint,
  'official templates contain no W4B.1 grant outside the frozen matrix'
);
select is(
  (
    select count(*) from (
      select template_key, permission_code from w4b_expected_template_permissions
      except
      select template.template_key, permission.code
      from private.authorization_profile_template_permissions as mapping
      join private.authorization_profile_templates as template on template.id = mapping.template_id
      join public.permission_catalog as permission on permission.id = mapping.permission_id
      where permission.resource_code in ('teams','team_memberships')
    ) as missing
  ),
  0::bigint,
  'official templates contain every frozen W4B.1 baseline grant'
);
select is(
  (
    select array_agg(grant_count order by template_key)
    from (
      select template.template_key, count(*)::integer as grant_count
      from private.authorization_profile_template_permissions as mapping
      join private.authorization_profile_templates as template on template.id = mapping.template_id
      join public.permission_catalog as permission on permission.id = mapping.permission_id
      where template.template_key in ('assistant','manager','requester','technician')
        and permission.resource_code in ('teams','team_memberships')
      group by template.template_key
    ) as counts
  ),
  array[2,10,1,2]::integer[],
  'Assistant, Manager, Requester and Technician receive exactly 2, 10, 1 and 2 grants'
);
select is(
  (
    select count(*)
    from private.authorization_profile_template_permissions as mapping
    join private.authorization_profile_templates as template on template.id = mapping.template_id
    join public.permission_catalog as permission on permission.id = mapping.permission_id
    where template.template_key = 'manager'
      and permission.code in (
        'shared.teams.read.team',
        'shared.teams.read.all_tenant',
        'shared.teams.lookup.team',
        'shared.teams.lookup.all_tenant'
      )
  ),
  4::bigint,
  'Manager explicitly receives both exact scopes for read and lookup'
);
select is(
  (
    select count(distinct (permission.action_code, permission.scope))
    from private.authorization_profile_template_permissions as mapping
    join private.authorization_profile_templates as template on template.id = mapping.template_id
    join public.permission_catalog as permission on permission.id = mapping.permission_id
    where template.template_key = 'manager'
      and permission.resource_code = 'teams'
      and permission.action_code in ('read','lookup')
  ),
  4::bigint,
  'Manager read and lookup TEAM and ALL_TENANT are four independent exact combinations'
);
select is(
  (
    select count(*)
    from private.authorization_profile_template_permissions as mapping
    join public.permission_catalog as permission on permission.id = mapping.permission_id
    where permission.code = 'shared.teams.reactivate.all_tenant'
  ),
  0::bigint,
  'teams.reactivate exists in the catalog but no official baseline receives it'
);

select is(
  (
    select procedure.prosecdef
    from pg_catalog.pg_proc as procedure
    where procedure.oid = 'private.apply_w4b_authorization_rollout(uuid)'::regprocedure
  ),
  true,
  'the privileged rollout has its explicitly approved SECURITY DEFINER mode'
);
select ok(
  exists (
    select 1
    from pg_catalog.pg_proc as procedure
    cross join pg_catalog.unnest(coalesce(procedure.proconfig,array[]::text[])) as setting(value)
    where procedure.oid = 'private.apply_w4b_authorization_rollout(uuid)'::regprocedure
      and pg_catalog.split_part(setting.value,'=',1) = 'search_path'
      and pg_catalog.replace(pg_catalog.split_part(setting.value,'=',2),'"','') = ''
  ),
  'the W4B.1 rollout fixes an empty search_path'
);
select is(
  (
    select owner_role.rolname
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_roles as owner_role on owner_role.oid = procedure.proowner
    where procedure.oid = 'private.apply_w4b_authorization_rollout(uuid)'::regprocedure
  ),
  'postgres',
  'the W4B.1 rollout has the controlled owner'
);
select is(
  (
    select count(*)
    from information_schema.routine_privileges
    where routine_schema = 'private'
      and routine_name = 'apply_w4b_authorization_rollout'
      and grantee in ('PUBLIC','anon','authenticated','service_role','cw_worker')
  ),
  0::bigint,
  'the W4B.1 rollout is not client-callable'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relkind in ('r','p')
      and relation.relname in ('teams','team_memberships')
  ),
  2::bigint,
  'the later W4B.2 phase adds exactly the two planned domain tables'
);
select is(
  (
    select count(*)
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and (procedure.proname like '%team%' or procedure.proname like '%membership%')
      and procedure.proname not in (
        'assign_tenant_membership_profile','change_tenant_membership_status',
        'resolve_membership_permission_ids'
      )
  ),
  12::bigint,
  'the later W4B.2 phase adds exactly the six commands and six read models'
);

insert into auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
values
  ('4b100000-0000-4000-8000-000000000001','authenticated','authenticated','w4b-manager@example.invalid',statement_timestamp(),statement_timestamp(),statement_timestamp()),
  ('4b100000-0000-4000-8000-000000000002','authenticated','authenticated','w4b-requester@example.invalid',statement_timestamp(),statement_timestamp(),statement_timestamp()),
  ('4b100000-0000-4000-8000-000000000003','authenticated','authenticated','w4b-delegation-success@example.invalid',statement_timestamp(),statement_timestamp(),statement_timestamp()),
  ('4b100000-0000-4000-8000-000000000004','authenticated','authenticated','w4b-delegation-denied@example.invalid',statement_timestamp(),statement_timestamp(),statement_timestamp());

create temporary table w4b_bootstrap as
select * from public.bootstrap_initial_tenant(
  '4b100000-0000-4000-8000-000000000001',
  'W4B Authorization Tenant',
  '4b200000-0000-4000-8000-000000000001'
);

update public.tenant_profiles
set name = 'Gestor W4B renomeado',
    updated_by = '4b100000-0000-4000-8000-000000000001'
where tenant_id = (select tenant_id from w4b_bootstrap)
  and template_key = 'manager';

insert into public.tenant_profiles (id, tenant_id, name, status, created_by, updated_by)
values (
  '4b300000-0000-4000-8000-000000000001',
  (select tenant_id from w4b_bootstrap),
  'Gestor',
  'active',
  '4b100000-0000-4000-8000-000000000001',
  '4b100000-0000-4000-8000-000000000001'
);

insert into public.tenant_memberships (
  id, tenant_id, user_id, status, joined_at, created_by,
  profile_id, profile_assigned_at, profile_assigned_by
)
select
  worker.membership_id,
  bootstrap.tenant_id,
  worker.user_id,
  'active',
  statement_timestamp(),
  '4b100000-0000-4000-8000-000000000001',
  profile.id,
  statement_timestamp(),
  '4b100000-0000-4000-8000-000000000001'
from w4b_bootstrap as bootstrap
cross join (values
  ('4b400000-0000-4000-8000-000000000002'::uuid,'4b100000-0000-4000-8000-000000000002'::uuid),
  ('4b400000-0000-4000-8000-000000000003'::uuid,'4b100000-0000-4000-8000-000000000003'::uuid),
  ('4b400000-0000-4000-8000-000000000004'::uuid,'4b100000-0000-4000-8000-000000000004'::uuid)
) as worker(membership_id, user_id)
join public.tenant_profiles as profile
  on profile.tenant_id = bootstrap.tenant_id
 and profile.template_key = 'requester';

insert into public.tenant_permission_overrides (
  id, tenant_id, membership_id, permission_id, effect, created_by, updated_by
)
select
  override.id,
  bootstrap.tenant_id,
  membership.id,
  permission.id,
  override.effect,
  '4b100000-0000-4000-8000-000000000001',
  '4b100000-0000-4000-8000-000000000001'
from w4b_bootstrap as bootstrap
join public.tenant_memberships as membership
  on membership.tenant_id = bootstrap.tenant_id
 and membership.user_id = '4b100000-0000-4000-8000-000000000001'
cross join (values
  ('4b500000-0000-4000-8000-000000000001'::uuid,'shared.teams.lookup.team','allow')
) as override(id, permission_code, effect)
join public.permission_catalog as permission on permission.code = override.permission_code;

create temporary table w4b_override_snapshot as
select id, tenant_id, membership_id, permission_id, effect, version, created_by, updated_by
from public.tenant_permission_overrides
where tenant_id = (select tenant_id from w4b_bootstrap);

-- Exercise the historical W4B.1 rollout against its own frozen template
-- version inside this transaction; W4C.1 is authoritative at rest on v4.
update private.authorization_profile_templates
set template_version = 3
where template_key in ('manager','technician','assistant','requester')
  and template_version = 4;

delete from public.tenant_profile_permissions as baseline
using public.tenant_profiles as profile, public.permission_catalog as permission
where profile.id = baseline.profile_id
  and permission.id = baseline.permission_id
  and profile.tenant_id = (select tenant_id from w4b_bootstrap)
  and profile.template_key in ('manager','technician','assistant','requester')
  and permission.resource_code in ('teams','team_memberships');

select is(
  private.apply_w4b_authorization_rollout((select tenant_id from w4b_bootstrap)),
  15,
  'the first rollout adds exactly the fifteen approved grants across official profiles'
);
select is(
  (
    select count(*)
    from private.authorization_profile_rollouts
    where rollout_key = 'w4b_team_scope_v1'
      and tenant_id = (select tenant_id from w4b_bootstrap)
  ),
  4::bigint,
  'the rollout ledger records one entry per official profile identity'
);
select is(
  (
    select sum(grants_added)::integer
    from private.authorization_profile_rollouts
    where rollout_key = 'w4b_team_scope_v1'
      and tenant_id = (select tenant_id from w4b_bootstrap)
  ),
  15,
  'the rollout ledger records the exact add-only grant count'
);
select is(
  (
    select count(*) from (
      select profile.template_key, permission.code
      from public.tenant_profile_permissions as baseline
      join public.tenant_profiles as profile on profile.id = baseline.profile_id
      join public.permission_catalog as permission on permission.id = baseline.permission_id
      where profile.tenant_id = (select tenant_id from w4b_bootstrap)
        and profile.template_key in ('manager','technician','assistant','requester')
        and permission.resource_code in ('teams','team_memberships')
      except
      select template_key, permission_code from w4b_expected_template_permissions
    ) as unexpected
  ),
  0::bigint,
  'rollout adds no W4B.1 permission outside the frozen matrix'
);
select is(
  (
    select count(*) from (
      select template_key, permission_code from w4b_expected_template_permissions
      except
      select profile.template_key, permission.code
      from public.tenant_profile_permissions as baseline
      join public.tenant_profiles as profile on profile.id = baseline.profile_id
      join public.permission_catalog as permission on permission.id = baseline.permission_id
      where profile.tenant_id = (select tenant_id from w4b_bootstrap)
        and permission.resource_code in ('teams','team_memberships')
    ) as missing
  ),
  0::bigint,
  'rollout adds every W4B.1 permission in the frozen matrix'
);
select is(
  (
    select count(*)
    from public.tenant_profile_permissions
    where profile_id = '4b300000-0000-4000-8000-000000000001'
  ),
  0::bigint,
  'a custom profile named Gestor is not treated as an official template instance'
);
select is(
  (
    select name
    from public.tenant_profiles
    where tenant_id = (select tenant_id from w4b_bootstrap)
      and template_key = 'manager'
  ),
  'Gestor W4B renomeado',
  'rollout identifies the official Manager by provenance and preserves its display name'
);
select is(
  (
    select count(*) from (
      select * from w4b_override_snapshot
      except
      select id, tenant_id, membership_id, permission_id, effect, version, created_by, updated_by
      from public.tenant_permission_overrides
      where tenant_id = (select tenant_id from w4b_bootstrap)
    ) as changed
  ),
  0::bigint,
  'rollout preserves every pre-existing exact override'
);
select is(
  private.apply_w4b_authorization_rollout((select tenant_id from w4b_bootstrap)),
  15,
  'rollout replay returns the recorded result without applying grants again'
);

update private.authorization_profile_templates
set template_version = 4
where template_key in ('manager','technician','assistant','requester')
  and template_version = 3;

select is(
  (
    select count(*)
    from public.audit_events
    where tenant_id = (select tenant_id from w4b_bootstrap)
      and event_type = 'authorization.profile.baseline_rolled_out'
      and actor_ref = 'w4b.authorization_rollout'
      and metadata->>'rollout_key' = 'w4b_team_scope_v1'
  ),
  4::bigint,
  'first rollout emits one technical Audit fact per official profile and replay emits none'
);

create temporary table w4b_delegation_refs as
select id as technician_profile_id
from public.tenant_profiles
where tenant_id = (select tenant_id from w4b_bootstrap)
  and template_key = 'technician';
grant select on w4b_delegation_refs to authenticated;

set local "request.jwt.claim.sub" = '4b100000-0000-4000-8000-000000000001';
set local role authenticated;
select lives_ok(
  format(
    'select * from public.assign_tenant_membership_profile(%L, %L, 1, %L, %L)',
    '4b400000-0000-4000-8000-000000000003',
    (select technician_profile_id from w4b_delegation_refs),
    'delegate exact W4B TEAM capabilities',
    '4b600000-0000-4000-8000-000000000001'
  ),
  'Manager can assign Technician because both exact TEAM capabilities are explicit'
);
reset role;

insert into public.tenant_permission_overrides (
  id, tenant_id, membership_id, permission_id, effect, created_by, updated_by
)
select
  '4b500000-0000-4000-8000-000000000002',
  bootstrap.tenant_id,
  membership.id,
  permission.id,
  'deny',
  '4b100000-0000-4000-8000-000000000001',
  '4b100000-0000-4000-8000-000000000001'
from w4b_bootstrap as bootstrap
join public.tenant_memberships as membership
  on membership.tenant_id = bootstrap.tenant_id
 and membership.user_id = '4b100000-0000-4000-8000-000000000001'
join public.permission_catalog as permission
  on permission.code = 'shared.teams.read.team';

set local role authenticated;
select throws_ok(
  format(
    'select * from public.assign_tenant_membership_profile(%L, %L, 1, %L, %L)',
    '4b400000-0000-4000-8000-000000000004',
    (select technician_profile_id from w4b_delegation_refs),
    'deny delegation without exact TEAM capability',
    '4b600000-0000-4000-8000-000000000002'
  ),
  '42501',
  'AUTHORIZATION_DELEGATION_DENIED',
  'delegation fails closed when exact teams.read.team is denied to Manager'
);
reset role;

set local "request.jwt.claim.sub" = '4b100000-0000-4000-8000-000000000001';
select is(
  (select array_agg(scope order by scope) from private.resolve_effective_scopes('teams','read') as scope),
  array['ALL_TENANT'::public.authorization_scope],
  'exact DENY TEAM does not subtract the independent ALL_TENANT grant'
);
select is(
  private.has_effective_permission('teams','read','TEAM'),
  false,
  'ALL_TENANT does not supply the explicitly denied TEAM combination'
);
select is(
  private.has_effective_permission('teams','read','ALL_TENANT'),
  true,
  'DENY TEAM leaves the independent ALL_TENANT combination effective'
);
select is(
  (select array_agg(scope order by scope) from private.resolve_effective_scopes('teams','lookup') as scope),
  array['TEAM','ALL_TENANT']::public.authorization_scope[],
  'exact ALLOW TEAM coexists with the independent ALL_TENANT baseline grant'
);

set local "request.jwt.claim.sub" = '4b100000-0000-4000-8000-000000000002';
select is(
  (select array_agg(scope order by scope) from private.resolve_effective_scopes('teams','lookup') as scope),
  array['TEAM'::public.authorization_scope],
  'Requester TEAM lookup does not imply ALL_TENANT'
);
select is(
  private.has_effective_permission('teams','lookup','ALL_TENANT'),
  false,
  'the W2 evaluator remains fail-closed for a scope not granted exactly'
);

select * from finish();
rollback;
