begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select has_function('public', 'lookup_team_member_candidates',
  array['uuid','text','integer','integer'], 'candidate lookup has the frozen signature');
select is(
  pg_catalog.pg_get_function_result(
    'public.lookup_team_member_candidates(uuid,text,integer,integer)'::pg_catalog.regprocedure
  ),
  'TABLE(membership_id uuid, user_id uuid, display_name text)',
  'projection has exactly the three approved columns'
);
select ok(
  (select procedure.prosecdef and procedure.provolatile = 's'
   from pg_catalog.pg_proc as procedure
   where procedure.oid = 'public.lookup_team_member_candidates(uuid,text,integer,integer)'::pg_catalog.regprocedure),
  'candidate lookup is a stable SECURITY DEFINER read'
);
select ok(
  (select exists (
     select 1
     from pg_catalog.unnest(coalesce(procedure.proconfig, array[]::text[])) as setting(value)
     where pg_catalog.split_part(setting.value, '=', 1) = 'search_path'
       and pg_catalog.replace(pg_catalog.split_part(setting.value, '=', 2), '"', '') = ''
   )
   from pg_catalog.pg_proc as procedure
   where procedure.oid = 'public.lookup_team_member_candidates(uuid,text,integer,integer)'::pg_catalog.regprocedure),
  'candidate lookup fixes an empty search_path'
);
select ok(pg_catalog.has_function_privilege(
  'authenticated', 'public.lookup_team_member_candidates(uuid,text,integer,integer)', 'EXECUTE'
), 'authenticated may execute the constrained RPC');
select ok(not pg_catalog.has_function_privilege(
  'anon', 'public.lookup_team_member_candidates(uuid,text,integer,integer)', 'EXECUTE'
), 'anon cannot execute candidate lookup');
select ok(not pg_catalog.has_function_privilege(
  'service_role', 'public.lookup_team_member_candidates(uuid,text,integer,integer)', 'EXECUTE'
), 'service_role receives no direct candidate RPC grant');
select is(
  (select count(*) from pg_catalog.pg_policies
   where schemaname = 'public' and tablename = 'team_memberships'),
  0::bigint, 'candidate lookup did not add a direct Team membership policy'
);
select is(
  (select count(*) from information_schema.table_privileges
   where table_schema = 'public' and table_name = 'team_memberships'
     and grantee = 'authenticated'),
  0::bigint, 'candidate lookup did not grant direct roster table access'
);

insert into auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
values
  ('4d100000-0000-4000-8000-000000000001','authenticated','authenticated','w4d-manager-a@example.invalid',statement_timestamp(),statement_timestamp(),statement_timestamp()),
  ('4d100000-0000-4000-8000-000000000002','authenticated','authenticated','w4d-tech-a@example.invalid',statement_timestamp(),statement_timestamp(),statement_timestamp()),
  ('4d100000-0000-4000-8000-000000000003','authenticated','authenticated','w4d-candidate-a@example.invalid',statement_timestamp(),statement_timestamp(),statement_timestamp()),
  ('4d100000-0000-4000-8000-000000000004','authenticated','authenticated','w4d-manager-b@example.invalid',statement_timestamp(),statement_timestamp(),statement_timestamp());

create temporary table w4d_tenant_a as
select * from public.bootstrap_initial_tenant(
  '4d100000-0000-4000-8000-000000000001', 'W4D Candidate Tenant A',
  '4d110000-0000-4000-8000-000000000001'
);

update public.app_users set display_name = 'Ana % _'
where id = '4d100000-0000-4000-8000-000000000003';

insert into public.tenant_memberships (
  id, tenant_id, user_id, status, joined_at, created_by,
  profile_id, profile_assigned_at, profile_assigned_by
)
select fixture.membership_id, tenant.tenant_id, fixture.user_id, 'active',
       pg_catalog.statement_timestamp(), '4d100000-0000-4000-8000-000000000001',
       profile.id, pg_catalog.statement_timestamp(),
       '4d100000-0000-4000-8000-000000000001'
from w4d_tenant_a as tenant
cross join (values
  ('4d120000-0000-4000-8000-000000000002'::uuid,'4d100000-0000-4000-8000-000000000002'::uuid),
  ('4d120000-0000-4000-8000-000000000003'::uuid,'4d100000-0000-4000-8000-000000000003'::uuid)
) as fixture(membership_id, user_id)
join public.tenant_profiles as profile
  on profile.tenant_id = tenant.tenant_id
 and profile.template_key = 'technician' and profile.status = 'active';

