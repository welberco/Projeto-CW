begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select has_table('private', 'platform_bootstrap_state', 'authoritative bootstrap state exists');
select has_column('public', 'tenant_invitations', 'token_hash', 'invitation token hash exists');
select is(has_function_privilege('anon', 'public.bootstrap_initial_tenant(uuid,text,uuid)', 'EXECUTE'), false, 'anon cannot execute bootstrap');
select is(has_function_privilege('authenticated', 'public.bootstrap_initial_tenant(uuid,text,uuid)', 'EXECUTE'), false, 'authenticated cannot execute bootstrap');
select ok(has_function_privilege('service_role', 'public.bootstrap_initial_tenant(uuid,text,uuid)', 'EXECUTE'), 'server role can execute bootstrap');
select is(has_function_privilege('authenticated', 'public.create_tenant_invitation(uuid,uuid,text,timestamptz,uuid,uuid)', 'EXECUTE'), false, 'ordinary users cannot create invitations before W2C');
select is(has_function_privilege('authenticated', 'public.revoke_tenant_invitation(uuid,uuid,uuid)', 'EXECUTE'), false, 'ordinary users cannot revoke invitations before W2');
select is(has_function_privilege('authenticated', 'public.expire_tenant_invitation(uuid,uuid,uuid)', 'EXECUTE'), false, 'ordinary users cannot expire invitations before W2');
select ok(has_function_privilege('authenticated', 'public.accept_tenant_invitation(text,uuid)', 'EXECUTE'), 'authenticated can execute narrow acceptance');
select is(has_function_privilege('anon', 'public.accept_tenant_invitation(text,uuid)', 'EXECUTE'), false, 'anon cannot accept invitations');
select is(
  (select count(*) from information_schema.routine_privileges where routine_schema = 'public' and routine_name in ('bootstrap_initial_tenant', 'create_tenant_invitation', 'revoke_tenant_invitation', 'expire_tenant_invitation', 'accept_tenant_invitation') and grantee = 'PUBLIC'),
  0::bigint, 'W1B commands have no PUBLIC EXECUTE'
);

