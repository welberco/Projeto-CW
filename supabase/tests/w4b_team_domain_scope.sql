begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select has_table('public', 'teams', 'W4B.2 creates teams');
select has_table('public', 'team_memberships', 'W4B.2 creates team memberships');
select is(
  (select count(*) from pg_catalog.pg_class as relation
   join pg_catalog.pg_namespace as namespace on namespace.oid = relation.relnamespace
   where namespace.nspname = 'public'
     and relation.relname in ('teams', 'team_memberships')
     and relation.relrowsecurity and relation.relforcerowsecurity),
  2::bigint,
  'both W4B.2 tables force RLS'
);
select is(
  (select count(*) from information_schema.table_privileges
   where table_schema = 'public'
     and table_name in ('teams', 'team_memberships')
     and grantee in ('PUBLIC', 'anon', 'service_role', 'cw_worker')),
  0::bigint,
  'non-client and bypass roles receive no W4B.2 table grants'
);
select is(
  (select count(*) from information_schema.table_privileges
   where table_schema = 'public' and table_name = 'team_memberships'
     and grantee = 'authenticated'),
  0::bigint,
  'the roster table is RPC-only'
);
select is(
  (select count(*) from information_schema.table_privileges
   where table_schema = 'public' and table_name = 'teams'
     and grantee = 'authenticated' and privilege_type <> 'SELECT'),
  0::bigint,
  'authenticated cannot mutate teams directly'
);
select is(
  (select count(*) from pg_catalog.pg_policies
   where schemaname = 'public' and tablename = 'teams' and cmd = 'SELECT'),
  1::bigint,
  'teams has one intentional SELECT policy'
);
select is(
  (select count(*) from pg_catalog.pg_policies
   where schemaname = 'public' and tablename = 'team_memberships'),
  0::bigint,
  'team memberships has no client policy'
);

select has_function('public', 'create_team', array['uuid','text','text','text','text','uuid','text'], 'create team command exists');
select has_function('public', 'update_team', array['uuid','bigint','uuid','text','text','text','text','uuid','text'], 'update team command exists');
select has_function('public', 'inactivate_team', array['uuid','bigint','text','uuid','text'], 'inactivate team command exists');
select has_function('public', 'reactivate_team', array['uuid','bigint','text','uuid','text'], 'reactivate team command exists');
select has_function('public', 'add_team_member', array['uuid','uuid','text','uuid','text'], 'add team member command exists');
select has_function('public', 'end_team_member', array['uuid','bigint','text','uuid','text'], 'end team member command exists');
select has_function('public', 'list_teams', array['text','text','integer','integer'], 'team administrative list exists');
select has_function('public', 'get_team', array['uuid'], 'team detail read exists');
select has_function('public', 'lookup_teams', array['text','integer'], 'team lookup exists');
select has_function('public', 'list_my_teams', array[]::text[], 'current actor team projection exists');
select has_function('public', 'list_team_members', array['uuid','text','integer','integer'], 'team roster read exists');
select has_function('public', 'list_teams_for_membership', array['uuid','text','integer','integer'], 'membership team read exists');

select is(
  (select count(*) from pg_catalog.pg_proc as procedure
   join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
   where namespace.nspname in ('public', 'private')
     and (procedure.proname like '%team%' or procedure.proname in ('protect_sector_team_dependency'))
     and not exists (
       select 1 from pg_catalog.unnest(coalesce(procedure.proconfig, array[]::text[])) as setting(value)
       where pg_catalog.split_part(setting.value, '=', 1) = 'search_path'
         and pg_catalog.replace(pg_catalog.split_part(setting.value, '=', 2), '"', '') = ''
     )),
  0::bigint,
  'every W4B.2 routine fixes an empty search_path'
);
select is(
  (select count(*) from information_schema.routine_privileges
   where routine_schema = 'private'
     and routine_name in (
       'team_reaches', 'can_access_team', 'assert_w4b_all_tenant_access',
       'execute_team_command', 'execute_team_membership_command',
       'protect_team_mutation', 'enforce_team_integrity',
       'protect_team_membership_mutation', 'enforce_team_membership_integrity',
       'bump_tenant_membership_revision_for_team', 'protect_sector_team_dependency'
     )
     and grantee in ('PUBLIC','anon','authenticated','service_role','cw_worker')),
  0::bigint,
  'all private W4B.2 helpers are closed'
);

