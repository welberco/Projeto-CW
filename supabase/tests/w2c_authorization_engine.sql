begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Contract, ownership and grants.
select has_function(
  'private', 'resolve_effective_scopes', array['text', 'text'],
  'the central exact-scope evaluator exists'
);
select has_function(
  'private', 'has_effective_permission', array['text', 'text', 'authorization_scope'],
  'the exact permission predicate exists'
);
select is(
  has_function_privilege('authenticated', 'private.resolve_effective_scopes(text,text)', 'EXECUTE'),
  false,
  'the private evaluator is not a client RPC'
);
select is(
  (
    select count(*)
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname in ('private', 'public')
      and procedure.proname in (
        'resolve_effective_scopes', 'has_effective_permission',
        'resolve_profile_permission_ids', 'resolve_membership_permission_ids',
        'can_delegate_permission', 'tenant_has_authorization_administrator',
        'require_authorization_reason', 'lock_authorization_actor',
        'assert_tenant_has_authorization_administrator', 'write_authorization_audit',
        'create_tenant_profile', 'update_tenant_profile',
        'change_tenant_profile_status', 'set_tenant_profile_permission',
        'assign_tenant_membership_profile', 'set_tenant_permission_override',
        'delete_tenant_permission_override', 'change_tenant_membership_status',
        'invite_tenant_user', 'revoke_tenant_invitation_authenticated',
        'expire_tenant_invitation_authenticated'
      )
      and not exists (
        select 1
        from pg_catalog.unnest(coalesce(procedure.proconfig, array[]::text[])) as configuration(setting)
        where pg_catalog.split_part(configuration.setting, '=', 1) = 'search_path'
          and pg_catalog.replace(pg_catalog.split_part(configuration.setting, '=', 2), '"', '') = ''
      )
  ),
  0::bigint,
  'all W2C functions fix an empty search_path'
);
select is(
  (
    select count(*)
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
    join pg_catalog.pg_roles as owner_role on owner_role.oid = procedure.proowner
    where namespace.nspname in ('private', 'public')
      and procedure.proname in (
        'resolve_effective_scopes', 'lock_authorization_actor',
        'create_tenant_profile', 'update_tenant_profile',
        'change_tenant_profile_status', 'set_tenant_profile_permission',
        'assign_tenant_membership_profile', 'set_tenant_permission_override',
        'delete_tenant_permission_override', 'change_tenant_membership_status',
        'invite_tenant_user', 'revoke_tenant_invitation_authenticated',
        'expire_tenant_invitation_authenticated'
      )
      and owner_role.rolname in ('anon', 'authenticated', 'service_role')
  ),
  0::bigint,
  'W2C function owners are not client roles'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname in (
        'create_tenant_profile', 'update_tenant_profile',
        'change_tenant_profile_status', 'set_tenant_profile_permission',
        'assign_tenant_membership_profile', 'set_tenant_permission_override',
        'delete_tenant_permission_override', 'change_tenant_membership_status',
        'invite_tenant_user', 'revoke_tenant_invitation_authenticated',
        'expire_tenant_invitation_authenticated'
      )
      and not (procedure.proname = 'create_tenant_profile' and procedure.pronargs = 4)
      and pg_catalog.has_function_privilege('authenticated', procedure.oid, 'EXECUTE')
  ),
  11::bigint,
  'authenticated receives only the eleven explicit W2C command entrypoints'
);

select is(
  (
    select count(*)
    from information_schema.routine_privileges
    where specific_schema = 'public'
      and routine_name in (
        'create_tenant_profile', 'update_tenant_profile',
        'change_tenant_profile_status', 'set_tenant_profile_permission',
        'assign_tenant_membership_profile', 'set_tenant_permission_override',
        'delete_tenant_permission_override', 'change_tenant_membership_status',
        'invite_tenant_user', 'revoke_tenant_invitation_authenticated',
        'expire_tenant_invitation_authenticated'
      )
      and grantee in ('PUBLIC', 'anon', 'service_role')
  ),
  0::bigint,
  'W2C commands are closed to PUBLIC, anon and service_role'
);

-- Two isolated tenant fixtures and four principals.
insert into auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
values
  ('17000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'w2c-manager-a@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp()),
  ('17000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'w2c-worker-a@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp()),
  ('17000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'w2c-limited-a@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp()),
  ('17000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'w2c-manager-b@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp());