insert into public.tenants (id, tenant_ref, display_name, status, created_by)
values ('4d130000-0000-4000-8000-000000000002',
        '4d140000-0000-4000-8000-000000000002',
        'W4D Candidate Tenant B', 'active',
        '4d100000-0000-4000-8000-000000000004');
update public.app_users set display_name = 'External B'
where id = '4d100000-0000-4000-8000-000000000004';
do $$
declare manager_profile_id uuid;
begin
  perform * from private.provision_tenant_authorization(
    '4d130000-0000-4000-8000-000000000002', null,
    '4d100000-0000-4000-8000-000000000004',
    '4d110000-0000-4000-8000-000000000002'
  );
  select profile.id into strict manager_profile_id
  from public.tenant_profiles as profile
  where profile.tenant_id = '4d130000-0000-4000-8000-000000000002'
    and profile.template_key = 'manager';
  insert into public.tenant_memberships (
    id, tenant_id, user_id, status, joined_at, created_by,
    profile_id, profile_assigned_at, profile_assigned_by
  ) values (
    '4d120000-0000-4000-8000-000000000004',
    '4d130000-0000-4000-8000-000000000002',
    '4d100000-0000-4000-8000-000000000004', 'active',
    pg_catalog.statement_timestamp(), '4d100000-0000-4000-8000-000000000004',
    manager_profile_id, pg_catalog.statement_timestamp(),
    '4d100000-0000-4000-8000-000000000004'
  );
end;
$$;

insert into public.teams (id, tenant_id, name, status, created_by, updated_by)
select '4d150000-0000-4000-8000-000000000001', tenant.tenant_id,
       'Active Team A', 'active',
       '4d100000-0000-4000-8000-000000000001',
       '4d100000-0000-4000-8000-000000000001'
from w4d_tenant_a as tenant;
insert into public.teams (
  id, tenant_id, name, status, inactivated_at, created_by, updated_by
)
select '4d150000-0000-4000-8000-000000000003', tenant.tenant_id,
       'Inactive Team A', 'inactive', pg_catalog.statement_timestamp(),
       '4d100000-0000-4000-8000-000000000001',
       '4d100000-0000-4000-8000-000000000001'
from w4d_tenant_a as tenant;
insert into public.teams (id, tenant_id, name, status, created_by, updated_by)
values ('4d150000-0000-4000-8000-000000000002',
        '4d130000-0000-4000-8000-000000000002', 'Active Team B', 'active',
        '4d100000-0000-4000-8000-000000000004',
        '4d100000-0000-4000-8000-000000000004');

-- Bulk fixture proves the 20/100 limits and offset pagination without client filtering.
create temporary table w4d_bulk_users as
select n, pg_catalog.gen_random_uuid() as user_id,
       pg_catalog.gen_random_uuid() as membership_id
from pg_catalog.generate_series(1, 105) as sequence(n);
insert into auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
select fixture.user_id, 'authenticated', 'authenticated',
       'w4d-bulk-' || fixture.n::text || '@example.invalid',
       pg_catalog.statement_timestamp(), pg_catalog.statement_timestamp(),
       pg_catalog.statement_timestamp()
from w4d_bulk_users as fixture;
update public.app_users as app_user
set display_name = case
  when fixture.n in (1, 2) then 'Pessoa Duplicada'
  when fixture.n = 105 then null
  when fixture.n = 104 then 'Pessoa _ literal'
  when fixture.n = 103 then 'Pessoa % literal'
  else 'Pessoa ' || pg_catalog.lpad(fixture.n::text, 3, '0')
end
from w4d_bulk_users as fixture
where app_user.id = fixture.user_id;
insert into public.tenant_memberships (
  id, tenant_id, user_id, status, joined_at, created_by,
  profile_id, profile_assigned_at, profile_assigned_by
)
select fixture.membership_id, tenant.tenant_id, fixture.user_id, 'active',
       pg_catalog.statement_timestamp(), '4d100000-0000-4000-8000-000000000001',
       profile.id, pg_catalog.statement_timestamp(),
       '4d100000-0000-4000-8000-000000000001'
from w4d_bulk_users as fixture
cross join w4d_tenant_a as tenant
join public.tenant_profiles as profile
  on profile.tenant_id = tenant.tenant_id
 and profile.template_key = 'technician' and profile.status = 'active';

update public.tenant_memberships as membership
set status = 'blocked', blocked_at = pg_catalog.statement_timestamp()
from w4d_bulk_users as fixture
where fixture.n = 100 and membership.id = fixture.membership_id;
update public.app_users as app_user
set status = 'blocked', blocked_at = pg_catalog.statement_timestamp()
from w4d_bulk_users as fixture
where fixture.n = 101 and app_user.id = fixture.user_id;

