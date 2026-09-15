begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

create temp view w2e_authorization_functions as
select
  procedure.oid,
  namespace.nspname as schema_name,
  procedure.proname,
  procedure.prosecdef,
  procedure.provolatile,
  procedure.proconfig,
  procedure.proowner,
  procedure.prosrc
from pg_catalog.pg_proc as procedure
join pg_catalog.pg_namespace as namespace
  on namespace.oid = procedure.pronamespace
where (
    namespace.nspname = 'private'
    and procedure.proname not in (
      'append_audit', 'append_history', 'jsonb_has_forbidden_history_keys',
      'prepare_audit_event', 'reject_history_mutation'
    )
  )
   or (
     namespace.nspname = 'public'
     and procedure.proname in (
       'bootstrap_initial_tenant', 'create_tenant_invitation',
       'revoke_tenant_invitation', 'expire_tenant_invitation',
       'accept_tenant_invitation', 'resolve_my_tenant_context',
       'create_tenant_profile', 'update_tenant_profile',
       'change_tenant_profile_status', 'set_tenant_profile_permission',
       'assign_tenant_membership_profile', 'set_tenant_permission_override',
       'delete_tenant_permission_override', 'change_tenant_membership_status',
       'invite_tenant_user', 'revoke_tenant_invitation_authenticated',
       'expire_tenant_invitation_authenticated', 'resolve_my_authorization'
     )
   );

-- Integrated RLS, grants, function and default-privilege inventory.
select is(
  (
    select count(*)
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relkind = 'r'
      and relation.relname in (
        'app_users', 'tenants', 'tenant_memberships', 'tenant_invitations',
        'tenant_entitlements', 'audit_events', 'permission_catalog',
        'tenant_profiles', 'tenant_profile_permissions', 'tenant_permission_overrides'
      )
      and relation.relrowsecurity
  ),
  10::bigint,
  'all W1/W2 public tables have RLS enabled'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename in (
        'app_users', 'tenants', 'tenant_memberships', 'tenant_invitations',
        'tenant_entitlements', 'audit_events', 'permission_catalog',
        'tenant_profiles', 'tenant_profile_permissions', 'tenant_permission_overrides'
      )
      and not (
        cmd = 'SELECT'
        and tablename in ('app_users', 'tenants', 'tenant_memberships', 'tenant_entitlements')
      )
  ),
  0::bigint,
  'the only W1/W2 policies are the four intentional read policies'
);

select is(
  (
    select count(*)
    from information_schema.table_privileges
    where table_schema in ('public', 'private')
      and grantee in ('PUBLIC', 'anon')
      and table_name in (
        'app_users', 'tenants', 'tenant_memberships', 'tenant_invitations',
        'tenant_entitlements', 'audit_events', 'permission_catalog',
        'tenant_profiles', 'tenant_profile_permissions', 'tenant_permission_overrides',
        'platform_bootstrap_state', 'authorization_catalog_state',
        'authorization_profile_templates', 'authorization_profile_template_permissions'
      )
  ),
  0::bigint,
  'PUBLIC and anon have no W1/W2 table privileges'
);

select is(
  (
    select count(*)
    from information_schema.table_privileges
    where table_schema = 'public'
      and grantee = 'authenticated'
      and privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'TRIGGER')
      and table_name in (
        'app_users', 'tenants', 'tenant_memberships', 'tenant_invitations',
        'tenant_entitlements', 'audit_events', 'permission_catalog',
        'tenant_profiles', 'tenant_profile_permissions', 'tenant_permission_overrides'
      )
  ),
  0::bigint,
  'authenticated has no direct W1/W2 mutation privilege'
);