insert into auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
values
  ('4b200000-0000-4000-8000-000000000001','authenticated','authenticated','w4b2-manager-a@example.invalid',statement_timestamp(),statement_timestamp(),statement_timestamp()),
  ('4b200000-0000-4000-8000-000000000002','authenticated','authenticated','w4b2-tech-a@example.invalid',statement_timestamp(),statement_timestamp(),statement_timestamp()),
  ('4b200000-0000-4000-8000-000000000003','authenticated','authenticated','w4b2-requester-a@example.invalid',statement_timestamp(),statement_timestamp(),statement_timestamp()),
  ('4b200000-0000-4000-8000-000000000004','authenticated','authenticated','w4b2-manager-b@example.invalid',statement_timestamp(),statement_timestamp(),statement_timestamp());

create temporary table w4b2_tenant_a as
select * from public.bootstrap_initial_tenant(
  '4b200000-0000-4000-8000-000000000001',
  'W4B.2 Tenant A',
  '4b210000-0000-4000-8000-000000000001'
);

insert into public.tenant_memberships (
  id, tenant_id, user_id, status, joined_at, created_by,
  profile_id, profile_assigned_at, profile_assigned_by
)
select fixture.membership_id, tenant.tenant_id, fixture.user_id, 'active',
       pg_catalog.statement_timestamp(), '4b200000-0000-4000-8000-000000000001',
       profile.id, pg_catalog.statement_timestamp(),
       '4b200000-0000-4000-8000-000000000001'
from w4b2_tenant_a as tenant
cross join (values
  ('4b220000-0000-4000-8000-000000000002'::uuid,'4b200000-0000-4000-8000-000000000002'::uuid,'technician'::text),
  ('4b220000-0000-4000-8000-000000000003'::uuid,'4b200000-0000-4000-8000-000000000003'::uuid,'requester'::text)
) as fixture(membership_id, user_id, template_key)
join public.tenant_profiles as profile
  on profile.tenant_id = tenant.tenant_id
 and profile.template_key = fixture.template_key
 and profile.status = 'active';

insert into public.tenants (id, tenant_ref, display_name, status, created_by)
values (
  '4b230000-0000-4000-8000-000000000002',
  '4b240000-0000-4000-8000-000000000002',
  'W4B.2 Tenant B', 'active', '4b200000-0000-4000-8000-000000000004'
);
do $$
declare manager_profile_id uuid;
begin
  perform * from private.provision_tenant_authorization(
    '4b230000-0000-4000-8000-000000000002', null,
    '4b200000-0000-4000-8000-000000000004',
    '4b210000-0000-4000-8000-000000000002'
  );
  select profile.id into strict manager_profile_id
  from public.tenant_profiles as profile
  join private.authorization_profile_templates as template
    on template.template_key = profile.template_key
   and template.template_version = profile.template_version
   and template.status = 'active'
  where profile.tenant_id = '4b230000-0000-4000-8000-000000000002'
    and template.template_key = 'manager' and profile.status = 'active';
  insert into public.tenant_memberships (
    id, tenant_id, user_id, status, joined_at, created_by,
    profile_id, profile_assigned_at, profile_assigned_by
  ) values (
    '4b220000-0000-4000-8000-000000000004',
    '4b230000-0000-4000-8000-000000000002',
    '4b200000-0000-4000-8000-000000000004', 'active',
    pg_catalog.statement_timestamp(), '4b200000-0000-4000-8000-000000000004',
    manager_profile_id, pg_catalog.statement_timestamp(),
    '4b200000-0000-4000-8000-000000000004'
  );
end;
$$;

insert into public.sectors (
  id, tenant_id, code, name, status, created_by, updated_by
) values (
  '4b260000-0000-4000-8000-000000000002',
  '4b230000-0000-4000-8000-000000000002',
  'TENANT-B', 'Tenant B Sector', 'active',
  '4b200000-0000-4000-8000-000000000004',
  '4b200000-0000-4000-8000-000000000004'
);

-- Reactivation remains absent from baselines and is granted explicitly for lifecycle tests.
insert into public.tenant_permission_overrides (
  tenant_id, membership_id, permission_id, effect, created_by, updated_by
)
select tenant.tenant_id, tenant.membership_id, permission.id, 'allow',
       tenant.user_id, tenant.user_id