create temporary table w2c_tenant_a as
select * from public.bootstrap_initial_tenant(
  '17000000-0000-4000-8000-000000000001',
  'W2C Tenant A',
  '57000000-0000-4000-8000-000000000001'
);

grant select on table w2c_tenant_a to authenticated;

insert into public.tenants (id, tenant_ref, display_name, status, created_by)
values (
  '27000000-0000-4000-8000-000000000002',
  '47000000-0000-4000-8000-000000000002',
  'W2C Tenant B', 'active',
  '17000000-0000-4000-8000-000000000004'
);

select *
from private.provision_tenant_authorization(
  '27000000-0000-4000-8000-000000000002', null,
  '17000000-0000-4000-8000-000000000004',
  '57000000-0000-4000-8000-000000000002'
);

insert into public.tenant_memberships (
  tenant_id, user_id, status, joined_at, created_by,
  profile_id, profile_assigned_at, profile_assigned_by
)
select
  '27000000-0000-4000-8000-000000000002',
  '17000000-0000-4000-8000-000000000004',
  'active', statement_timestamp(), '17000000-0000-4000-8000-000000000004',
  profile.id, statement_timestamp(), '17000000-0000-4000-8000-000000000004'
from public.tenant_profiles as profile
where profile.tenant_id = '27000000-0000-4000-8000-000000000002'
  and profile.template_key = 'manager';

insert into public.tenant_entitlements (tenant_id, module_key, enabled, created_by)
values (
  '27000000-0000-4000-8000-000000000002', 'maintenance', true,
  '17000000-0000-4000-8000-000000000004'
);

create temporary table w2c_refs (
  key text primary key,
  id uuid not null,
  version bigint not null
);
grant select on table w2c_refs to authenticated;

insert into w2c_refs (key, id, version)
select 'tenant_b_assistant', profile.id, profile.version
from public.tenant_profiles as profile
where profile.tenant_id = '27000000-0000-4000-8000-000000000002'
  and profile.template_key = 'assistant';

insert into public.tenant_memberships (
  tenant_id, user_id, status, joined_at, created_by,
  profile_id, profile_assigned_at, profile_assigned_by
)
select
  (select tenant_id from w2c_tenant_a), target.user_id,
  'active', statement_timestamp(), '17000000-0000-4000-8000-000000000001',
  profile.id, statement_timestamp(), '17000000-0000-4000-8000-000000000001'
from (
  values
    ('17000000-0000-4000-8000-000000000002'::uuid, 'technician'::text),
    ('17000000-0000-4000-8000-000000000003'::uuid, 'assistant'::text)
) as target(user_id, template_key)
join public.tenant_profiles as profile
  on profile.tenant_id = (select tenant_id from w2c_tenant_a)
 and profile.template_key = target.template_key;

insert into w2c_refs (key, id, version)
select 'tenant_a_' || profile.template_key, profile.id, profile.version
from public.tenant_profiles as profile
where profile.tenant_id = (select tenant_id from w2c_tenant_a)
  and profile.template_key in ('manager', 'technician', 'assistant');

-- Test-only permission combinations exercise AUTH-01 without adding domain tables.
insert into public.permission_catalog (
  id, code, module_code, resource_code, action_code, scope,
  required_entitlement_key, tenant_delegable, label_key
)
values
  ('93000000-0000-4000-8000-000000000001', 'probe.authorization.read.own', 'probe', 'authorization', 'read', 'OWN', 'maintenance', true, 'probe.authorization.read.own.label'),
  ('93000000-0000-4000-8000-000000000002', 'probe.authorization.read.assigned', 'probe', 'authorization', 'read', 'ASSIGNED', 'maintenance', true, 'probe.authorization.read.assigned.label'),
  ('93000000-0000-4000-8000-000000000003', 'probe.authorization.read.team', 'probe', 'authorization', 'read', 'TEAM', 'maintenance', true, 'probe.authorization.read.team.label'),
  ('93000000-0000-4000-8000-000000000004', 'probe.authorization.read.all_tenant', 'probe', 'authorization', 'read', 'ALL_TENANT', 'maintenance', true, 'probe.authorization.read.all_tenant.label'),
  ('93000000-0000-4000-8000-000000000005', 'probe.authorization.delegate.own', 'probe', 'authorization', 'delegate', 'OWN', null, false, 'probe.authorization.delegate.own.label');