insert into public.team_memberships (
  id, tenant_id, team_id, membership_id, created_by, updated_by
)
select pg_catalog.gen_random_uuid(), tenant.tenant_id,
       '4d150000-0000-4000-8000-000000000001', fixture.membership_id,
       '4d100000-0000-4000-8000-000000000001',
       '4d100000-0000-4000-8000-000000000001'
from w4d_bulk_users as fixture cross join w4d_tenant_a as tenant
where fixture.n in (3, 4);
update public.team_memberships as association
set status = 'ended', ended_at = pg_catalog.statement_timestamp()
from w4d_bulk_users as fixture
where fixture.n = 4 and association.membership_id = fixture.membership_id;

grant select on table w4d_tenant_a, w4d_bulk_users to authenticated;

create temporary table w4d_side_effect_baseline as
select (select count(*) from public.audit_events) as audit_count,
       (select count(*) from public.history_entries) as history_count,
       (select count(*) from private.outbox_events) as outbox_count,
       (select count(*) from private.command_idempotency) as idempotency_count;

set local "request.jwt.claim.sub" = '4d100000-0000-4000-8000-000000000001';
set local role authenticated;
select is(
  (select count(*) from public.lookup_team_member_candidates(
    '4d150000-0000-4000-8000-000000000001', 'Ana', 20, 0)),
  1::bigint, 'authorized actor finds a matching candidate'
);
select is(
  (select candidate.membership_id from public.lookup_team_member_candidates(
    '4d150000-0000-4000-8000-000000000001', 'Ana', 20, 0) as candidate),
  '4d120000-0000-4000-8000-000000000003'::uuid,
  'candidate identity is the tenant membership required by add_team_member'
);
select is(
  (select count(*) from public.lookup_team_member_candidates(
    '4d150000-0000-4000-8000-000000000001', 'Pessoa 100', 20, 0) as candidate
   join w4d_bulk_users as fixture on fixture.membership_id = candidate.membership_id
   where fixture.n = 100),
  0::bigint, 'blocked tenant membership is excluded'
);
select is(
  (select count(*) from public.lookup_team_member_candidates(
    '4d150000-0000-4000-8000-000000000001', 'Pessoa 101', 20, 0) as candidate
   join w4d_bulk_users as fixture on fixture.membership_id = candidate.membership_id
   where fixture.n = 101),
  0::bigint, 'blocked app_user is excluded'
);
select is(
  (select count(*) from public.lookup_team_member_candidates(
    '4d150000-0000-4000-8000-000000000001', 'External B', 20, 0)),
  0::bigint, 'other tenant candidate is excluded'
);
select is(
  (select count(*) from public.lookup_team_member_candidates(
    '4d150000-0000-4000-8000-000000000001', null, 100, 0) as candidate
   join w4d_bulk_users as fixture on fixture.membership_id = candidate.membership_id
   where fixture.n = 3),
  0::bigint, 'existing active Team membership is excluded'
);
select is(
  (select count(*) from public.lookup_team_member_candidates(
    '4d150000-0000-4000-8000-000000000001', null, 100, 0) as candidate
   join w4d_bulk_users as fixture on fixture.membership_id = candidate.membership_id
   where fixture.n = 4),
  1::bigint, 'ended Team membership may return as a new-period candidate'
);
select throws_ok(
  $$select * from public.lookup_team_member_candidates('4d150000-0000-4000-8000-000000000002')$$,
  'P0001', 'TEAM_UNAVAILABLE', 'cross-tenant Team is rejected'
);
select throws_ok(
  $$select * from public.lookup_team_member_candidates('4d150000-0000-4000-8000-000000000003')$$,
  'P0001', 'TEAM_UNAVAILABLE', 'inactive Team is rejected'
);
select is(
  (select count(*) from public.lookup_team_member_candidates(
    '4d150000-0000-4000-8000-000000000001')),
  20::bigint, 'default result_limit is twenty'
);
select is(
  (select count(*) from public.lookup_team_member_candidates(
    '4d150000-0000-4000-8000-000000000001', null, 100, 0)),
  100::bigint, 'maximum result_limit is one hundred'
);
select throws_ok(
  $$select * from public.lookup_team_member_candidates('4d150000-0000-4000-8000-000000000001',null,101,0)$$,
  '22023', 'INVALID_QUERY_INPUT', 'limit above one hundred is rejected'
);
select throws_ok(
  $$select * from public.lookup_team_member_candidates('4d150000-0000-4000-8000-000000000001',null,0,0)$$,
  '22023', 'INVALID_QUERY_INPUT', 'zero limit is rejected'
);
select throws_ok(
  $$select * from public.lookup_team_member_candidates('4d150000-0000-4000-8000-000000000001',null,-1,0)$$,
  '22023', 'INVALID_QUERY_INPUT', 'negative limit is rejected'
);
select throws_ok(
  $$select * from public.lookup_team_member_candidates('4d150000-0000-4000-8000-000000000001',null,20,-1)$$,
  '22023', 'INVALID_QUERY_INPUT', 'negative offset is rejected'
);
select throws_ok(
  $$select * from public.lookup_team_member_candidates('4d150000-0000-4000-8000-000000000001',null,null,0)$$,
  '22023', 'INVALID_QUERY_INPUT', 'null limit is rejected'
);
select ok(
  (select pg_catalog.array_agg(membership_id order by ordinal)
   from public.lookup_team_member_candidates(
     '4d150000-0000-4000-8000-000000000001', null, 20, 0) with ordinality as page(membership_id,user_id,display_name,ordinal))
  ||
  (select pg_catalog.array_agg(membership_id order by ordinal)
   from public.lookup_team_member_candidates(
     '4d150000-0000-4000-8000-000000000001', null, 20, 20) with ordinality as page(membership_id,user_id,display_name,ordinal))
  =
  (select pg_catalog.array_agg(membership_id order by ordinal)
   from public.lookup_team_member_candidates(
     '4d150000-0000-4000-8000-000000000001', null, 40, 0) with ordinality as page(membership_id,user_id,display_name,ordinal)),
  'offset pages compose the same deterministic ordering as a wider page'
);
select is(
  (select count(*) from public.lookup_team_member_candidates(
    '4d150000-0000-4000-8000-000000000001', 'duplicada', 20, 0)),
  2::bigint, 'display name search is a case-insensitive literal substring'
);
select is(
  (select count(*) from public.lookup_team_member_candidates(
    '4d150000-0000-4000-8000-000000000001', '%', 20, 0)),
  2::bigint, 'percent sign is literal rather than an ILIKE wildcard'
);
select is(
  (select count(*) from public.lookup_team_member_candidates(
    '4d150000-0000-4000-8000-000000000001', '_', 20, 0)),
  2::bigint, 'underscore is literal rather than an ILIKE wildcard'
);
select is(
  (select count(*) from public.lookup_team_member_candidates(
    '4d150000-0000-4000-8000-000000000001', '  Ana  ', 20, 0)),
  1::bigint, 'search input is trimmed'
);
select is(
  (select count(*) from public.lookup_team_member_candidates(
    '4d150000-0000-4000-8000-000000000001', '', 20, 0)),
  20::bigint, 'empty search means unfiltered default page'
);
select is(
  (select count(*) from public.lookup_team_member_candidates(
    '4d150000-0000-4000-8000-000000000001', '   ', 20, 0)),
  20::bigint, 'whitespace-only search is unfiltered'
);
select throws_ok(
  $$select * from public.lookup_team_member_candidates('4d150000-0000-4000-8000-000000000001',repeat('x',161),20,0)$$,
  '22023', 'INVALID_QUERY_INPUT', 'search longer than 160 characters is rejected'
);
select is(
  (select count(*) from public.lookup_team_member_candidates(
    '4d150000-0000-4000-8000-000000000001', null, 100, 10) as candidate
   join w4d_bulk_users as fixture on fixture.membership_id = candidate.membership_id
   where fixture.n = 105 and candidate.display_name is null),
  1::bigint, 'null display name is retained and ordered after named candidates'
);
select is(
  (select count(*) from public.lookup_team_member_candidates(
    '4d150000-0000-4000-8000-000000000001', null, 3, 102)
   where display_name is null),
  3::bigint, 'all null names occur after the named candidate pages'
);
select is(
  (select count(distinct candidate.membership_id)
   from public.lookup_team_member_candidates(
     '4d150000-0000-4000-8000-000000000001', 'Pessoa Duplicada', 20, 0) as candidate),
  2::bigint, 'duplicate names retain distinct membership identities'
);
select is(
  (select count(*) from public.app_users where id <> auth.uid()),
  0::bigint, 'direct app_users SELECT cannot enumerate other users'
);
select is(
  (select count(*) from public.tenant_memberships where user_id <> auth.uid()),
  0::bigint, 'direct tenant_memberships SELECT cannot enumerate candidates'
);
select throws_ok(
  $$select count(*) from public.team_memberships$$,
  '42501', 'permission denied for table team_memberships',
  'direct Team membership SELECT remains denied'
);
reset role;