from (
  select bootstrap.tenant_id, membership.id as membership_id,
         membership.user_id
  from w4b2_tenant_a as bootstrap
  join public.tenant_memberships as membership
    on membership.tenant_id = bootstrap.tenant_id
   and membership.user_id = '4b200000-0000-4000-8000-000000000001'
) as tenant
join public.permission_catalog as permission
  on permission.code in (
    'shared.teams.reactivate.all_tenant',
    'shared.sectors.reactivate.all_tenant'
  );

create temporary table w4b2_results(kind text primary key, result jsonb not null);
grant select, insert, update on table w4b2_results to authenticated;
grant select on table w4b2_tenant_a to authenticated;

set local "request.jwt.claim.sub" = '4b200000-0000-4000-8000-000000000001';
set local role authenticated;
insert into w4b2_results values (
  'sector',
  public.create_sector(
    'W4B2-OPS', 'Operations', 'Sector for team tests', 'create team parent',
    '4b250000-0000-4000-8000-000000000001', 'w4b2-sector-create-0001'
  )
);
insert into w4b2_results values (
  'team',
  public.create_team(
    (select (result->>'id')::uuid from w4b2_results where kind = 'sector'),
    'TEAM-OPS', 'Operations Team', 'Primary operational team', 'create team',
    '4b250000-0000-4000-8000-000000000002', 'w4b2-team-create-0001'
  )
);
reset role;

select is(
  (select pg_catalog.array_agg(keys.key order by keys.key)
   from pg_catalog.jsonb_object_keys(
     (select result from w4b2_results where kind = 'team')
   ) as keys(key)),
  array['command_correlation_id','id','status','version']::text[],
  'team command result has the strict W4 result contract'
);
select is(
  (select count(*) from public.teams
   where id = (select (result->>'id')::uuid from w4b2_results where kind = 'team')
     and tenant_id = (select tenant_id from w4b2_tenant_a)
     and sector_id = (select (result->>'id')::uuid from w4b2_results where kind = 'sector')),
  1::bigint,
  'created team and sector are tenant-consistent'
);
select is(
  (select count(*)
   from pg_catalog.pg_proc as procedure
   join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
   cross join lateral pg_catalog.unnest(coalesce(procedure.proargnames, array[]::text[])) as argument(name)
   where namespace.nspname = 'public'
     and procedure.proname in (
       'create_team','update_team','inactivate_team','reactivate_team',
       'add_team_member','end_team_member'
     )
     and argument.name in (
       'tenant_id','actor_id','actor_user_id','profile_id','permission_id','scope'
     )),
  0::bigint,
  'public commands accept no tenant actor profile permission or scope authority payload'
);

set local "request.jwt.claim.sub" = '4b200000-0000-4000-8000-000000000001';
set local role authenticated;
select is(
  (select count(*) from public.get_team('4b270000-0000-4000-8000-000000000099')),
  0::bigint,
  'guessed unknown Team UUID is indistinguishable from unavailable'
);
select throws_ok(
  $$insert into public.teams(tenant_id,name,created_by,updated_by)
    values('4b230000-0000-4000-8000-000000000002','Forged tenant team',
      '4b200000-0000-4000-8000-000000000001','4b200000-0000-4000-8000-000000000001')$$,
  '42501', 'permission denied for table teams',
  'direct INSERT cannot forge tenant authority'
);
select throws_ok(
  format('update public.teams set name=%L where id=%L::uuid', 'Direct update',
    (select result->>'id' from w4b2_results where kind = 'team')),
  '42501', 'permission denied for table teams',
  'direct Team UPDATE is denied'
);
select throws_ok(
  format('delete from public.teams where id=%L::uuid',
    (select result->>'id' from w4b2_results where kind = 'team')),
  '42501', 'permission denied for table teams',
  'direct Team DELETE is denied'
);
select throws_ok(
  format(
    'select public.create_team(%L::uuid,%L,%L,null,%L,%L::uuid,%L)',
    '4b270000-0000-4000-8000-000000000098', 'MISSING-SECTOR',
    'Missing sector team', 'invalid parent',
    '4b250000-0000-4000-8000-000000000101', 'w4b2-missing-sector-0001'
  ),
  'P0001', 'TEAM_SECTOR_UNAVAILABLE',
  'unknown Sector fails closed'
);
select throws_ok(
  format(
    'select public.create_team(%L::uuid,%L,%L,null,%L,%L::uuid,%L)',
    '4b260000-0000-4000-8000-000000000002', 'CROSS-SECTOR',
    'Cross tenant sector team', 'invalid parent tenant',
    '4b250000-0000-4000-8000-000000000102', 'w4b2-cross-sector-0001'
  ),
  'P0001', 'TEAM_SECTOR_UNAVAILABLE',
  'cross-tenant Sector fails closed'
);
select throws_ok(
  format(
    'select public.add_team_member(%L::uuid,%L::uuid,%L,%L::uuid,%L)',
    (select result->>'id' from w4b2_results where kind = 'team'),
    '4b220000-0000-4000-8000-000000000004', 'cross tenant target',
    '4b250000-0000-4000-8000-000000000103', 'w4b2-cross-membership-0001'
  ),
  'P0001', 'TEAM_MEMBER_TARGET_UNAVAILABLE',
  'cross-tenant membership cannot be added'
);
reset role;