insert into public.tenant_profile_permissions (tenant_id, profile_id, permission_id, created_by)
select
  profile.tenant_id, profile.id, permission.id,
  '17000000-0000-4000-8000-000000000001'
from public.tenant_profiles as profile
cross join public.permission_catalog as permission
where profile.tenant_id = (select tenant_id from w2c_tenant_a)
  and profile.template_key = 'manager'
  and permission.id in (
    '93000000-0000-4000-8000-000000000001',
    '93000000-0000-4000-8000-000000000003',
    '93000000-0000-4000-8000-000000000004',
    '93000000-0000-4000-8000-000000000005'
  );

insert into public.tenant_permission_overrides (
  tenant_id, membership_id, permission_id, effect, created_by, updated_by
)
select
  membership.tenant_id, membership.id, permission.id,
  case permission.scope when 'ASSIGNED' then 'allow' else 'deny' end,
  '17000000-0000-4000-8000-000000000001',
  '17000000-0000-4000-8000-000000000001'
from public.tenant_memberships as membership
cross join public.permission_catalog as permission
where membership.user_id = '17000000-0000-4000-8000-000000000001'
  and permission.id in (
    '93000000-0000-4000-8000-000000000002',
    '93000000-0000-4000-8000-000000000004'
  );

set local "request.jwt.claim.sub" = '17000000-0000-4000-8000-000000000001';

select is(
  (
    select array_agg(scope order by scope)
    from private.resolve_effective_scopes('authorization', 'read') as scope
  ),
  array['OWN', 'ASSIGNED', 'TEAM']::public.authorization_scope[],
  'baseline and exact ALLOW override union scopes while exact DENY replaces only ALL_TENANT'
);
select is(
  private.has_effective_permission('authorization', 'read', 'OWN'),
  true,
  'an exact baseline scope is effective'
);
select is(
  private.has_effective_permission('authorization', 'read', 'ALL_TENANT'),
  false,
  'scope values do not imply or inherit another scope'
);
select is(
  private.has_effective_permission('users', 'invite', 'ALL_TENANT'),
  true,
  'the manager baseline resolves the seeded exact administrative permission'
);
select is(
  private.has_effective_permission('users', 'invite', 'TEAM'),
  false,
  'a nonexistent exact combination fails closed'
);

update public.tenant_entitlements
set enabled = false
where tenant_id = (select tenant_id from w2c_tenant_a)
  and module_key = 'maintenance';

select is(
  (select count(*) from private.resolve_effective_scopes('authorization', 'read')),
  0::bigint,
  'a disabled entitlement suppresses baseline and override ALLOW results'
);

update public.tenant_entitlements
set enabled = true
where tenant_id = (select tenant_id from w2c_tenant_a)
  and module_key = 'maintenance';

update public.permission_catalog
set status = 'deprecated', deprecated_at = statement_timestamp()
where id = '93000000-0000-4000-8000-000000000003';

select is(
  private.has_effective_permission('authorization', 'read', 'TEAM'),
  false,
  'deprecated catalog combinations fail closed'
);

update public.permission_catalog
set status = 'active', deprecated_at = null
where id = '93000000-0000-4000-8000-000000000003';

update public.tenant_memberships
set status = 'blocked', blocked_at = statement_timestamp()
where user_id = '17000000-0000-4000-8000-000000000001';

select is(
  (select count(*) from private.resolve_effective_scopes('authorization', 'read')),
  0::bigint,
  'current blocked membership state overrides a still-valid JWT claim'
);

update public.tenant_memberships
set status = 'active', blocked_at = null
where user_id = '17000000-0000-4000-8000-000000000001';

update public.app_users
set status = 'blocked', blocked_at = statement_timestamp()
where id = '17000000-0000-4000-8000-000000000001';

select is(
  (select count(*) from private.resolve_effective_scopes('authorization', 'read')),
  0::bigint,
  'current blocked application identity overrides stale JWT state'
);

update public.app_users
set status = 'active', blocked_at = null
where id = '17000000-0000-4000-8000-000000000001';

select is(
  private.can_delegate_permission('93000000-0000-4000-8000-000000000005'),
  false,
  'tenant_delegable false blocks delegation even when the actor holds the exact permission'
);

