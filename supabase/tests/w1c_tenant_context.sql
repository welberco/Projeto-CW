begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  has_function('public', 'resolve_my_tenant_context', array['uuid']),
  'authoritative tenant context resolver exists'
);
select ok(
  has_function_privilege('authenticated', 'public.resolve_my_tenant_context(uuid)', 'EXECUTE'),
  'authenticated can execute the resolver'
);
select is(
  has_function_privilege('anon', 'public.resolve_my_tenant_context(uuid)', 'EXECUTE'),
  false,
  'anon cannot execute the resolver'
);
select is(
  (
    select count(*)
    from information_schema.routine_privileges
    where routine_schema = 'public'
      and routine_name = 'resolve_my_tenant_context'
      and grantee = 'PUBLIC'
  ),
  0::bigint,
  'resolver has no PUBLIC EXECUTE'
);

insert into auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
values
  ('14000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'ready-a@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp()),
  ('14000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'ready-b@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp()),
  ('14000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'blocked-principal@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp()),
  ('14000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'inactive-principal@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp()),
  ('14000000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'no-membership@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp()),
  ('14000000-0000-4000-8000-000000000006', 'authenticated', 'authenticated', 'blocked-membership@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp()),
  ('14000000-0000-4000-8000-000000000007', 'authenticated', 'authenticated', 'revoked-membership@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp()),
  ('14000000-0000-4000-8000-000000000008', 'authenticated', 'authenticated', 'suspended-tenant@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp()),
  ('14000000-0000-4000-8000-000000000009', 'authenticated', 'authenticated', 'disabled-feature@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp()),
  ('14000000-0000-4000-8000-000000000010', 'authenticated', 'authenticated', 'missing-profile@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp());

delete from public.app_users where id = '14000000-0000-4000-8000-000000000010';

update public.app_users
set status = 'blocked', blocked_at = statement_timestamp()
where id = '14000000-0000-4000-8000-000000000003';
update public.app_users
set status = 'inactive', inactivated_at = statement_timestamp()
where id = '14000000-0000-4000-8000-000000000004';

insert into public.tenants (id, tenant_ref, display_name, status, suspended_at, created_by)
values
  ('24000000-0000-4000-8000-000000000001', '34000000-0000-4000-8000-000000000001', 'Tenant A', 'active', null, '14000000-0000-4000-8000-000000000001'),
  ('24000000-0000-4000-8000-000000000002', '34000000-0000-4000-8000-000000000002', 'Tenant B', 'active', null, '14000000-0000-4000-8000-000000000002'),
  ('24000000-0000-4000-8000-000000000003', '34000000-0000-4000-8000-000000000003', 'Suspended Tenant', 'suspended', statement_timestamp(), '14000000-0000-4000-8000-000000000001'),
  ('24000000-0000-4000-8000-000000000004', '34000000-0000-4000-8000-000000000004', 'Disabled Feature Tenant', 'active', null, '14000000-0000-4000-8000-000000000001');

insert into public.tenant_memberships
  (id, tenant_id, user_id, status, joined_at, blocked_at, revoked_at, created_by)
values
  ('44000000-0000-4000-8000-000000000001', '24000000-0000-4000-8000-000000000001', '14000000-0000-4000-8000-000000000001', 'active', statement_timestamp(), null, null, '14000000-0000-4000-8000-000000000001'),
  ('44000000-0000-4000-8000-000000000002', '24000000-0000-4000-8000-000000000002', '14000000-0000-4000-8000-000000000002', 'active', statement_timestamp(), null, null, '14000000-0000-4000-8000-000000000001'),
  ('44000000-0000-4000-8000-000000000006', '24000000-0000-4000-8000-000000000001', '14000000-0000-4000-8000-000000000006', 'blocked', statement_timestamp(), statement_timestamp(), null, '14000000-0000-4000-8000-000000000001'),
  ('44000000-0000-4000-8000-000000000007', '24000000-0000-4000-8000-000000000001', '14000000-0000-4000-8000-000000000007', 'revoked', statement_timestamp(), null, statement_timestamp(), '14000000-0000-4000-8000-000000000001'),
  ('44000000-0000-4000-8000-000000000008', '24000000-0000-4000-8000-000000000003', '14000000-0000-4000-8000-000000000008', 'active', statement_timestamp(), null, null, '14000000-0000-4000-8000-000000000001'),
  ('44000000-0000-4000-8000-000000000009', '24000000-0000-4000-8000-000000000004', '14000000-0000-4000-8000-000000000009', 'active', statement_timestamp(), null, null, '14000000-0000-4000-8000-000000000001');

insert into public.tenant_entitlements (tenant_id, module_key, enabled, created_by)
values
  ('24000000-0000-4000-8000-000000000001', 'maintenance', true, '14000000-0000-4000-8000-000000000001'),
  ('24000000-0000-4000-8000-000000000002', 'maintenance', true, '14000000-0000-4000-8000-000000000001'),
  ('24000000-0000-4000-8000-000000000003', 'maintenance', true, '14000000-0000-4000-8000-000000000001'),
  ('24000000-0000-4000-8000-000000000004', 'maintenance', false, '14000000-0000-4000-8000-000000000001');

set local role authenticated;
set local "request.jwt.claim.sub" = '14000000-0000-4000-8000-000000000001';
select is(
  (select context_status from public.resolve_my_tenant_context(null)),
  'ready',
  'active principal resolves its single authoritative context without a route selector'
);
select is(
  (select tenant_ref from public.resolve_my_tenant_context('34000000-0000-4000-8000-000000000001')),
  '34000000-0000-4000-8000-000000000001'::uuid,
  'own opaque tenant ref selects the already-authorized context'
);
select is(
  (select membership_version from public.resolve_my_tenant_context(null)),
  1::bigint,
  'ready context carries membership version for cache identity'
);
select is(
  (select context_status from public.resolve_my_tenant_context('34000000-0000-4000-8000-000000000002')),
  'tenant_context_unavailable',
  'Tenant A cannot resolve Tenant B ref'
);
select is(
  (select context_status from public.resolve_my_tenant_context('34000000-0000-4000-8000-000000000099')),
  'tenant_context_unavailable',
  'unknown ref has the same external result as Tenant B ref'
);
select is(
  (select tenant_id from public.resolve_my_tenant_context('34000000-0000-4000-8000-000000000002')),
  null::uuid,
  'unauthorized ref does not project tenant identity'
);
reset role;

set local role authenticated;
set local "request.jwt.claim.sub" = '14000000-0000-4000-8000-000000000010';
select is((select context_status from public.resolve_my_tenant_context(null)), 'profile_missing', 'missing Application User fails closed');
reset role;

set local role authenticated;
set local "request.jwt.claim.sub" = '14000000-0000-4000-8000-000000000003';
select is((select context_status from public.resolve_my_tenant_context(null)), 'principal_unavailable', 'blocked principal loses context with a still-valid JWT');
reset role;

set local role authenticated;
set local "request.jwt.claim.sub" = '14000000-0000-4000-8000-000000000004';
select is((select context_status from public.resolve_my_tenant_context(null)), 'principal_unavailable', 'inactive principal loses context with a still-valid JWT');
reset role;

set local role authenticated;
set local "request.jwt.claim.sub" = '14000000-0000-4000-8000-000000000005';
select is((select context_status from public.resolve_my_tenant_context(null)), 'no_membership', 'principal without membership receives no context');
reset role;

set local role authenticated;
set local "request.jwt.claim.sub" = '14000000-0000-4000-8000-000000000006';
select is((select context_status from public.resolve_my_tenant_context(null)), 'membership_unavailable', 'blocked membership loses context');
reset role;

set local role authenticated;
set local "request.jwt.claim.sub" = '14000000-0000-4000-8000-000000000007';
select is((select context_status from public.resolve_my_tenant_context(null)), 'membership_unavailable', 'revoked membership history grants no context');
reset role;

set local role authenticated;
set local "request.jwt.claim.sub" = '14000000-0000-4000-8000-000000000008';
select is((select context_status from public.resolve_my_tenant_context(null)), 'tenant_unavailable', 'suspended tenant loses context');
reset role;

set local role authenticated;
set local "request.jwt.claim.sub" = '14000000-0000-4000-8000-000000000009';
select is((select context_status from public.resolve_my_tenant_context(null)), 'feature_unavailable', 'disabled maintenance entitlement loses context');
reset role;

update public.tenant_memberships
set status = 'revoked', revoked_at = statement_timestamp()
where id = '44000000-0000-4000-8000-000000000001';
set local role authenticated;
set local "request.jwt.claim.sub" = '14000000-0000-4000-8000-000000000001';
select is(
  (select context_status from public.resolve_my_tenant_context(null)),
  'membership_unavailable',
  'membership revocation is effective while the Auth JWT remains valid'
);
reset role;

select * from finish();
rollback;