select is(
  (
    select count(*)
    from information_schema.table_privileges
    where table_schema = 'public'
      and grantee = 'service_role'
      and table_name in (
        'app_users', 'tenants', 'tenant_memberships', 'tenant_invitations',
        'tenant_entitlements', 'audit_events', 'permission_catalog',
        'tenant_profiles', 'tenant_profile_permissions', 'tenant_permission_overrides'
      )
  ),
  0::bigint,
  'service_role cannot bypass authorization through direct W1/W2 tables'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_default_acl as default_acl
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = default_acl.defaclnamespace
    cross join lateral pg_catalog.aclexplode(default_acl.defaclacl) as privilege
    left join pg_catalog.pg_roles as grantee on grantee.oid = privilege.grantee
    where default_acl.defaclrole = 'postgres'::regrole
      and namespace.nspname in ('public', 'private')
      and default_acl.defaclobjtype in ('r', 'S', 'f')
      and coalesce(grantee.rolname, 'PUBLIC') in (
        'PUBLIC', 'anon', 'authenticated', 'service_role'
      )
  ),
  0::bigint,
  'future versioned W1/W2 objects are closed by default for the migration owner'
);

select is((select count(*) from w2e_authorization_functions), 46::bigint, 'the W1/W2 function inventory contains 46 routines');
select is((select count(*) from w2e_authorization_functions where prosecdef), 30::bigint, '30 authority-boundary routines are SECURITY DEFINER');
select is((select count(*) from w2e_authorization_functions where not prosecdef), 16::bigint, '16 trigger or validation routines are SECURITY INVOKER');
select is(
  (
    select count(*)
    from w2e_authorization_functions as function_inventory
    join pg_catalog.pg_roles as owner_role on owner_role.oid = function_inventory.proowner
    where owner_role.rolname <> 'postgres'
  ),
  0::bigint,
  'all W1/W2 routines have the controlled postgres owner'
);
select is(
  (
    select count(*)
    from w2e_authorization_functions
    where not exists (
      select 1
      from pg_catalog.unnest(coalesce(proconfig, array[]::text[])) as setting(value)
      where setting.value = 'search_path=""'
    )
  ),
  0::bigint,
  'every W1/W2 routine fixes an empty search_path'
);
select is(
  (
    select count(*)
    from w2e_authorization_functions
    where prosrc ~* E'(^|[^a-z_])execute[[:space:]]'
  ),
  0::bigint,
  'no W1/W2 routine uses dynamic SQL'
);
select is(
  (
    select count(*)
    from w2e_authorization_functions
    cross join lateral pg_catalog.aclexplode(
      coalesce(
        (select procedure.proacl from pg_catalog.pg_proc as procedure where procedure.oid = w2e_authorization_functions.oid),
        pg_catalog.acldefault('f', proowner)
      )
    ) as privilege
    where privilege.grantee = 0
  ),
  0::bigint,
  'no W1/W2 routine has PUBLIC EXECUTE'
);
select is(
  (
    select count(*)
    from w2e_authorization_functions
    where pg_catalog.has_function_privilege('anon', oid, 'EXECUTE')
  ),
  0::bigint,
  'anon cannot execute a W1/W2 routine'
);
select is(
  pg_catalog.has_function_privilege(
    'service_role', 'public.resolve_my_tenant_context(uuid)', 'EXECUTE'
  ),
  false,
  'service_role cannot call the authenticated self context projection'
);
select is(
  (
    select count(*)
    from information_schema.routine_privileges
    where routine_schema = 'public'
      and grantee = 'service_role'
      and privilege_type = 'EXECUTE'
      and routine_name in (
        'bootstrap_initial_tenant', 'create_tenant_invitation',
        'revoke_tenant_invitation', 'expire_tenant_invitation'
      )
  ),
  4::bigint,
  'service_role retains only the four documented technical W1 operations'
);
select is(
  (
    select count(*)
    from w2e_authorization_functions
    where schema_name = 'public'
      and pg_catalog.has_function_privilege('authenticated', oid, 'EXECUTE')
      and pg_catalog.pg_get_function_identity_arguments(oid) ~ '(actor_user_id|operator_user_id)'
  ),
  0::bigint,
  'no authenticated RPC accepts actor identity from payload'
);
select is(
  pg_catalog.pg_get_function_identity_arguments('public.resolve_my_authorization()'::regprocedure),
  ''::text,
  'authorization projection accepts no target, tenant or actor input'
);
select is(
  pg_catalog.has_function_privilege('service_role', 'public.resolve_my_authorization()', 'EXECUTE'),
  false,
  'service_role is not a functional authorization principal'
);