select is(
  private.tenant_has_authorization_administrator((select tenant_id from w2c_tenant_a)),
  true,
  'the provisioned manager is recognized by effective permissions rather than profile name'
);

insert into w2c_refs (key, id, version)
select
  case membership.user_id
    when '17000000-0000-4000-8000-000000000001' then 'manager_membership'
    when '17000000-0000-4000-8000-000000000002' then 'worker_membership'
    else 'limited_membership'
  end,
  membership.id,
  membership.version
from public.tenant_memberships as membership
where membership.user_id in (
  '17000000-0000-4000-8000-000000000001',
  '17000000-0000-4000-8000-000000000002',
  '17000000-0000-4000-8000-000000000003'
);

-- Authenticated commands reject unauthenticated and unauthorized callers.
reset "request.jwt.claim.sub";
set local role authenticated;
select throws_ok(
  $$ select * from public.create_tenant_profile('No principal', 'test', pg_catalog.gen_random_uuid()) $$,
  '28000', 'AUTHENTICATION_REQUIRED',
  'commands require an authenticated principal'
);
reset role;

set local "request.jwt.claim.sub" = '17000000-0000-4000-8000-000000000002';
set local role authenticated;
select throws_ok(
  $$ select * from public.create_tenant_profile('Forbidden', 'test', pg_catalog.gen_random_uuid()) $$,
  '42501', 'AUTHORIZATION_DENIED',
  'a member without the exact administrative permission is denied'
);
reset role;

-- Profile lifecycle commands and optimistic concurrency.
set local "request.jwt.claim.sub" = '17000000-0000-4000-8000-000000000001';
set local role authenticated;
select lives_ok(
  $$ select * from public.create_tenant_profile('Custom W2C', 'create custom profile', '57000000-0000-4000-8000-000000000010') $$,
  'authorized manager creates a tenant profile through the command boundary'
);
reset role;

select is(
  (select count(*) from public.tenant_profiles where tenant_id = (select tenant_id from w2c_tenant_a) and name = 'Custom W2C'),
  1::bigint,
  'profile creation is tenant-bound'
);

set local role authenticated;
select throws_ok(
  $$ select * from public.create_tenant_profile('Custom W2C', 'duplicate name', pg_catalog.gen_random_uuid()) $$,
  'P0001', 'AUTHORIZATION_OPERATION_UNAVAILABLE',
  'profile uniqueness conflicts do not expose internal constraint details'
);
reset role;

insert into w2c_refs (key, id, version)
select 'custom', profile.id, profile.version
from public.tenant_profiles as profile
where profile.tenant_id = (select tenant_id from w2c_tenant_a)
  and profile.name = 'Custom W2C';

set local role authenticated;
select lives_ok(
  format(
    'select * from public.update_tenant_profile(%L, %s, %L, %L, %L)',
    (select id from w2c_refs where key = 'custom'),
    (select version from w2c_refs where key = 'custom'),
    'Custom W2C Renamed', 'rename custom profile',
    '57000000-0000-4000-8000-000000000011'
  ),
  'authorized manager updates a profile with its current version'
);
reset role;

update w2c_refs
set version = (
  select profile.version from public.tenant_profiles as profile
  where profile.id = w2c_refs.id
)
where key = 'custom';

set local role authenticated;
select throws_ok(
  format(
    'select * from public.update_tenant_profile(%L, 1, %L, %L, %L)',
    (select id from w2c_refs where key = 'custom'),
    'Stale overwrite', 'stale test', '57000000-0000-4000-8000-000000000012'
  ),
  '40001', 'AUTHORIZATION_VERSION_CONFLICT',
  'stale profile versions fail closed without overwriting concurrent state'
);
reset role;

-- Cross-tenant identifiers are non-authoritative and non-enumerative.
set local role authenticated;
select throws_ok(
  format(
    'select * from public.update_tenant_profile(%L, %s, %L, %L, %L)',
    (select id from w2c_refs where key = 'tenant_b_assistant'),
    (select version from w2c_refs where key = 'tenant_b_assistant'),
    'Cross tenant', 'cross tenant attempt', '57000000-0000-4000-8000-000000000013'
  ),
  'P0001', 'AUTHORIZATION_OPERATION_UNAVAILABLE',
  'ALL_TENANT never crosses into another tenant'
);
reset role;