set local "request.jwt.claim.sub" = '4b200000-0000-4000-8000-000000000002';
set local role authenticated;
select is((select count(*) from public.list_teams()), 0::bigint, 'TEAM read grants no reach before association');
select is((select count(*) from public.lookup_teams()), 0::bigint, 'TEAM lookup grants no reach before association');
reset role;

insert into public.tenant_permission_overrides (
  id, tenant_id, membership_id, permission_id, effect, created_by, updated_by
)
select '4b280000-0000-4000-8000-000000000002', tenant.tenant_id,
       membership.id, permission.id, 'deny',
       '4b200000-0000-4000-8000-000000000001',
       '4b200000-0000-4000-8000-000000000001'
from w4b2_tenant_a as tenant
join public.tenant_memberships as membership
  on membership.tenant_id = tenant.tenant_id
 and membership.user_id = '4b200000-0000-4000-8000-000000000001'
join public.permission_catalog as permission
  on permission.code = 'shared.teams.read.team';
set local "request.jwt.claim.sub" = '4b200000-0000-4000-8000-000000000001';
set local role authenticated;
select is(
  (select count(*) from public.list_teams()),
  1::bigint,
  'DENY TEAM does not subtract the independent ALL_TENANT read capability'
);
reset role;
delete from public.tenant_permission_overrides
where id = '4b280000-0000-4000-8000-000000000002';

set local "request.jwt.claim.sub" = '4b200000-0000-4000-8000-000000000001';
set local role authenticated;
insert into w4b2_results values (
  'tech-association',
  public.add_team_member(
    (select (result->>'id')::uuid from w4b2_results where kind = 'team'),
    '4b220000-0000-4000-8000-000000000002', 'add technician',
    '4b250000-0000-4000-8000-000000000003', 'w4b2-add-tech-0001'
  )
);
insert into w4b2_results values (
  'requester-association',
  public.add_team_member(
    (select (result->>'id')::uuid from w4b2_results where kind = 'team'),
    '4b220000-0000-4000-8000-000000000003', 'add requester',
    '4b250000-0000-4000-8000-000000000004', 'w4b2-add-requester-0001'
  )
);
select is(
  (select count(*) from public.list_team_members(
    (select (result->>'id')::uuid from w4b2_results where kind = 'team'), 'active'
  )),
  2::bigint,
  'roster permission exposes both active associations to Manager'
);
reset role;

select ok(
  (select version > 1 from public.tenant_memberships
   where id = '4b220000-0000-4000-8000-000000000002'),
  'adding a team member atomically bumps the target authorization revision'
);
select is(
  (select count(*) from public.team_memberships
   where tenant_id = (select tenant_id from w4b2_tenant_a)
     and team_id = (select (result->>'id')::uuid from w4b2_results where kind = 'team')
     and membership_id = '4b220000-0000-4000-8000-000000000002'
     and status = 'active'),
  1::bigint,
  'the active pair uniqueness invariant holds'
);