-- Two-tenant fixture with valid IDs known to the opposite principal.
insert into auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
values
  ('1e000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'w2e-a@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp()),
  ('1e000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'w2e-b@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp()),
  ('1e000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'w2e-limited@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp());

insert into public.tenants (id, tenant_ref, display_name, status, created_by)
values
  ('2e000000-0000-4000-8000-000000000001', '3e000000-0000-4000-8000-000000000001', 'W2E Tenant A', 'active', '1e000000-0000-4000-8000-000000000001'),
  ('2e000000-0000-4000-8000-000000000002', '3e000000-0000-4000-8000-000000000002', 'W2E Tenant B', 'active', '1e000000-0000-4000-8000-000000000002');

select * from private.provision_tenant_authorization('2e000000-0000-4000-8000-000000000001', null, '1e000000-0000-4000-8000-000000000001', '4e000000-0000-4000-8000-000000000001');
select * from private.provision_tenant_authorization('2e000000-0000-4000-8000-000000000002', null, '1e000000-0000-4000-8000-000000000002', '4e000000-0000-4000-8000-000000000002');

insert into public.tenant_entitlements (tenant_id, module_key, enabled, created_by)
values
  ('2e000000-0000-4000-8000-000000000001', 'maintenance', true, '1e000000-0000-4000-8000-000000000001'),
  ('2e000000-0000-4000-8000-000000000002', 'maintenance', true, '1e000000-0000-4000-8000-000000000002');

insert into public.tenant_memberships (
  id, tenant_id, user_id, status, joined_at, created_by,
  profile_id, profile_assigned_at, profile_assigned_by
)
select
  target.membership_id, target.tenant_id, target.user_id, 'active',
  statement_timestamp(), target.user_id, profile.id, statement_timestamp(), target.user_id
from (
  values
    ('5e000000-0000-4000-8000-000000000001'::uuid, '2e000000-0000-4000-8000-000000000001'::uuid, '1e000000-0000-4000-8000-000000000001'::uuid),
    ('5e000000-0000-4000-8000-000000000002'::uuid, '2e000000-0000-4000-8000-000000000002'::uuid, '1e000000-0000-4000-8000-000000000002'::uuid)
) as target(membership_id, tenant_id, user_id)
join public.tenant_profiles as profile
  on profile.tenant_id = target.tenant_id and profile.template_key = 'manager';

create temporary table w2e_refs (
  key text primary key,
  id uuid not null,
  version bigint not null
);
grant select on table w2e_refs to authenticated;
insert into w2e_refs (key, id, version)
select
  case
    when profile.tenant_id = '2e000000-0000-4000-8000-000000000002' then 'tenant_b_technician'
    else 'tenant_a_technician'
  end,
  profile.id,
  profile.version
from public.tenant_profiles as profile
where profile.template_key = 'technician'
  and profile.tenant_id in (
    '2e000000-0000-4000-8000-000000000001',
    '2e000000-0000-4000-8000-000000000002'
  );

set local "request.jwt.claim.sub" = '1e000000-0000-4000-8000-000000000001';
set local role authenticated;