-- Baseline, assignment and override commands use exact differences.
set local role authenticated;
select lives_ok(
  format(
    'select * from public.set_tenant_profile_permission(%L, %L, true, %s, %L, %L)',
    (select id from w2c_refs where key = 'custom'),
    '91000000-0000-4000-8000-000000000001',
    (select version from w2c_refs where key = 'custom'),
    'grant exact read baseline', '57000000-0000-4000-8000-000000000020'
  ),
  'manager delegates an exact permission that the manager effectively holds'
);
reset role;

update w2c_refs
set version = (select profile.version from public.tenant_profiles as profile where profile.id = w2c_refs.id)
where key = 'custom';

set local role authenticated;
select lives_ok(
  format(
    'select * from public.assign_tenant_membership_profile(%L, %L, %s, %L, %L)',
    (select id from w2c_refs where key = 'worker_membership'),
    (select id from w2c_refs where key = 'custom'),
    (select version from w2c_refs where key = 'worker_membership'),
    'assign constrained custom profile', '57000000-0000-4000-8000-000000000021'
  ),
  'profile assignment succeeds when every newly effective permission is delegable by the actor'
);
reset role;

update w2c_refs
set version = (select membership.version from public.tenant_memberships as membership where membership.id = w2c_refs.id)
where key = 'worker_membership';

select is(
  (
    select profile_id
    from public.tenant_memberships
    where id = (select id from w2c_refs where key = 'worker_membership')
  ),
  (select id from w2c_refs where key = 'custom'),
  'assignment persists only the same-tenant target profile'
);

set local role authenticated;
select lives_ok(
  format(
    'select * from public.set_tenant_permission_override(%L, %L, %L, %s, %L, null, %L)',
    (select id from w2c_refs where key = 'worker_membership'),
    '91000000-0000-4000-8000-000000000001', 'deny',
    (select version from w2c_refs where key = 'worker_membership'),
    'deny exact inherited read', '57000000-0000-4000-8000-000000000022'
  ),
  'an exact DENY override replaces the inherited baseline combination'
);
reset role;

update w2c_refs
set version = (select membership.version from public.tenant_memberships as membership where membership.id = w2c_refs.id)
where key = 'worker_membership';

insert into w2c_refs (key, id, version)
select 'worker_read_override', individual_override.id, individual_override.version
from public.tenant_permission_overrides as individual_override
where individual_override.membership_id = (select id from w2c_refs where key = 'worker_membership')
  and individual_override.permission_id = '91000000-0000-4000-8000-000000000001';

set local role authenticated;
select throws_ok(
  format(
    'select * from public.set_tenant_permission_override(%L, %L, %L, %s, %L, 999, %L)',
    (select id from w2c_refs where key = 'worker_membership'),
    '91000000-0000-4000-8000-000000000001', 'allow',
    (select version from w2c_refs where key = 'worker_membership'),
    'stale override update', '57000000-0000-4000-8000-000000000022'
  ),
  '40001', 'AUTHORIZATION_VERSION_CONFLICT',
  'stale override versions cannot overwrite a concurrent exact exception'
);
reset role;

select is(
  (select effect from public.tenant_permission_overrides where id = (select id from w2c_refs where key = 'worker_read_override')),
  'deny',
  'the stale override command leaves the current effect unchanged'
);

set local "request.jwt.claim.sub" = '17000000-0000-4000-8000-000000000002';
select is(
  private.has_effective_permission('users', 'read', 'ALL_TENANT'),
  false,
  'the target evaluator observes the exact DENY immediately'
);

set local "request.jwt.claim.sub" = '17000000-0000-4000-8000-000000000001';
set local role authenticated;
select lives_ok(
  format(
    'select * from public.delete_tenant_permission_override(%L, %s, %s, %L, %L)',
    (select id from w2c_refs where key = 'worker_read_override'),
    (select version from w2c_refs where key = 'worker_membership'),
    (select version from w2c_refs where key = 'worker_read_override'),
    'restore inherited read', '57000000-0000-4000-8000-000000000023'
  ),
  'deleting a DENY that restores ALLOW succeeds only because the actor can delegate the exact permission'
);
reset role;

update w2c_refs
set version = (select membership.version from public.tenant_memberships as membership where membership.id = w2c_refs.id)
where key = 'worker_membership';

set local "request.jwt.claim.sub" = '17000000-0000-4000-8000-000000000002';
select is(
  private.has_effective_permission('users', 'read', 'ALL_TENANT'),
  true,
  'override deletion restores the exact inherited baseline'
);