set local "request.jwt.claim.sub" = '4b200000-0000-4000-8000-000000000002';
set local role authenticated;
select is((select count(*) from public.list_teams()), 1::bigint, 'TEAM read reaches exactly the assigned active team');
select is((select count(*) from public.lookup_teams()), 1::bigint, 'TEAM lookup reaches exactly the assigned active team');
select is((select count(*) from public.list_my_teams()), 1::bigint, 'list_my_teams derives the actor membership server-side');
select throws_ok(
  format(
    'select public.update_team(%L::uuid,1,null,%L,%L,null,%L,%L::uuid,%L)',
    (select result->>'id' from w4b2_results where kind = 'team'),
    'TEAM-OPS', 'Unauthorized mutation', 'read must not mutate',
    '4b250000-0000-4000-8000-000000000107', 'w4b2-read-mutation-0001'
  ),
  '42501', 'AUTHORIZATION_DENIED',
  'TEAM read never grants Team mutation'
);
select throws_ok(
  format('select * from public.list_team_members(%L::uuid)',
    (select result->>'id' from w4b2_results where kind = 'team')),
  '42501', 'AUTHORIZATION_DENIED',
  'teams.read.team never grants roster access'
);
select throws_ok(
  'select count(*) from public.team_memberships',
  '42501', 'permission denied for table team_memberships',
  'team roster cannot be bypassed by direct select'
);
reset role;

insert into public.tenant_permission_overrides (
  id, tenant_id, membership_id, permission_id, effect, created_by, updated_by
)
select '4b280000-0000-4000-8000-000000000004', tenant.tenant_id,
       '4b220000-0000-4000-8000-000000000002', permission.id, 'allow',
       '4b200000-0000-4000-8000-000000000001',
       '4b200000-0000-4000-8000-000000000001'
from w4b2_tenant_a as tenant
join public.permission_catalog as permission
  on permission.code = 'shared.teams.read.all_tenant';
set local "request.jwt.claim.sub" = '4b200000-0000-4000-8000-000000000002';
set local role authenticated;
select is((select count(*) from public.list_teams()), 1::bigint, 'ALL_TENANT read is independently effective');
select throws_ok(
  format('select * from public.list_team_members(%L::uuid)',
    (select result->>'id' from w4b2_results where kind = 'team')),
  '42501', 'AUTHORIZATION_DENIED',
  'teams.read.all_tenant alone does not disclose roster data'
);
reset role;
delete from public.tenant_permission_overrides
where id = '4b280000-0000-4000-8000-000000000004';

insert into public.tenant_permission_overrides (
  id, tenant_id, membership_id, permission_id, effect, created_by, updated_by
)
select '4b280000-0000-4000-8000-000000000003', tenant.tenant_id,
       '4b220000-0000-4000-8000-000000000002', permission.id, 'deny',
       '4b200000-0000-4000-8000-000000000001',
       '4b200000-0000-4000-8000-000000000001'
from w4b2_tenant_a as tenant
join public.permission_catalog as permission
  on permission.code = 'shared.teams.read.team';
set local "request.jwt.claim.sub" = '4b200000-0000-4000-8000-000000000002';
set local role authenticated;
select is((select count(*) from public.list_teams()), 0::bigint, 'exact DENY TEAM removes an otherwise reachable Team');
select is((select count(*) from public.lookup_teams()), 1::bigint, 'DENY read TEAM does not subtract independent lookup TEAM');
reset role;
delete from public.tenant_permission_overrides
where id = '4b280000-0000-4000-8000-000000000003';

update public.tenant_memberships
set status = 'blocked', blocked_at = pg_catalog.statement_timestamp()
where id = '4b220000-0000-4000-8000-000000000002';
set local "request.jwt.claim.sub" = '4b200000-0000-4000-8000-000000000002';
set local role authenticated;
select is((select count(*) from public.list_teams()), 0::bigint, 'a blocked membership invalidates previously reachable TEAM state');
reset role;
set local "request.jwt.claim.sub" = '4b200000-0000-4000-8000-000000000001';
set local role authenticated;
select throws_ok(
  format(
    'select public.add_team_member(%L::uuid,%L::uuid,%L,%L::uuid,%L)',
    (select result->>'id' from w4b2_results where kind = 'team'),
    '4b220000-0000-4000-8000-000000000002', 'blocked target',
    '4b250000-0000-4000-8000-000000000110', 'w4b2-blocked-target-0001'
  ),
  'P0001', 'TEAM_MEMBER_TARGET_UNAVAILABLE',
  'blocked tenant membership cannot be added to a Team'
);
reset role;
update public.tenant_memberships
set status = 'active', blocked_at = null
where id = '4b220000-0000-4000-8000-000000000002';