select is((select count(*) from public.app_users), 1::bigint, 'Tenant A principal sees only its own application identity');
select is((select count(*) from public.tenants), 1::bigint, 'Tenant A cannot enumerate Tenant B');
select is((select count(*) from public.tenant_memberships), 1::bigint, 'Tenant A cannot enumerate Tenant B membership');
select is((select count(*) from public.tenant_entitlements), 1::bigint, 'Tenant A cannot enumerate Tenant B entitlement');
select is(
  (select context_status from public.resolve_my_tenant_context('3e000000-0000-4000-8000-000000000002')),
  'tenant_context_unavailable',
  'a valid Tenant B route reference cannot redefine the authoritative tenant'
);
select is(
  (select tenant_id from public.resolve_my_authorization()),
  '2e000000-0000-4000-8000-000000000001'::uuid,
  'the self projection remains bound to Tenant A'
);
select throws_ok(
  $$ select * from public.update_tenant_profile('6e000000-0000-4000-8000-000000000099', 1, 'Unknown', 'probe', pg_catalog.gen_random_uuid()) $$,
  'P0001', 'AUTHORIZATION_OPERATION_UNAVAILABLE',
  'a nonexistent profile returns the generic public error'
);
select throws_ok(
  format(
    'select * from public.update_tenant_profile(%L, %s, %L, %L, %L)',
    (select id from w2e_refs where key = 'tenant_b_technician'),
    (select version from w2e_refs where key = 'tenant_b_technician'),
    'Cross tenant', 'probe', pg_catalog.gen_random_uuid()
  ),
  'P0001', 'AUTHORIZATION_OPERATION_UNAVAILABLE',
  'a known Tenant B profile is non-enumerable and cannot be changed'
);
select throws_ok(
  $$ update public.tenant_memberships set profile_id = profile_id where id = '5e000000-0000-4000-8000-000000000002' $$,
  '42501', null,
  'authenticated cannot bypass commands with direct membership mutation'
);
select throws_ok(
  $$ insert into public.tenant_profile_permissions (tenant_id, profile_id, permission_id) values ('2e000000-0000-4000-8000-000000000001', pg_catalog.gen_random_uuid(), '91000000-0000-4000-8000-000000000001') $$,
  '42501', null,
  'authenticated cannot add a baseline directly'
);
select throws_ok(
  $$ insert into public.tenant_permission_overrides (tenant_id, membership_id, permission_id, effect) values ('2e000000-0000-4000-8000-000000000001', '5e000000-0000-4000-8000-000000000001', '91000000-0000-4000-8000-000000000001', 'allow') $$,
  '42501', null,
  'authenticated cannot add an override directly'
);
select throws_ok(
  $$ update public.audit_events set metadata = '{}'::jsonb $$,
  '42501', null,
  'authenticated cannot alter audit rows'
);
select throws_ok(
  $$ update public.permission_catalog set status = 'deprecated', deprecated_at = statement_timestamp() $$,
  '42501', null,
  'authenticated cannot mutate the platform permission catalog'
);
select throws_ok(
  $$ update private.authorization_profile_templates set default_name = 'Forged' $$,
  '42501', null,
  'authenticated cannot mutate private platform templates'
);

reset role;

select is(
  (select count(*) from private.resolve_effective_scopes('users', 'read')),
  1::bigint,
  'ALL_TENANT resolves only inside the current authoritative tenant'
);
select is(
  private.has_effective_permission('users', 'read', 'OWN'),
  false,
  'ALL_TENANT does not imply OWN or any scope hierarchy'
);
select is(
  private.has_effective_permission('users', '*', 'ALL_TENANT'),
  false,
  'wildcard actions fail closed'
);
select is(
  private.has_effective_permission('user', 'read', 'ALL_TENANT'),
  false,
  'prefix and substring resource matches fail closed'
);

-- Stale JWT must lose authority against current database lifecycle and entitlement facts.
update public.tenant_memberships
set status = 'blocked', blocked_at = statement_timestamp()
where id = '5e000000-0000-4000-8000-000000000001';
set local role authenticated;
select is((select projection_status from public.resolve_my_authorization()), 'membership_unavailable', 'blocked membership invalidates a still-valid JWT');
select throws_ok(
  $$ select * from public.create_tenant_profile('Blocked actor', 'probe', pg_catalog.gen_random_uuid()) $$,
  'P0001', 'AUTHORIZATION_OPERATION_UNAVAILABLE',
  'blocked membership cannot retain command authority'
);
reset role;
update public.tenant_memberships
set status = 'active', blocked_at = null
where id = '5e000000-0000-4000-8000-000000000001';