-- A limited actor cannot self-escalate or delegate a non-delegable permission.
insert into public.tenant_profile_permissions (tenant_id, profile_id, permission_id, created_by)
values (
  (select tenant_id from w2c_tenant_a),
  (select id from w2c_refs where key = 'tenant_a_assistant'),
  '91000000-0000-4000-8000-000000000011',
  '17000000-0000-4000-8000-000000000001'
);

update w2c_refs
set version = (select profile.version from public.tenant_profiles as profile where profile.id = w2c_refs.id)
where key in ('tenant_a_assistant', 'tenant_a_manager');

set local "request.jwt.claim.sub" = '17000000-0000-4000-8000-000000000003';
set local role authenticated;
select throws_ok(
  format(
    'select * from public.set_tenant_profile_permission(%L, %L, true, %s, %L, %L)',
    (select id from w2c_refs where key = 'tenant_a_assistant'),
    '91000000-0000-4000-8000-000000000002',
    (select version from w2c_refs where key = 'tenant_a_assistant'),
    'attempt self escalation', '57000000-0000-4000-8000-000000000024'
  ),
  '42501', 'AUTHORIZATION_DELEGATION_DENIED',
  'holding the administration command does not let an actor grant a permission they lack'
);
reset role;

insert into public.tenant_profile_permissions (tenant_id, profile_id, permission_id, created_by)
values (
  (select tenant_id from w2c_tenant_a),
  (select id from w2c_refs where key = 'tenant_a_assistant'),
  '91000000-0000-4000-8000-000000000002',
  '17000000-0000-4000-8000-000000000001'
);

update w2c_refs
set version = (select profile.version from public.tenant_profiles as profile where profile.id = w2c_refs.id)
where key = 'tenant_a_assistant';

set local role authenticated;
select throws_ok(
  format(
    'select * from public.invite_tenant_user(%L, %s, %L, statement_timestamp() + interval %L, %L, %L)',
    (select id from w2c_refs where key = 'tenant_a_manager'),
    (select version from w2c_refs where key = 'tenant_a_manager'),
    'w2c-indirect@example.invalid', '1 day',
    'attempt indirect escalation', '57000000-0000-4000-8000-000000000024'
  ),
  '42501', 'AUTHORIZATION_DELEGATION_DENIED',
  'invitation cannot indirectly assign a profile containing permissions the inviter lacks'
);
reset role;

set local "request.jwt.claim.sub" = '17000000-0000-4000-8000-000000000001';
set local role authenticated;
select throws_ok(
  format(
    'select * from public.set_tenant_profile_permission(%L, %L, true, %s, %L, %L)',
    (select id from w2c_refs where key = 'custom'),
    '93000000-0000-4000-8000-000000000005',
    (select version from w2c_refs where key = 'custom'),
    'attempt nondelegable grant', '57000000-0000-4000-8000-000000000025'
  ),
  '42501', 'AUTHORIZATION_DELEGATION_DENIED',
  'tenant_delegable false blocks indirect escalation despite actor possession'
);
reset role;

-- The last effective full administrator cannot be weakened.
update w2c_refs
set version = (select membership.version from public.tenant_memberships as membership where membership.id = w2c_refs.id)
where key = 'manager_membership';

set local role authenticated;
select throws_ok(
  format(
    'select * from public.set_tenant_permission_override(%L, %L, %L, %s, %L, null, %L)',
    (select id from w2c_refs where key = 'manager_membership'),
    '91000000-0000-4000-8000-000000000001', 'deny',
    (select version from w2c_refs where key = 'manager_membership'),
    'attempt remove last admin capability', '57000000-0000-4000-8000-000000000026'
  ),
  '23514', 'LAST_AUTHORIZATION_ADMIN_REQUIRED',
  'a command cannot remove the final effective full authorization administrator'
);
reset role;

select is(
  (
    select count(*)
    from public.tenant_permission_overrides
    where membership_id = (select id from w2c_refs where key = 'manager_membership')
      and permission_id = '91000000-0000-4000-8000-000000000001'
  ),
  0::bigint,
  'the failed last-administrator mutation rolls back atomically'
);
select is(
  (
    select count(*)
    from public.audit_events
    where correlation_id = '57000000-0000-4000-8000-000000000026'
  ),
  0::bigint,
  'a failed last-administrator command leaves no partial audit event'
);

