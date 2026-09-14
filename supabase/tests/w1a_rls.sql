begin;

set local search_path = public, extensions, pg_catalog;

select no_plan();

insert into auth.users (id, aud, role, email, created_at, updated_at)
values
  ('11000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'rls-user-a@example.invalid', statement_timestamp(), statement_timestamp()),
  ('11000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'rls-user-b@example.invalid', statement_timestamp(), statement_timestamp());

insert into public.tenants (
  id,
  tenant_ref,
  display_name,
  status,
  created_by
)
values
  ('21000000-0000-4000-8000-000000000001', '31000000-0000-4000-8000-000000000001', 'RLS Tenant A', 'active', '11000000-0000-4000-8000-000000000001'),
  ('21000000-0000-4000-8000-000000000002', '31000000-0000-4000-8000-000000000002', 'RLS Tenant B', 'active', '11000000-0000-4000-8000-000000000002');

do $$
begin
  perform * from private.provision_tenant_authorization('21000000-0000-4000-8000-000000000001');
  perform * from private.provision_tenant_authorization('21000000-0000-4000-8000-000000000002');
end;
$$;

insert into public.tenant_memberships (
  id,
  tenant_id,
  user_id,
  status,
  joined_at,
  created_by,
  profile_id,
  profile_assigned_at
)
values
  ('41000000-0000-4000-8000-000000000001', '21000000-0000-4000-8000-000000000001', '11000000-0000-4000-8000-000000000001', 'active', statement_timestamp(), '11000000-0000-4000-8000-000000000001', (select id from public.tenant_profiles where tenant_id = '21000000-0000-4000-8000-000000000001' and template_key = 'manager'), statement_timestamp()),
  ('41000000-0000-4000-8000-000000000002', '21000000-0000-4000-8000-000000000002', '11000000-0000-4000-8000-000000000002', 'active', statement_timestamp(), '11000000-0000-4000-8000-000000000002', (select id from public.tenant_profiles where tenant_id = '21000000-0000-4000-8000-000000000002' and template_key = 'manager'), statement_timestamp());

insert into public.tenant_entitlements (
  tenant_id,
  module_key,
  enabled,
  created_by
)
values
  ('21000000-0000-4000-8000-000000000001', 'maintenance', true, '11000000-0000-4000-8000-000000000001'),
  ('21000000-0000-4000-8000-000000000002', 'maintenance', true, '11000000-0000-4000-8000-000000000002');

insert into public.tenant_invitations (
  tenant_id,
  target_profile_id,
  recipient_email_hash,
  expires_at,
  created_by
)
values (
  '21000000-0000-4000-8000-000000000001',
  (select id from public.tenant_profiles where tenant_id = '21000000-0000-4000-8000-000000000001' and template_key = 'manager'),
  repeat('c', 64),
  statement_timestamp() + interval '1 day',
  '11000000-0000-4000-8000-000000000001'
);

insert into public.audit_events (
  tenant_id,
  actor_user_id,
  actor_kind,
  event_type,
  entity_type,
  entity_id
)
values (
  '21000000-0000-4000-8000-000000000001',
  '11000000-0000-4000-8000-000000000001',
  'application_user',
  'tenant.created',
  'tenant',
  '21000000-0000-4000-8000-000000000001'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename in (
        'app_users',
        'tenants',
        'tenant_memberships',
        'tenant_entitlements'
      )
  ),
  4::bigint,
  'only the four minimum read policies exist'
);

select is(
  pg_catalog.has_function_privilege('anon', 'private.is_active_principal()', 'EXECUTE'),
  false,
  'anon cannot execute the principal helper'
);

select is(
  pg_catalog.has_function_privilege('anon', 'private.can_access_tenant(uuid)', 'EXECUTE'),
  false,
  'anon cannot execute the tenant helper'
);

select is(
  (
    select count(*)
    from information_schema.routine_privileges
    where routine_schema = 'private'
      and grantee = 'PUBLIC'
      and privilege_type = 'EXECUTE'
  ),
  0::bigint,
  'private functions have no PUBLIC EXECUTE grant'
);

select is(
  (
    select count(*)
    from information_schema.table_privileges
    where table_schema = 'public'
      and table_name in (
        'app_users',
        'tenants',
        'tenant_memberships',
        'tenant_invitations',
        'tenant_entitlements',
        'audit_events'
      )
      and grantee in ('PUBLIC', 'anon')
  ),
  0::bigint,
  'PUBLIC and anon have no W1A table grants'
);

select is(
  (
    select count(*)
    from information_schema.table_privileges
    where table_schema = 'public'
      and table_name in (
        'app_users',
        'tenants',
        'tenant_memberships',
        'tenant_invitations',
        'tenant_entitlements',
        'audit_events'
      )
      and grantee = 'authenticated'
      and privilege_type <> 'SELECT'
  ),
  0::bigint,
  'authenticated has no W1A mutation grants'
);

set local role authenticated;
set local "request.jwt.claim.sub" = '11000000-0000-4000-8000-000000000001';

select is(
  (select count(*) from public.app_users),
  1::bigint,
  'User A reads only its own app_user'
);

select is(
  (select count(*) from public.app_users where id = '11000000-0000-4000-8000-000000000002'),
  0::bigint,
  'User A cannot read User B app_user'
);

select is(
  (select count(*) from public.tenants),
  1::bigint,
  'User A reads only Tenant A'
);

select is(
  (select count(*) from public.tenants where tenant_ref = '31000000-0000-4000-8000-000000000002'),
  0::bigint,
  'Tenant B ref does not expose Tenant B to User A'
);

select is(
  (select count(*) from public.tenant_memberships),
  1::bigint,
  'User A reads only its own membership'
);

select is(
  (select count(*) from public.tenant_entitlements where tenant_id = '21000000-0000-4000-8000-000000000001'),
  1::bigint,
  'User A reads Tenant A entitlement'
);

select is(
  (select count(*) from public.tenant_entitlements where tenant_id = '21000000-0000-4000-8000-000000000002'),
  0::bigint,
  'forged Tenant B target does not expose its entitlement to User A'
);

select ok(
  private.is_active_principal(),
  'principal helper derives User A from auth.uid()'
);

select ok(
  private.can_access_tenant('21000000-0000-4000-8000-000000000001'),
  'tenant helper authorizes the persisted User A membership'
);

select is(
  private.can_access_tenant('21000000-0000-4000-8000-000000000002'),
  false,
  'tenant_id target alone cannot authorize Tenant B'
);

reset role;
set local role authenticated;
set local "request.jwt.claim.sub" = '11000000-0000-4000-8000-000000000002';

select is(
  (select count(*) from public.app_users where id = '11000000-0000-4000-8000-000000000001'),
  0::bigint,
  'User B cannot read User A app_user'
);

select is(
  (select count(*) from public.tenants where id = '21000000-0000-4000-8000-000000000001'),
  0::bigint,
  'User B cannot read Tenant A'
);

select is(
  (select count(*) from public.tenant_memberships where user_id = '11000000-0000-4000-8000-000000000001'),
  0::bigint,
  'User B cannot read User A membership'
);

select is(
  (select count(*) from public.tenant_entitlements where tenant_id = '21000000-0000-4000-8000-000000000001'),
  0::bigint,
  'User B cannot read Tenant A entitlement'
);

reset role;
set local role authenticated;
set local "request.jwt.claim.sub" = '11000000-0000-4000-8000-000000000001';

select throws_ok(
  $$
    insert into public.tenant_memberships (
      tenant_id, user_id, status, joined_at, created_by
    ) values (
      '21000000-0000-4000-8000-000000000002',
      '11000000-0000-4000-8000-000000000001',
      'active',
      statement_timestamp(),
      '11000000-0000-4000-8000-000000000001'
    )
  $$,
  '42501',
  null,
  'forged tenant_id and user_id cannot create a membership'
);

select throws_ok(
  $$
    insert into public.tenant_memberships (
      tenant_id, user_id, status, joined_at, created_by
    ) values (
      '21000000-0000-4000-8000-000000000001',
      '11000000-0000-4000-8000-000000000002',
      'active',
      statement_timestamp(),
      '11000000-0000-4000-8000-000000000001'
    )
  $$,
  '42501',
  null,
  'forged user_id cannot create a membership for another principal'
);

select throws_ok(
  $$ update public.app_users set status = 'active' $$,
  '42501',
  null,
  'a user cannot change its own lifecycle fields directly'
);

select throws_ok(
  $$ select id from public.tenant_invitations $$,
  '42501',
  null,
  'invitations remain closed to client reads in W1A'
);

select throws_ok(
  $$ select id from public.audit_events $$,
  '42501',
  null,
  'audit remains closed to client reads in W1A'
);

select throws_ok(
  $$
    insert into public.audit_events (actor_kind, event_type, entity_type)
    values ('technical', 'forged.event', 'tenant')
  $$,
  '42501',
  null,
  'a user cannot insert arbitrary audit events'
);

reset role;

update public.app_users
set status = 'blocked',
    blocked_at = statement_timestamp()
where id = '11000000-0000-4000-8000-000000000001';

set local role authenticated;
set local "request.jwt.claim.sub" = '11000000-0000-4000-8000-000000000001';

select is(
  (select count(*) from public.tenants),
  0::bigint,
  'blocked app_user immediately removes tenant access'
);

reset role;

update public.app_users
set status = 'active',
    blocked_at = null
where id = '11000000-0000-4000-8000-000000000001';

update public.app_users
set status = 'inactive',
    inactivated_at = statement_timestamp()
where id = '11000000-0000-4000-8000-000000000001';

set local role authenticated;
set local "request.jwt.claim.sub" = '11000000-0000-4000-8000-000000000001';

select is(
  (select count(*) from public.tenants),
  0::bigint,
  'inactive app_user immediately removes tenant access'
);

reset role;

update public.app_users
set status = 'active',
    inactivated_at = null
where id = '11000000-0000-4000-8000-000000000001';

update public.tenant_memberships
set status = 'blocked',
    blocked_at = statement_timestamp()
where id = '41000000-0000-4000-8000-000000000001';

set local role authenticated;
set local "request.jwt.claim.sub" = '11000000-0000-4000-8000-000000000001';

select is(
  (select count(*) from public.tenants),
  0::bigint,
  'blocked membership immediately removes tenant access'
);

select is(
  (select count(*) from public.tenant_entitlements),
  0::bigint,
  'blocked membership immediately removes entitlement access'
);

reset role;

update public.tenant_memberships
set status = 'revoked',
    revoked_at = statement_timestamp()
where id = '41000000-0000-4000-8000-000000000001';

set local role authenticated;
set local "request.jwt.claim.sub" = '11000000-0000-4000-8000-000000000001';

select is(
  (select count(*) from public.tenants),
  0::bigint,
  'revoked membership immediately removes tenant access'
);

reset role;

update public.tenants
set status = 'suspended',
    suspended_at = statement_timestamp()
where id = '21000000-0000-4000-8000-000000000002';

set local role authenticated;
set local "request.jwt.claim.sub" = '11000000-0000-4000-8000-000000000002';

select is(
  (select count(*) from public.tenants),
  0::bigint,
  'suspended tenant is unavailable to its member'
);

select is(
  (select count(*) from public.tenant_entitlements),
  0::bigint,
  'suspended tenant hides its entitlements'
);

reset role;

update public.tenants
set status = 'inactive',
    inactivated_at = statement_timestamp()
where id = '21000000-0000-4000-8000-000000000002';

set local role authenticated;
set local "request.jwt.claim.sub" = '11000000-0000-4000-8000-000000000002';

select is(
  (select count(*) from public.tenants),
  0::bigint,
  'inactive tenant remains unavailable to its member'
);

reset role;

select * from finish();
rollback;