update public.app_users
set status = 'blocked', blocked_at = statement_timestamp()
where id = '1e000000-0000-4000-8000-000000000001';
set local role authenticated;
select is((select projection_status from public.resolve_my_authorization()), 'principal_unavailable', 'blocked app user invalidates a still-valid JWT');
reset role;
update public.app_users
set status = 'active', blocked_at = null
where id = '1e000000-0000-4000-8000-000000000001';

update public.tenants
set status = 'suspended', suspended_at = statement_timestamp()
where id = '2e000000-0000-4000-8000-000000000001';
set local role authenticated;
select is((select projection_status from public.resolve_my_authorization()), 'tenant_unavailable', 'suspended tenant invalidates a still-valid JWT');
reset role;
update public.tenants
set status = 'active', suspended_at = null
where id = '2e000000-0000-4000-8000-000000000001';

insert into public.permission_catalog (
  id, code, module_code, resource_code, action_code, scope,
  required_entitlement_key, tenant_delegable, label_key
)
values
  ('9e000000-0000-4000-8000-000000000001', 'probe.hardening.read.own', 'probe', 'hardening', 'read', 'OWN', 'maintenance', true, 'probe.hardening.read.own.label'),
  ('9e000000-0000-4000-8000-000000000002', 'probe.hardening.read.assigned', 'probe', 'hardening', 'read', 'ASSIGNED', 'maintenance', true, 'probe.hardening.read.assigned.label'),
  ('9e000000-0000-4000-8000-000000000003', 'probe.hardening.read.team', 'probe', 'hardening', 'read', 'TEAM', 'maintenance', true, 'probe.hardening.read.team.label'),
  ('9e000000-0000-4000-8000-000000000004', 'probe.hardening.read.all_tenant', 'probe', 'hardening', 'read', 'ALL_TENANT', 'maintenance', true, 'probe.hardening.read.all_tenant.label');

insert into public.tenant_profile_permissions (tenant_id, profile_id, permission_id, created_by)
select '2e000000-0000-4000-8000-000000000001', profile.id, permission.id,
  '1e000000-0000-4000-8000-000000000001'
from public.tenant_profiles as profile
cross join public.permission_catalog as permission
where profile.tenant_id = '2e000000-0000-4000-8000-000000000001'
  and profile.template_key = 'manager'
  and permission.id in (
    '9e000000-0000-4000-8000-000000000001',
    '9e000000-0000-4000-8000-000000000002',
    '9e000000-0000-4000-8000-000000000003',
    '9e000000-0000-4000-8000-000000000004'
  );

insert into public.tenant_permission_overrides (
  tenant_id, membership_id, permission_id, effect, created_by, updated_by
)
values (
  '2e000000-0000-4000-8000-000000000001',
  '5e000000-0000-4000-8000-000000000001',
  '9e000000-0000-4000-8000-000000000001',
  'deny',
  '1e000000-0000-4000-8000-000000000001',
  '1e000000-0000-4000-8000-000000000001'
);

select is(
  (select array_agg(scope order by scope) from private.resolve_effective_scopes('hardening', 'read') as scope),
  array['ASSIGNED', 'TEAM', 'ALL_TENANT']::public.authorization_scope[],
  'DENY OWN replaces only OWN while the remaining scopes form a union'
);

delete from public.tenant_permission_overrides
where membership_id = '5e000000-0000-4000-8000-000000000001'
  and permission_id = '9e000000-0000-4000-8000-000000000001';
insert into public.tenant_permission_overrides (
  tenant_id, membership_id, permission_id, effect, created_by, updated_by
)
values (
  '2e000000-0000-4000-8000-000000000001',
  '5e000000-0000-4000-8000-000000000001',
  '9e000000-0000-4000-8000-000000000002',
  'deny',
  '1e000000-0000-4000-8000-000000000001',
  '1e000000-0000-4000-8000-000000000001'
);

select is(
  (select array_agg(scope order by scope) from private.resolve_effective_scopes('hardening', 'read') as scope),
  array['OWN', 'TEAM', 'ALL_TENANT']::public.authorization_scope[],
  'DENY ASSIGNED does not remove TEAM or ALL_TENANT'
);