-- Membership lifecycle is current-state checked and optimistic.
set local role authenticated;
select lives_ok(
  format(
    'select * from public.change_tenant_membership_status(%L, %s, %L, %L, %L)',
    (select id from w2c_refs where key = 'worker_membership'),
    (select version from w2c_refs where key = 'worker_membership'),
    'blocked', 'temporarily block worker', '57000000-0000-4000-8000-000000000027'
  ),
  'authorized manager blocks a same-tenant membership'
);
reset role;

update w2c_refs
set version = (select membership.version from public.tenant_memberships as membership where membership.id = w2c_refs.id)
where key = 'worker_membership';

set local "request.jwt.claim.sub" = '17000000-0000-4000-8000-000000000002';
select is(
  private.has_effective_permission('users', 'read', 'ALL_TENANT'),
  false,
  'blocked membership loses effective authority immediately'
);

set local "request.jwt.claim.sub" = '17000000-0000-4000-8000-000000000001';
set local role authenticated;
select lives_ok(
  format(
    'select * from public.change_tenant_membership_status(%L, %s, %L, %L, %L)',
    (select id from w2c_refs where key = 'worker_membership'),
    (select version from w2c_refs where key = 'worker_membership'),
    'active', 'restore worker', '57000000-0000-4000-8000-000000000028'
  ),
  'reactivation checks every restored exact permission against actor delegation authority'
);
reset role;

update w2c_refs
set version = (select membership.version from public.tenant_memberships as membership where membership.id = w2c_refs.id)
where key = 'worker_membership';

-- Assigned profiles cannot be inactivated; after reassignment lifecycle commands succeed.
set local role authenticated;
select throws_ok(
  format(
    'select * from public.change_tenant_profile_status(%L, %s, %L, %L, %L)',
    (select id from w2c_refs where key = 'custom'),
    (select version from w2c_refs where key = 'custom'),
    'inactive', 'attempt assigned inactivation', '57000000-0000-4000-8000-000000000029'
  ),
  '23514', 'TENANT_PROFILE_ASSIGNED_TO_OPERATIONAL_MEMBERSHIP',
  'an operationally assigned profile cannot be inactivated'
);
reset role;

set local role authenticated;
select lives_ok(
  format(
    'select * from public.assign_tenant_membership_profile(%L, %L, %s, %L, %L)',
    (select id from w2c_refs where key = 'worker_membership'),
    (select id from w2c_refs where key = 'tenant_a_technician'),
    (select version from w2c_refs where key = 'worker_membership'),
    'return worker to technician', '57000000-0000-4000-8000-000000000030'
  ),
  'authority-reducing assignment does not require delegation of removed permissions'
);
reset role;

update w2c_refs
set version = (select profile.version from public.tenant_profiles as profile where profile.id = w2c_refs.id)
where key = 'custom';

set local role authenticated;
select lives_ok(
  format(
    'select * from public.change_tenant_profile_status(%L, %s, %L, %L, %L)',
    (select id from w2c_refs where key = 'custom'),
    (select version from w2c_refs where key = 'custom'),
    'inactive', 'inactivate unused profile', '57000000-0000-4000-8000-000000000031'
  ),
  'unused profile can be inactivated through its exact command permission'
);
reset role;

update w2c_refs
set version = (select profile.version from public.tenant_profiles as profile where profile.id = w2c_refs.id)
where key = 'custom';

set local role authenticated;
select lives_ok(
  format(
    'select * from public.change_tenant_profile_status(%L, %s, %L, %L, %L)',
    (select id from w2c_refs where key = 'custom'),
    (select version from w2c_refs where key = 'custom'),
    'active', 'reactivate profile', '57000000-0000-4000-8000-000000000032'
  ),
  'inactive profile can be reactivated through its exact command permission'
);
reset role;

-- Authenticated invitation boundary preserves one-time token secrecy.
set local role authenticated;
select lives_ok(
  format(
    'select * from public.invite_tenant_user(%L, %s, %L, statement_timestamp() + interval %L, %L, %L)',
    (select id from w2c_refs where key = 'tenant_a_technician'),
    (select version from w2c_refs where key = 'tenant_a_technician'),
    'w2c-invite@example.invalid', '1 day',
    'invite technician', '57000000-0000-4000-8000-000000000033'
  ),
  'authorized invitation derives actor and tenant from current database state'
);
reset role;