update public.tenant_memberships
set status = 'revoked', revoked_at = pg_catalog.statement_timestamp()
where id = '4b220000-0000-4000-8000-000000000002';
set local "request.jwt.claim.sub" = '4b200000-0000-4000-8000-000000000001';
set local role authenticated;
select throws_ok(
  format(
    'select public.add_team_member(%L::uuid,%L::uuid,%L,%L::uuid,%L)',
    (select result->>'id' from w4b2_results where kind = 'team'),
    '4b220000-0000-4000-8000-000000000002', 'revoked target',
    '4b250000-0000-4000-8000-000000000111', 'w4b2-revoked-target-0001'
  ),
  'P0001', 'TEAM_MEMBER_TARGET_UNAVAILABLE',
  'revoked tenant membership cannot be added to a Team'
);
reset role;
update public.tenant_memberships
set status = 'active', revoked_at = null
where id = '4b220000-0000-4000-8000-000000000002';

update public.app_users
set status = 'blocked', blocked_at = pg_catalog.statement_timestamp()
where id = '4b200000-0000-4000-8000-000000000002';
set local "request.jwt.claim.sub" = '4b200000-0000-4000-8000-000000000002';
set local role authenticated;
select is((select count(*) from public.list_teams()), 0::bigint, 'a blocked app user invalidates previously reachable TEAM state');
reset role;
update public.app_users
set status = 'active', blocked_at = null
where id = '4b200000-0000-4000-8000-000000000002';

update public.app_users
set status = 'inactive', inactivated_at = pg_catalog.statement_timestamp()
where id = '4b200000-0000-4000-8000-000000000002';
set local "request.jwt.claim.sub" = '4b200000-0000-4000-8000-000000000002';
set local role authenticated;
select is((select count(*) from public.list_teams()), 0::bigint, 'inactive app user invalidates previously reachable TEAM state');
reset role;
update public.app_users
set status = 'active', inactivated_at = null
where id = '4b200000-0000-4000-8000-000000000002';

update public.tenants
set status = 'inactive', inactivated_at = pg_catalog.statement_timestamp()
where id = (select tenant_id from w4b2_tenant_a);
set local "request.jwt.claim.sub" = '4b200000-0000-4000-8000-000000000002';
set local role authenticated;
select is((select count(*) from public.list_teams()), 0::bigint, 'an inactive tenant invalidates previously reachable TEAM state');
reset role;
update public.tenants
set status = 'active', inactivated_at = null
where id = (select tenant_id from w4b2_tenant_a);

set local "request.jwt.claim.sub" = '4b200000-0000-4000-8000-000000000001';
set local role authenticated;
insert into w4b2_results values (
  'aux-team',
  public.create_team(
    null, 'TEAM-AUX', 'Auxiliary Team', null, 'prove multiple teams',
    '4b250000-0000-4000-8000-000000000104', 'w4b2-aux-team-0001'
  )
);
insert into w4b2_results values (
  'aux-tech-association',
  public.add_team_member(
    (select (result->>'id')::uuid from w4b2_results where kind = 'aux-team'),
    '4b220000-0000-4000-8000-000000000002', 'second simultaneous team',
    '4b250000-0000-4000-8000-000000000105', 'w4b2-aux-add-0001'
  )
);
reset role;
select is(
  (select count(*) from public.team_memberships
   where membership_id = '4b220000-0000-4000-8000-000000000002'
     and status = 'active'),
  2::bigint,
  'one tenant membership may participate in multiple Teams simultaneously'
);
set local "request.jwt.claim.sub" = '4b200000-0000-4000-8000-000000000001';
set local role authenticated;
insert into w4b2_results values (
  'aux-tech-ended',
  public.end_team_member(
    (select (result->>'id')::uuid from w4b2_results where kind = 'aux-tech-association'),
    1, 'close auxiliary proof',
    '4b250000-0000-4000-8000-000000000106', 'w4b2-aux-end-0001'
  )
);
reset role;

set local "request.jwt.claim.sub" = '4b200000-0000-4000-8000-000000000003';
set local role authenticated;
select is((select count(*) from public.list_teams()), 0::bigint, 'lookup TEAM does not imply read TEAM');
select is((select count(*) from public.lookup_teams()), 1::bigint, 'Requester lookup reaches its assigned team');
select is((select count(*) from public.list_my_teams()), 1::bigint, 'Requester current-team projection uses exact lookup TEAM');
reset role;