select is((select count(*) from public.audit_events),
  (select audit_count from w4d_side_effect_baseline), 'lookup creates no Audit');
select is((select count(*) from public.history_entries),
  (select history_count from w4d_side_effect_baseline), 'lookup creates no History');
select is((select count(*) from private.outbox_events),
  (select outbox_count from w4d_side_effect_baseline), 'lookup creates no Outbox event');
select is((select count(*) from private.command_idempotency),
  (select idempotency_count from w4d_side_effect_baseline), 'lookup creates no idempotency row');

-- read.all_tenant alone is not an implication to add.all_tenant.
insert into public.tenant_permission_overrides (
  tenant_id, membership_id, permission_id, effect, created_by, updated_by
)
select tenant.tenant_id, '4d120000-0000-4000-8000-000000000002',
       permission.id, 'allow',
       '4d100000-0000-4000-8000-000000000001',
       '4d100000-0000-4000-8000-000000000001'
from w4d_tenant_a as tenant
join public.permission_catalog as permission
  on permission.code = 'shared.team_memberships.read.all_tenant';
set local "request.jwt.claim.sub" = '4d100000-0000-4000-8000-000000000002';
set local role authenticated;
select throws_ok(
  $$select * from public.lookup_team_member_candidates('4d150000-0000-4000-8000-000000000001')$$,
  '42501', 'AUTHORIZATION_DENIED',
  'read.all_tenant alone cannot use the add candidate lookup'
);
select is(
  (select count(*) from public.list_teams()),
  0::bigint, 'candidate lookup did not expand TEAM reach for an unassigned actor'
);
reset role;