delete from public.tenant_permission_overrides
where membership_id = '5e000000-0000-4000-8000-000000000001'
  and permission_id = '9e000000-0000-4000-8000-000000000002';
insert into public.tenant_permission_overrides (
  tenant_id, membership_id, permission_id, effect, created_by, updated_by
)
values (
  '2e000000-0000-4000-8000-000000000001',
  '5e000000-0000-4000-8000-000000000001',
  '9e000000-0000-4000-8000-000000000003',
  'deny',
  '1e000000-0000-4000-8000-000000000001',
  '1e000000-0000-4000-8000-000000000001'
);

select is(
  (select array_agg(scope order by scope) from private.resolve_effective_scopes('hardening', 'read') as scope),
  array['OWN', 'ASSIGNED', 'ALL_TENANT']::public.authorization_scope[],
  'DENY TEAM does not remove ALL_TENANT'
);

update public.tenant_entitlements
set enabled = false
where tenant_id = '2e000000-0000-4000-8000-000000000001'
  and module_key = 'maintenance';
select is((select count(*) from private.resolve_effective_scopes('hardening', 'read')), 0::bigint, 'disabled entitlement suppresses baseline and override authority');
select is(private.has_effective_permission('users', 'read', 'ALL_TENANT'), true, 'core permission without entitlement remains governed by its formal rule');
set local role authenticated;
select is(
  (select count(*) from unnest((select permission_codes from public.resolve_my_authorization())) as code where code like 'probe.hardening.%'),
  0::bigint,
  'projection cannot bypass a disabled entitlement'
);
select is(
  (select count(*) from unnest((select permission_codes from public.resolve_my_authorization())) as code where code = 'core.users.read.all_tenant'),
  1::bigint,
  'projection retains unrelated core authority exactly'
);
reset role;
update public.tenant_entitlements
set enabled = true
where tenant_id = '2e000000-0000-4000-8000-000000000001'
  and module_key = 'maintenance';

update public.permission_catalog
set status = 'deprecated', deprecated_at = statement_timestamp()
where id = '9e000000-0000-4000-8000-000000000003';
select is(
  (select count(*) from public.tenant_profile_permissions where permission_id = '9e000000-0000-4000-8000-000000000003'),
  1::bigint,
  'deprecation preserves historical baseline rows'
);
select is(private.has_effective_permission('hardening', 'read', 'TEAM'), false, 'deprecated permission no longer resolves');
set local role authenticated;
select throws_ok(
  format(
    'select * from public.set_tenant_profile_permission(%L, %L, true, %s, %L, %L)',
    (select id from w2e_refs where key = 'tenant_a_technician'),
    '9e000000-0000-4000-8000-000000000003',
    (select version from w2e_refs where key = 'tenant_a_technician'),
    'probe', pg_catalog.gen_random_uuid()
  ),
  'P0001', 'AUTHORIZATION_OPERATION_UNAVAILABLE',
  'deprecated permission cannot receive a new baseline'
);
reset role;

-- service_role keeps technical RPCs but no direct authorization data plane.
set local role service_role;
select throws_ok(
  $$ select count(*) from public.tenant_memberships $$,
  '42501', null,
  'service_role cannot read membership authority directly'
);
select throws_ok(
  $$ update public.audit_events set metadata = '{}'::jsonb $$,
  '42501', null,
  'service_role cannot mutate audit directly'
);
reset role;

select is(
  (
    select count(*)
    from public.audit_events
    where metadata::text ~* '(invitation_token|password|jwt|service_role|secret)'
  ),
  0::bigint,
  'authorization audit contains no token, JWT, password or secret material'
);
select throws_ok(
  $$ update public.audit_events set metadata = metadata $$,
  '55000', 'audit_events is append-only',
  'audit remains append-only even for the controlled owner'
);
select is(
  (
    select count(*)
    from public.permission_catalog
    where code like '%*%'
       or code like '%global_admin%'
       or code like '%platform%'
  ),
  0::bigint,
  'catalog contains no wildcard, Global Admin or platform tenant permission'
);

select * from finish();
rollback;