insert into auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
values
  ('12000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'bootstrap@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp()),
  ('12000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'target@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp()),
  ('12000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'wrong@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp()),
  ('12000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'revoked@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp()),
  ('12000000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'expired@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp()),
  ('12000000-0000-4000-8000-000000000006', 'authenticated', 'authenticated', 'active-conflict@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp()),
  ('12000000-0000-4000-8000-000000000007', 'authenticated', 'authenticated', 'blocked-conflict@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp()),
  ('12000000-0000-4000-8000-000000000008', 'authenticated', 'authenticated', 'reentry@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp()),
  ('12000000-0000-4000-8000-000000000009', 'authenticated', 'authenticated', 'suspended@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp()),
  ('12000000-0000-4000-8000-000000000010', 'authenticated', 'authenticated', 'inactive@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp());

select throws_ok(
  $$ select * from public.bootstrap_initial_tenant('12000000-0000-4000-8000-000000000099', 'Invalid Bootstrap', pg_catalog.gen_random_uuid()) $$,
  'P0001', 'BOOTSTRAP_IDENTITY_UNAVAILABLE', 'bootstrap requires an existing active Auth/Application User identity'
);
select is((select count(*) from public.tenants), 0::bigint, 'failed bootstrap leaves no partial tenant');
select is((select count(*) from private.platform_bootstrap_state), 0::bigint, 'failed bootstrap leaves no completion marker');

create temporary table w1b_bootstrap_result as
select * from public.bootstrap_initial_tenant(
  '12000000-0000-4000-8000-000000000001', 'W1B Tenant',
  '52000000-0000-4000-8000-000000000001'
);

select is((select count(*) from private.platform_bootstrap_state), 1::bigint, 'bootstrap state is written once');
select is((select count(*) from public.tenants), 1::bigint, 'bootstrap creates one tenant');
select is((select status from public.tenants), 'active', 'bootstrap finishes with active tenant');
select is((select count(*) from public.tenant_memberships), 1::bigint, 'bootstrap creates one membership');
select ok((select enabled from public.tenant_entitlements where module_key = 'maintenance'), 'bootstrap enables maintenance');
select is((select count(*) from public.audit_events where event_type = 'platform.bootstrap_completed'), 1::bigint, 'bootstrap writes audit');
select throws_ok(
  $$ select * from public.bootstrap_initial_tenant('12000000-0000-4000-8000-000000000001', 'Second Tenant', pg_catalog.gen_random_uuid()) $$,
  'P0001', 'SYSTEM_ALREADY_INITIALIZED', 'second bootstrap is rejected'
);

create temporary table w1b_invites (
  purpose text primary key,
  invite_ref uuid not null,
  invitation_token text not null
);
grant select on w1b_invites to authenticated;

insert into w1b_invites
select 'target', invitation.* from public.create_tenant_invitation(
  (select tenant_id from w1b_bootstrap_result),
  (select id from public.tenant_profiles where tenant_id = (select tenant_id from w1b_bootstrap_result) and template_key = 'manager'),
  '  TARGET@EXAMPLE.INVALID  ',
  statement_timestamp() + interval '1 day', '12000000-0000-4000-8000-000000000001',
  '52000000-0000-4000-8000-000000000003'
) as invitation;

select is(
  (select status from public.tenant_invitations where invite_ref = (select invite_ref from w1b_invites where purpose = 'target')),
  'pending', 'new invitation starts pending'
);

select is(
  (select recipient_email_hash from public.tenant_invitations where invite_ref = (select invite_ref from w1b_invites where purpose = 'target')),
  private.sha256_hex('target@example.invalid'), 'invitation email is normalized and hashed'
);
select isnt(
  (select token_hash from public.tenant_invitations where invite_ref = (select invite_ref from w1b_invites where purpose = 'target')),
  (select invitation_token from w1b_invites where purpose = 'target'), 'raw token is not persisted'
);
select is(
  (select count(*) from public.audit_events where metadata::text like '%' || (select invitation_token from w1b_invites where purpose = 'target') || '%'),
  0::bigint, 'raw token is absent from audit'
);

set local role authenticated;
set local "request.jwt.claim.sub" = '12000000-0000-4000-8000-000000000003';
select throws_ok(
  $$ select * from public.accept_tenant_invitation(repeat('0', 64), pg_catalog.gen_random_uuid()) $$,
  'P0001', 'INVITATION_UNAVAILABLE', 'wrong token fails safely'
);
select throws_ok(
  format('select * from public.accept_tenant_invitation(%L, %L)', (select invitation_token from w1b_invites where purpose = 'target'), pg_catalog.gen_random_uuid()),
  'P0001', 'INVITATION_UNAVAILABLE', 'wrong identity cannot accept'
);
reset role;

set local role authenticated;
set local "request.jwt.claim.sub" = '12000000-0000-4000-8000-000000000002';
select lives_ok(
  format('select * from public.accept_tenant_invitation(%L, %L)', (select invitation_token from w1b_invites where purpose = 'target'), '52000000-0000-4000-8000-000000000004'),
  'intended identity accepts invitation'
);
reset role;

select is((select status from public.tenant_invitations where invite_ref = (select invite_ref from w1b_invites where purpose = 'target')), 'accepted', 'invitation becomes accepted');
select is((select count(*) from public.tenant_memberships where user_id = '12000000-0000-4000-8000-000000000002' and status = 'active'), 1::bigint, 'acceptance creates one membership');
select is((select count(*) from public.audit_events where event_type = 'invitation.accepted' and actor_user_id = '12000000-0000-4000-8000-000000000002'), 1::bigint, 'acceptance writes audit');

set local role authenticated;
set local "request.jwt.claim.sub" = '12000000-0000-4000-8000-000000000002';
select throws_ok(
  format('select * from public.accept_tenant_invitation(%L, %L)', (select invitation_token from w1b_invites where purpose = 'target'), pg_catalog.gen_random_uuid()),
  'P0001', 'INVITATION_UNAVAILABLE', 'accepted invitation cannot be reused'
);
reset role;

insert into w1b_invites
select 'revoked', invitation.* from public.create_tenant_invitation(
  (select tenant_id from w1b_bootstrap_result),
  (select id from public.tenant_profiles where tenant_id = (select tenant_id from w1b_bootstrap_result) and template_key = 'manager'),
  'revoked@example.invalid', statement_timestamp() + interval '1 day',
  '12000000-0000-4000-8000-000000000001', pg_catalog.gen_random_uuid()
) as invitation;
select public.revoke_tenant_invitation(
  (select invite_ref from w1b_invites where purpose = 'revoked'),
  '12000000-0000-4000-8000-000000000001', pg_catalog.gen_random_uuid()
);
set local role authenticated;
set local "request.jwt.claim.sub" = '12000000-0000-4000-8000-000000000004';
select throws_ok(
  format('select * from public.accept_tenant_invitation(%L, %L)', (select invitation_token from w1b_invites where purpose = 'revoked'), pg_catalog.gen_random_uuid()),
  'P0001', 'INVITATION_UNAVAILABLE', 'revoked invitation cannot be accepted'
);
reset role;

insert into w1b_invites
select 'expired', invitation.* from public.create_tenant_invitation(
  (select tenant_id from w1b_bootstrap_result),
  (select id from public.tenant_profiles where tenant_id = (select tenant_id from w1b_bootstrap_result) and template_key = 'manager'),
  'expired@example.invalid', statement_timestamp() + interval '1 day',
  '12000000-0000-4000-8000-000000000001', pg_catalog.gen_random_uuid()
) as invitation;
update public.tenant_invitations
set created_at = statement_timestamp() - interval '2 days', expires_at = statement_timestamp() - interval '1 day'
where invite_ref = (select invite_ref from w1b_invites where purpose = 'expired');
set local role authenticated;
set local "request.jwt.claim.sub" = '12000000-0000-4000-8000-000000000005';
select throws_ok(
  format('select * from public.accept_tenant_invitation(%L, %L)', (select invitation_token from w1b_invites where purpose = 'expired'), pg_catalog.gen_random_uuid()),
  'P0001', 'INVITATION_UNAVAILABLE', 'expired invitation cannot be accepted'
);
reset role;
select public.expire_tenant_invitation(
  (select invite_ref from w1b_invites where purpose = 'expired'),
  '12000000-0000-4000-8000-000000000001', pg_catalog.gen_random_uuid()
);
select is((select status from public.tenant_invitations where invite_ref = (select invite_ref from w1b_invites where purpose = 'expired')), 'expired', 'expiry command preserves lifecycle');

insert into w1b_invites
select 'active-conflict', invitation.* from public.create_tenant_invitation(
  (select tenant_id from w1b_bootstrap_result),
  (select id from public.tenant_profiles where tenant_id = (select tenant_id from w1b_bootstrap_result) and template_key = 'manager'),
  'active-conflict@example.invalid', statement_timestamp() + interval '1 day',
  '12000000-0000-4000-8000-000000000001', pg_catalog.gen_random_uuid()
) as invitation;
insert into w1b_invites
select 'blocked-conflict', invitation.* from public.create_tenant_invitation(
  (select tenant_id from w1b_bootstrap_result),
  (select id from public.tenant_profiles where tenant_id = (select tenant_id from w1b_bootstrap_result) and template_key = 'manager'),
  'blocked-conflict@example.invalid', statement_timestamp() + interval '1 day',
  '12000000-0000-4000-8000-000000000001', pg_catalog.gen_random_uuid()
) as invitation;
insert into w1b_invites
select 'reentry', invitation.* from public.create_tenant_invitation(
  (select tenant_id from w1b_bootstrap_result),
  (select id from public.tenant_profiles where tenant_id = (select tenant_id from w1b_bootstrap_result) and template_key = 'manager'),
  'reentry@example.invalid', statement_timestamp() + interval '1 day',
  '12000000-0000-4000-8000-000000000001', pg_catalog.gen_random_uuid()
) as invitation;

insert into public.tenants (id, tenant_ref, display_name, status, created_by)
values ('22000000-0000-4000-8000-000000000001', '32000000-0000-4000-8000-000000000001', 'Prior Tenant', 'active', '12000000-0000-4000-8000-000000000001');

do $$
begin
  perform * from private.provision_tenant_authorization('22000000-0000-4000-8000-000000000001');
end;
$$;

insert into public.tenant_memberships (tenant_id, user_id, status, joined_at, blocked_at, revoked_at, created_by, profile_id, profile_assigned_at)
values
  ('22000000-0000-4000-8000-000000000001', '12000000-0000-4000-8000-000000000006', 'active', statement_timestamp(), null, null, '12000000-0000-4000-8000-000000000001', (select id from public.tenant_profiles where tenant_id = '22000000-0000-4000-8000-000000000001' and template_key = 'manager'), statement_timestamp()),
  ('22000000-0000-4000-8000-000000000001', '12000000-0000-4000-8000-000000000007', 'blocked', statement_timestamp(), statement_timestamp(), null, '12000000-0000-4000-8000-000000000001', (select id from public.tenant_profiles where tenant_id = '22000000-0000-4000-8000-000000000001' and template_key = 'manager'), statement_timestamp()),
  ('22000000-0000-4000-8000-000000000001', '12000000-0000-4000-8000-000000000008', 'revoked', statement_timestamp(), null, statement_timestamp(), '12000000-0000-4000-8000-000000000001', (select id from public.tenant_profiles where tenant_id = '22000000-0000-4000-8000-000000000001' and template_key = 'manager'), statement_timestamp());

set local role authenticated;
set local "request.jwt.claim.sub" = '12000000-0000-4000-8000-000000000006';
select throws_ok(
  format('select * from public.accept_tenant_invitation(%L, %L)', (select invitation_token from w1b_invites where purpose = 'active-conflict'), pg_catalog.gen_random_uuid()),
  'P0001', 'INVITATION_UNAVAILABLE', 'active membership blocks acceptance'
);
reset role;
set local role authenticated;
set local "request.jwt.claim.sub" = '12000000-0000-4000-8000-000000000007';
select throws_ok(
  format('select * from public.accept_tenant_invitation(%L, %L)', (select invitation_token from w1b_invites where purpose = 'blocked-conflict'), pg_catalog.gen_random_uuid()),
  'P0001', 'INVITATION_UNAVAILABLE', 'blocked membership blocks acceptance'
);
reset role;
set local role authenticated;
set local "request.jwt.claim.sub" = '12000000-0000-4000-8000-000000000008';
select lives_ok(
  format('select * from public.accept_tenant_invitation(%L, %L)', (select invitation_token from w1b_invites where purpose = 'reentry'), pg_catalog.gen_random_uuid()),
  'revoked membership permits historical re-entry'
);
reset role;

insert into w1b_invites
select 'suspended', invitation.* from public.create_tenant_invitation(
  (select tenant_id from w1b_bootstrap_result),
  (select id from public.tenant_profiles where tenant_id = (select tenant_id from w1b_bootstrap_result) and template_key = 'manager'),
  'suspended@example.invalid', statement_timestamp() + interval '1 day',
  '12000000-0000-4000-8000-000000000001', pg_catalog.gen_random_uuid()
) as invitation;
insert into w1b_invites
select 'inactive', invitation.* from public.create_tenant_invitation(
  (select tenant_id from w1b_bootstrap_result),
  (select id from public.tenant_profiles where tenant_id = (select tenant_id from w1b_bootstrap_result) and template_key = 'manager'),
  'inactive@example.invalid', statement_timestamp() + interval '1 day',
  '12000000-0000-4000-8000-000000000001', pg_catalog.gen_random_uuid()
) as invitation;

update public.tenants set status = 'suspended', suspended_at = statement_timestamp()
where id = (select tenant_id from w1b_bootstrap_result);
set local role authenticated;
set local "request.jwt.claim.sub" = '12000000-0000-4000-8000-000000000009';
select throws_ok(
  format('select * from public.accept_tenant_invitation(%L, %L)', (select invitation_token from w1b_invites where purpose = 'suspended'), pg_catalog.gen_random_uuid()),
  'P0001', 'INVITATION_UNAVAILABLE', 'suspended tenant blocks onboarding'
);
reset role;

update public.tenants set status = 'inactive', suspended_at = null, inactivated_at = statement_timestamp()
where id = (select tenant_id from w1b_bootstrap_result);
set local role authenticated;
set local "request.jwt.claim.sub" = '12000000-0000-4000-8000-000000000010';
select throws_ok(
  format('select * from public.accept_tenant_invitation(%L, %L)', (select invitation_token from w1b_invites where purpose = 'inactive'), pg_catalog.gen_random_uuid()),
  'P0001', 'INVITATION_UNAVAILABLE', 'inactive tenant blocks onboarding'
);
reset role;

select is(
  (select count(*) from information_schema.parameters where specific_schema = 'public' and specific_name like 'accept_tenant_invitation_%' and parameter_mode = 'IN'),
  2::bigint, 'acceptance accepts no tenant, user, role or status input'
);

select is(
  (select count(*) from information_schema.routine_privileges where routine_schema = 'private' and grantee = 'PUBLIC' and privilege_type = 'EXECUTE'),
  0::bigint, 'private helpers have no PUBLIC EXECUTE'
);

select * from finish();
rollback;