set local "request.jwt.claim.sub" = '4b200000-0000-4000-8000-000000000004';
set local role authenticated;
select is(
  (select count(*) from public.get_team(
    (select (result->>'id')::uuid from w4b2_results where kind = 'team')
  )),
  0::bigint,
  'cross-tenant detail access fails closed without leaking existence'
);
reset role;

set local "request.jwt.claim.sub" = '4b200000-0000-4000-8000-000000000001';
set local role authenticated;
select throws_ok(
  format(
    'select public.inactivate_team(%L::uuid,1,%L,%L::uuid,%L)',
    (select result->>'id' from w4b2_results where kind = 'team'),
    'blocked by active roster', '4b250000-0000-4000-8000-000000000005',
    'w4b2-team-inactivate-blocked-0001'
  ),
  '23514', 'ACTIVE_TEAM_MEMBERSHIP_DEPENDENCY',
  'active team membership blocks team inactivation'
);
select throws_ok(
  format(
    'select public.inactivate_sector(%L::uuid,1,%L,%L::uuid,%L)',
    (select result->>'id' from w4b2_results where kind = 'sector'),
    'blocked by active team', '4b250000-0000-4000-8000-000000000006',
    'w4b2-sector-inactivate-blocked-0001'
  ),
  '23514', 'ACTIVE_TEAM_SECTOR_DEPENDENCY',
  'active team blocks sector inactivation'
);
insert into w4b2_results values (
  'tech-ended',
  public.end_team_member(
    (select (result->>'id')::uuid from w4b2_results where kind = 'tech-association'),
    1, 'end technician participation',
    '4b250000-0000-4000-8000-000000000007', 'w4b2-end-tech-0001'
  )
);
reset role;
set local "request.jwt.claim.sub" = '4b200000-0000-4000-8000-000000000002';
set local role authenticated;
select is((select count(*) from public.list_teams()), 0::bigint, 'ended membership immediately removes TEAM read reach');
select is((select count(*) from public.list_my_teams()), 0::bigint, 'ended membership immediately removes self Team projection');
reset role;
set local "request.jwt.claim.sub" = '4b200000-0000-4000-8000-000000000001';
set local role authenticated;
insert into w4b2_results values (
  'requester-ended',
  public.end_team_member(
    (select (result->>'id')::uuid from w4b2_results where kind = 'requester-association'),
    1, 'end requester participation',
    '4b250000-0000-4000-8000-000000000008', 'w4b2-end-requester-0001'
  )
);
insert into w4b2_results values (
  'team-inactive',
  public.inactivate_team(
    (select (result->>'id')::uuid from w4b2_results where kind = 'team'),
    1, 'inactivate empty team',
    '4b250000-0000-4000-8000-000000000009', 'w4b2-team-inactivate-0001'
  )
);
select throws_ok(
  format(
    'select public.add_team_member(%L::uuid,%L::uuid,%L,%L::uuid,%L)',
    (select result->>'id' from w4b2_results where kind = 'team'),
    '4b220000-0000-4000-8000-000000000002', 'inactive Team target',
    '4b250000-0000-4000-8000-000000000108', 'w4b2-inactive-team-add-0001'
  ),
  'P0001', 'TEAM_UNAVAILABLE',
  'inactive Team rejects new membership'
);
insert into w4b2_results values (
  'sector-inactive',
  public.inactivate_sector(
    (select (result->>'id')::uuid from w4b2_results where kind = 'sector'),
    1, 'inactivate unused sector',
    '4b250000-0000-4000-8000-000000000010', 'w4b2-sector-inactivate-0001'
  )
);
select throws_ok(
  format(
    'select public.create_team(%L::uuid,%L,%L,null,%L,%L::uuid,%L)',
    (select result->>'id' from w4b2_results where kind = 'sector'),
    'INACTIVE-SECTOR', 'Inactive sector team', 'inactive parent',
    '4b250000-0000-4000-8000-000000000109', 'w4b2-inactive-sector-create-0001'
  ),
  'P0001', 'TEAM_SECTOR_UNAVAILABLE',
  'inactive Sector rejects Team creation'
);
select throws_ok(
  format(
    'select public.reactivate_team(%L::uuid,2,%L,%L::uuid,%L)',
    (select result->>'id' from w4b2_results where kind = 'team'),
    'sector still inactive', '4b250000-0000-4000-8000-000000000011',
    'w4b2-team-reactivate-blocked-0001'
  ),
  'P0001', 'TEAM_SECTOR_UNAVAILABLE',
  'team reactivation requires an active sector'
);
insert into w4b2_results values (
  'sector-active',
  public.reactivate_sector(
    (select (result->>'id')::uuid from w4b2_results where kind = 'sector'),
    2, 'reactivate parent sector',
    '4b250000-0000-4000-8000-000000000012', 'w4b2-sector-reactivate-0001'
  )
);
insert into w4b2_results values (
  'team-active',
  public.reactivate_team(
    (select (result->>'id')::uuid from w4b2_results where kind = 'team'),
    2, 'reactivate team',
    '4b250000-0000-4000-8000-000000000013', 'w4b2-team-reactivate-0001'
  )
);
insert into w4b2_results values (
  'requester-returned',
  public.add_team_member(
    (select (result->>'id')::uuid from w4b2_results where kind = 'team'),
    '4b220000-0000-4000-8000-000000000003', 'requester returns',
    '4b250000-0000-4000-8000-000000000014', 'w4b2-add-requester-return-0001'
  )
);
select is(
  public.add_team_member(
    (select (result->>'id')::uuid from w4b2_results where kind = 'team'),
    '4b220000-0000-4000-8000-000000000003', 'requester returns',
    '4b250000-0000-4000-8000-000000000099', 'w4b2-add-requester-return-0001'
  ),
  (select result from w4b2_results where kind = 'requester-returned'),
  'same semantic command and idempotency key replay the stored result'
);
reset role;