-- An exact add grant makes the projection available without roster read.
insert into public.tenant_permission_overrides (
  tenant_id, membership_id, permission_id, effect, created_by, updated_by
)
select tenant.tenant_id, '4d120000-0000-4000-8000-000000000002',
       permission.id, 'allow',
       '4d100000-0000-4000-8000-000000000001',
       '4d100000-0000-4000-8000-000000000001'
from w4d_tenant_a as tenant
join public.permission_catalog as permission
  on permission.code = 'shared.team_memberships.add.all_tenant';
set local "request.jwt.claim.sub" = '4d100000-0000-4000-8000-000000000002';
set local role authenticated;
select is(
  (select count(*) from public.lookup_team_member_candidates(
    '4d150000-0000-4000-8000-000000000001', 'Ana', 20, 0)),
  1::bigint, 'exact add grant enables the constrained projection'
);
reset role;

-- The actor must stay active in the authoritative DB context.
update public.tenant_memberships
set status = 'blocked', blocked_at = pg_catalog.statement_timestamp()
where id = '4d120000-0000-4000-8000-000000000002';
set local "request.jwt.claim.sub" = '4d100000-0000-4000-8000-000000000002';
set local role authenticated;
select throws_ok(
  $$select * from public.lookup_team_member_candidates('4d150000-0000-4000-8000-000000000001')$$,
  '42501', 'AUTHORIZATION_DENIED', 'blocked actor membership fails closed'
);
reset role;
update public.tenant_memberships
set status = 'active', blocked_at = null
where id = '4d120000-0000-4000-8000-000000000002';
update public.app_users
set status = 'blocked', blocked_at = pg_catalog.statement_timestamp()
where id = '4d100000-0000-4000-8000-000000000002';
set local "request.jwt.claim.sub" = '4d100000-0000-4000-8000-000000000002';
set local role authenticated;
select throws_ok(
  $$select * from public.lookup_team_member_candidates('4d150000-0000-4000-8000-000000000001')$$,
  '42501', 'AUTHORIZATION_DENIED', 'blocked actor app_user fails closed'
);
reset role;
update public.app_users
set status = 'active', blocked_at = null
where id = '4d100000-0000-4000-8000-000000000002';
update public.tenants
set status = 'suspended', suspended_at = pg_catalog.statement_timestamp()
where id = (select tenant_id from w4d_tenant_a);
set local "request.jwt.claim.sub" = '4d100000-0000-4000-8000-000000000002';
set local role authenticated;
select throws_ok(
  $$select * from public.lookup_team_member_candidates('4d150000-0000-4000-8000-000000000001')$$,
  '42501', 'AUTHORIZATION_DENIED', 'suspended tenant fails closed'
);
reset role;

select * from finish();
rollback;