insert into w2c_refs (key, id, version)
select 'invitation', invitation.invite_ref, invitation.version
from public.tenant_invitations as invitation
where invitation.recipient_email_hash = private.sha256_hex('w2c-invite@example.invalid')
  and invitation.status = 'pending';

select ok(
  (
    select token_hash ~ '^[0-9a-f]{64}$'
    from public.tenant_invitations
    where invite_ref = (select id from w2c_refs where key = 'invitation')
  ),
  'only a fixed-length token hash is persisted'
);
select is(
  (
    select count(*)
    from public.audit_events as audit
    where audit.correlation_id = '57000000-0000-4000-8000-000000000033'
      and audit.metadata::text like '%invitation_token%'
  ),
  0::bigint,
  'plaintext invitation tokens are absent from audit metadata'
);

set local role authenticated;
select lives_ok(
  format(
    'select * from public.revoke_tenant_invitation_authenticated(%L, %s, %L, %L)',
    (select id from w2c_refs where key = 'invitation'),
    (select version from w2c_refs where key = 'invitation'),
    'revoke invitation', '57000000-0000-4000-8000-000000000034'
  ),
  'authenticated invitation revocation is versioned and tenant-bound'
);
reset role;

select is(
  (select status from public.tenant_invitations where invite_ref = (select id from w2c_refs where key = 'invitation')),
  'revoked',
  'revocation persists the expected lifecycle state'
);

insert into public.tenant_invitations (
  tenant_id, target_profile_id, recipient_email_hash, token_hash,
  expires_at, created_by, created_at, updated_at
)
values (
  (select tenant_id from w2c_tenant_a),
  (select id from w2c_refs where key = 'tenant_a_technician'),
  private.sha256_hex('w2c-expired@example.invalid'),
  private.sha256_hex(repeat('7', 64)),
  statement_timestamp() - interval '1 day',
  '17000000-0000-4000-8000-000000000001',
  statement_timestamp() - interval '2 days',
  statement_timestamp() - interval '2 days'
);

insert into w2c_refs (key, id, version)
select 'expired_invitation', invitation.invite_ref, invitation.version
from public.tenant_invitations as invitation
where invitation.recipient_email_hash = private.sha256_hex('w2c-expired@example.invalid')
  and invitation.status = 'pending';

set local role authenticated;
select lives_ok(
  format(
    'select * from public.expire_tenant_invitation_authenticated(%L, %s, %L, %L)',
    (select id from w2c_refs where key = 'expired_invitation'),
    (select version from w2c_refs where key = 'expired_invitation'),
    'expire elapsed invitation', '57000000-0000-4000-8000-000000000036'
  ),
  'elapsed invitation expiry is authenticated, tenant-bound and versioned'
);
reset role;

select is(
  (select status from public.tenant_invitations where invite_ref = (select id from w2c_refs where key = 'expired_invitation')),
  'expired',
  'expiry persists the expected lifecycle state'
);

-- Commands re-check mutable identity state instead of trusting a stale JWT.
update public.tenant_memberships
set status = 'blocked', blocked_at = statement_timestamp()
where id = (select id from w2c_refs where key = 'manager_membership');

set local role authenticated;
select throws_ok(
  $$ select * from public.create_tenant_profile('Stale JWT', 'must fail', pg_catalog.gen_random_uuid()) $$,
  'P0001', 'AUTHORIZATION_OPERATION_UNAVAILABLE',
  'a stale authenticated claim cannot bypass the current blocked membership'
);
reset role;

update public.tenant_memberships
set status = 'active', blocked_at = null
where id = (select id from w2c_refs where key = 'manager_membership');

select ok(
  (
    select bool_and(
      audit.actor_user_id = '17000000-0000-4000-8000-000000000001'
      and audit.tenant_id = (select tenant_id from w2c_tenant_a)
      and audit.metadata ? 'reason'
    )
    from public.audit_events as audit
    where audit.event_type like 'authorization.%'
      and audit.correlation_id between
        '57000000-0000-4000-8000-000000000010' and
        '57000000-0000-4000-8000-000000000034'
  ),
  'authorization command audits bind current actor, tenant, correlation and reason'
);

select * from finish();
rollback;