select isnt(
  (select result->>'id' from w4b2_results where kind = 'requester-returned'),
  (select result->>'id' from w4b2_results where kind = 'requester-association'),
  'returning to a team creates a new association row'
);
select is(
  (select count(*) from public.team_memberships
   where membership_id = '4b220000-0000-4000-8000-000000000003'),
  2::bigint,
  'ended history is preserved beside the new active association'
);
select throws_ok(
  format(
    'update public.team_memberships set ended_at=statement_timestamp() where id=%L::uuid',
    (select result->>'id' from w4b2_results where kind = 'requester-association')
  ),
  '23514', 'ENDED_TEAM_MEMBERSHIP_IMMUTABLE',
  'ended team membership rows are immutable'
);
select throws_ok(
  format(
    'delete from public.teams where id=%L::uuid',
    (select result->>'id' from w4b2_results where kind = 'team')
  ),
  '23514', 'TEAM_DELETE_FORBIDDEN',
  'teams cannot be physically deleted'
);

select is(
  (select count(*) from public.audit_events
   where correlation_id = '4b250000-0000-4000-8000-000000000002'),
  1::bigint,
  'team create writes exactly one audit fact'
);
select is(
  (select count(*) from public.history_entries
   where correlation_id = '4b250000-0000-4000-8000-000000000002'),
  1::bigint,
  'team create writes exactly one history fact'
);
select is(
  (select count(*) from private.outbox_events
   where correlation_id = '4b250000-0000-4000-8000-000000000002'),
  1::bigint,
  'team create enqueues exactly one event'
);
select is(
  (select pg_catalog.array_agg(keys.key order by keys.key)
   from private.outbox_events as event
   cross join lateral pg_catalog.jsonb_object_keys(event.payload) as keys(key)
   where event.correlation_id = '4b250000-0000-4000-8000-000000000002'),
  array['code','id','sector_id','status','version']::text[],
  'Team event payload is the frozen minimal allowlist'
);
select is(
  (select pg_catalog.array_agg(keys.key order by keys.key)
   from private.outbox_events as event
   cross join lateral pg_catalog.jsonb_object_keys(event.payload) as keys(key)
   where event.correlation_id = '4b250000-0000-4000-8000-000000000003'),
  array['id','membership_id','status','team_id','version']::text[],
  'Team membership event payload is the frozen minimal allowlist'
);
select is(
  (select count(*)
   from private.outbox_events as event
   where event.aggregate_type in ('team','team_membership')
     and event.payload::text ~* '(email|permission|override|secret)'),
  0::bigint,
  'W4B.2 event payloads contain no auth PII or authorization dump'
);
select is(
  (select count(*) from public.audit_events
   where correlation_id = '4b250000-0000-4000-8000-000000000014'),
  1::bigint,
  'idempotent replay does not duplicate command effects'
);

select * from finish();
rollback;
