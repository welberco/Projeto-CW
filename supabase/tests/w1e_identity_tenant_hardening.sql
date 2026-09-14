begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

-- Security surface: RLS, grants, owners and fixed search paths.
select is(
  (
    select count(*)
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname in (
        'app_users',
        'tenants',
        'tenant_memberships',
        'tenant_invitations',
        'tenant_entitlements',
        'audit_events'
      )
      and relation.relrowsecurity
  ),
  6::bigint,
  'all exposed W1 tables keep RLS enabled'
);

select is(
  (
    select count(*)
    from information_schema.table_privileges
    where table_schema in ('public', 'private')
      and table_name in (
        'app_users',
        'tenants',
        'tenant_memberships',
        'tenant_invitations',
        'tenant_entitlements',
        'audit_events',
        'platform_bootstrap_state'
      )
      and grantee in ('PUBLIC', 'anon')
  ),
  0::bigint,
  'PUBLIC and anon have no W1 table privileges'
);

select is(
  (
    select count(*)
    from information_schema.table_privileges
    where table_schema in ('public', 'private')
      and table_name in (
        'app_users',
        'tenants',
        'tenant_memberships',
        'tenant_invitations',
        'tenant_entitlements',
        'audit_events',
        'platform_bootstrap_state'
      )
      and grantee = 'authenticated'
      and privilege_type <> 'SELECT'
  ),
  0::bigint,
  'authenticated has no direct W1 table mutation privileges'
);

select is(
  (
    select count(*)
    from information_schema.table_privileges
    where table_schema = 'private'
      and table_name = 'platform_bootstrap_state'
      and grantee = 'authenticated'
  ),
  0::bigint,
  'bootstrap state is not exposed to authenticated users'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = procedure.pronamespace
    where (
      (
        namespace.nspname = 'private'
        and procedure.proname in (
          'create_app_user_for_auth_identity',
          'is_active_principal',
          'can_access_tenant'
        )
      ) or (
        namespace.nspname = 'public'
        and procedure.proname in (
          'bootstrap_initial_tenant',
          'create_tenant_invitation',
          'revoke_tenant_invitation',
          'expire_tenant_invitation',
          'accept_tenant_invitation',
          'resolve_my_tenant_context'
        )
      )
    )
      and procedure.prosecdef
  ),
  9::bigint,
  'only the expected W1 authority-boundary functions are SECURITY DEFINER'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = procedure.pronamespace
    join pg_catalog.pg_roles as owner_role
      on owner_role.oid = procedure.proowner
    where (
      (
        namespace.nspname = 'private'
        and procedure.proname in (
          'create_app_user_for_auth_identity',
          'is_active_principal',
          'can_access_tenant'
        )
      ) or (
        namespace.nspname = 'public'
        and procedure.proname in (
          'bootstrap_initial_tenant',
          'create_tenant_invitation',
          'revoke_tenant_invitation',
          'expire_tenant_invitation',
          'accept_tenant_invitation',
          'resolve_my_tenant_context'
        )
      )
    )
      and owner_role.rolname in ('PUBLIC', 'anon', 'authenticated', 'service_role')
  ),
  0::bigint,
  'privileged W1 functions are not owned by client-facing roles'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = procedure.pronamespace
    where (
      (
        namespace.nspname = 'private'
        and procedure.proname in (
          'create_app_user_for_auth_identity',
          'is_active_principal',
          'can_access_tenant'
        )
      ) or (
        namespace.nspname = 'public'
        and procedure.proname in (
          'bootstrap_initial_tenant',
          'create_tenant_invitation',
          'revoke_tenant_invitation',
          'expire_tenant_invitation',
          'accept_tenant_invitation',
          'resolve_my_tenant_context'
        )
      )
    )
      and not exists (
        select 1
        from pg_catalog.unnest(
          coalesce(procedure.proconfig, array[]::text[])
        ) as configuration(setting)
        where pg_catalog.split_part(configuration.setting, '=', 1) = 'search_path'
          and pg_catalog.replace(
            pg_catalog.split_part(configuration.setting, '=', 2),
            '"',
            ''
          ) = ''
      )
  ),
  0::bigint,
  'every privileged W1 function fixes an empty search_path'
);

select is(
  (
    select count(*)
    from information_schema.routine_privileges
    where routine_schema in ('public', 'private')
      and routine_name in (
        'create_app_user_for_auth_identity',
        'is_active_principal',
        'can_access_tenant',
        'bootstrap_initial_tenant',
        'create_tenant_invitation',
        'revoke_tenant_invitation',
        'expire_tenant_invitation',
        'accept_tenant_invitation',
        'resolve_my_tenant_context'
      )
      and grantee = 'PUBLIC'
  ),
  0::bigint,
  'W1 authority-boundary functions have no PUBLIC EXECUTE'
);

select is(
  has_function_privilege(
    'service_role',
    'public.accept_tenant_invitation(text,uuid)',
    'EXECUTE'
  ),
  false,
  'service_role cannot accept an invitation'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.accept_tenant_invitation(text,uuid)',
    'EXECUTE'
  ),
  'only the authenticated onboarding boundary can accept an invitation'
);

select is(
  has_function_privilege(
    'anon',
    'public.resolve_my_tenant_context(uuid)',
    'EXECUTE'
  ),
  false,
  'anon cannot resolve tenant context'
);

select is(
  (
    select count(*)
    from information_schema.routine_privileges
    where routine_schema = 'public'
      and routine_name in (
        'bootstrap_initial_tenant',
        'create_tenant_invitation',
        'revoke_tenant_invitation',
        'expire_tenant_invitation'
      )
      and grantee in ('anon', 'authenticated')
  ),
  0::bigint,
  'anon and authenticated cannot execute bootstrap or invitation administration'
);

select is(
  (
    select count(*)
    from information_schema.routine_privileges
    where routine_schema = 'public'
      and routine_name in (
        'bootstrap_initial_tenant',
        'create_tenant_invitation',
        'revoke_tenant_invitation',
        'expire_tenant_invitation'
      )
      and grantee = 'service_role'
      and privilege_type = 'EXECUTE'
  ),
  4::bigint,
  'service_role has exactly the four operational W1 administration commands'
);

select ok(
  pg_catalog.pg_get_functiondef(
    'public.bootstrap_initial_tenant(uuid,text,uuid)'::regprocedure
  ) like '%pg_advisory_xact_lock%',
  'bootstrap keeps its transaction-scoped advisory lock'
);

select ok(
  pg_catalog.pg_get_functiondef(
    'public.accept_tenant_invitation(text,uuid)'::regprocedure
  ) like '%pg_advisory_xact_lock%',
  'invitation acceptance keeps its transaction-scoped advisory locks'
);

-- Current database facts remain authoritative while the same JWT sub is kept.
insert into auth.users (
  id, aud, role, email, email_confirmed_at, created_at, updated_at
)
values
  (
    '15000000-0000-4000-8000-000000000001',
    'authenticated',
    'authenticated',
    'w1e-user-a@example.invalid',
    statement_timestamp(),
    statement_timestamp(),
    statement_timestamp()
  ),
  (
    '15000000-0000-4000-8000-000000000002',
    'authenticated',
    'authenticated',
    'w1e-user-b@example.invalid',
    statement_timestamp(),
    statement_timestamp(),
    statement_timestamp()
  );

insert into public.tenants (
  id, tenant_ref, display_name, status, created_by
)
values
  (
    '25000000-0000-4000-8000-000000000001',
    '35000000-0000-4000-8000-000000000001',
    'W1E Tenant A',
    'active',
    '15000000-0000-4000-8000-000000000001'
  ),
  (
    '25000000-0000-4000-8000-000000000002',
    '35000000-0000-4000-8000-000000000002',
    'W1E Tenant B',
    'active',
    '15000000-0000-4000-8000-000000000002'
  );

do $$
begin
  perform * from private.provision_tenant_authorization('25000000-0000-4000-8000-000000000001');
  perform * from private.provision_tenant_authorization('25000000-0000-4000-8000-000000000002');
end;
$$;

insert into public.tenant_memberships (
  id, tenant_id, user_id, status, joined_at, created_by, profile_id, profile_assigned_at
)
values
  (
    '45000000-0000-4000-8000-000000000001',
    '25000000-0000-4000-8000-000000000001',
    '15000000-0000-4000-8000-000000000001',
    'active',
    statement_timestamp(),
    '15000000-0000-4000-8000-000000000001',
    (select id from public.tenant_profiles where tenant_id = '25000000-0000-4000-8000-000000000001' and template_key = 'manager'),
    statement_timestamp()
  ),
  (
    '45000000-0000-4000-8000-000000000002',
    '25000000-0000-4000-8000-000000000002',
    '15000000-0000-4000-8000-000000000002',
    'active',
    statement_timestamp(),
    '15000000-0000-4000-8000-000000000002',
    (select id from public.tenant_profiles where tenant_id = '25000000-0000-4000-8000-000000000002' and template_key = 'manager'),
    statement_timestamp()
  );

insert into public.tenant_entitlements (
  tenant_id, module_key, enabled, created_by
)
values
  (
    '25000000-0000-4000-8000-000000000001',
    'maintenance',
    true,
    '15000000-0000-4000-8000-000000000001'
  ),
  (
    '25000000-0000-4000-8000-000000000002',
    'maintenance',
    true,
    '15000000-0000-4000-8000-000000000002'
  );

set local "request.jwt.claim.sub" = '15000000-0000-4000-8000-000000000001';
set local "request.jwt.claim.tenant_id" = '25000000-0000-4000-8000-000000000002';
set local "request.jwt.claim.role" = 'forged_platform_admin';
set local role authenticated;

select is(
  (select context_status from public.resolve_my_tenant_context(null)),
  'ready',
  'active principal starts with a valid authoritative context'
);

select is(
  (select count(*) from public.tenants),
  1::bigint,
  'forged JWT tenant and role metadata do not widen RLS'
);

select is(
  (
    select context_status
    from public.resolve_my_tenant_context(
      '35000000-0000-4000-8000-000000000002'
    )
  ),
  'tenant_context_unavailable',
  'another tenant ref is denied'
);

select is(
  (
    select context_status
    from public.resolve_my_tenant_context(
      '35000000-0000-4000-8000-000000000099'
    )
  ),
  'tenant_context_unavailable',
  'an unknown tenant ref is indistinguishable from another tenant'
);

reset role;

update public.app_users
set status = 'blocked', blocked_at = statement_timestamp()
where id = '15000000-0000-4000-8000-000000000001';

set local role authenticated;
select is(
  (select context_status from public.resolve_my_tenant_context(null)),
  'principal_unavailable',
  'blocked app_user is denied while the same JWT remains present'
);
select is((select count(*) from public.tenants), 0::bigint, 'blocked app_user loses tenant RLS access');
reset role;

update public.app_users
set status = 'active', blocked_at = null
where id = '15000000-0000-4000-8000-000000000001';

update public.app_users
set status = 'inactive', inactivated_at = statement_timestamp()
where id = '15000000-0000-4000-8000-000000000001';

set local role authenticated;
select is(
  (select context_status from public.resolve_my_tenant_context(null)),
  'principal_unavailable',
  'inactive app_user is denied while the same JWT remains present'
);
reset role;

update public.app_users
set status = 'active', inactivated_at = null
where id = '15000000-0000-4000-8000-000000000001';

update public.tenant_memberships
set status = 'blocked', blocked_at = statement_timestamp()
where id = '45000000-0000-4000-8000-000000000001';

set local role authenticated;
select is(
  (select context_status from public.resolve_my_tenant_context(null)),
  'membership_unavailable',
  'blocked membership is denied while the same JWT remains present'
);
select is((select count(*) from public.tenants), 0::bigint, 'blocked membership loses tenant RLS access');
reset role;

update public.tenant_memberships
set status = 'active', blocked_at = null
where id = '45000000-0000-4000-8000-000000000001';

update public.tenant_memberships
set status = 'revoked', revoked_at = statement_timestamp()
where id = '45000000-0000-4000-8000-000000000001';

set local role authenticated;
select is(
  (select context_status from public.resolve_my_tenant_context(null)),
  'membership_unavailable',
  'revoked membership is denied while the same JWT remains present'
);
select is((select count(*) from public.tenants), 0::bigint, 'revoked membership loses tenant RLS access');
reset role;

update public.tenant_memberships
set status = 'active', revoked_at = null
where id = '45000000-0000-4000-8000-000000000001';

update public.tenants
set status = 'suspended', suspended_at = statement_timestamp()
where id = '25000000-0000-4000-8000-000000000001';

set local role authenticated;
select is(
  (select context_status from public.resolve_my_tenant_context(null)),
  'tenant_unavailable',
  'suspended tenant is denied while the same JWT remains present'
);
select is((select count(*) from public.tenants), 0::bigint, 'suspended tenant loses RLS visibility');
reset role;

update public.tenants
set status = 'active', suspended_at = null
where id = '25000000-0000-4000-8000-000000000001';

update public.tenants
set status = 'inactive', inactivated_at = statement_timestamp()
where id = '25000000-0000-4000-8000-000000000001';

set local role authenticated;
select is(
  (select context_status from public.resolve_my_tenant_context(null)),
  'tenant_unavailable',
  'inactive tenant is denied while the same JWT remains present'
);
reset role;

update public.tenants
set status = 'active', inactivated_at = null
where id = '25000000-0000-4000-8000-000000000001';

update public.tenant_entitlements
set enabled = false
where tenant_id = '25000000-0000-4000-8000-000000000001'
  and module_key = 'maintenance';

set local role authenticated;
select is(
  (select context_status from public.resolve_my_tenant_context(null)),
  'feature_unavailable',
  'disabled maintenance entitlement invalidates context with the same JWT'
);
select is(
  current_setting('request.jwt.claim.sub', true),
  '15000000-0000-4000-8000-000000000001',
  'authorization was revoked without changing the JWT principal'
);
reset role;

update public.tenant_entitlements
set enabled = true
where tenant_id = '25000000-0000-4000-8000-000000000001'
  and module_key = 'maintenance';

-- Invitation and audit payload hardening.
create temporary table w1e_invitation as
select *
from public.create_tenant_invitation(
  '25000000-0000-4000-8000-000000000001',
  (select id from public.tenant_profiles where tenant_id = '25000000-0000-4000-8000-000000000001' and template_key = 'manager'),
  '  W1E-INVITED@EXAMPLE.INVALID  ',
  statement_timestamp() + interval '1 day',
  '15000000-0000-4000-8000-000000000001',
  '55000000-0000-4000-8000-000000000001'
);

select is(
  (
    select recipient_email_hash
    from public.tenant_invitations
    where invite_ref = (select invite_ref from w1e_invitation)
  ),
  private.sha256_hex('w1e-invited@example.invalid'),
  'invitation persists only the normalized recipient hash'
);

select isnt(
  (
    select token_hash
    from public.tenant_invitations
    where invite_ref = (select invite_ref from w1e_invitation)
  ),
  (select invitation_token from w1e_invitation),
  'raw invitation token is not persisted'
);

select is(
  (
    select count(*)
    from public.audit_events
    where metadata::text like
      '%' || (select invitation_token from w1e_invitation) || '%'
  ),
  0::bigint,
  'raw invitation token is absent from audit metadata'
);

select is(
  (
    select count(*)
    from public.audit_events
    where metadata::text ~* '(password|invitation_token|jwt|service_role|secret)'
  ),
  0::bigint,
  'W1 audit metadata contains no known secret-bearing fields'
);

select throws_ok(
  $$ update public.audit_events set metadata = '{"changed": true}'::jsonb $$,
  '55000',
  'audit_events is append-only',
  'audit events reject UPDATE even through a privileged database path'
);

select throws_ok(
  $$ delete from public.audit_events $$,
  '55000',
  'audit_events is append-only',
  'audit events reject DELETE even through a privileged database path'
);

select throws_ok(
  $$ truncate table public.audit_events $$,
  '55000',
  'audit_events is append-only',
  'audit events reject TRUNCATE even through a privileged database path'
);

set local role authenticated;
select throws_ok(
  $$
    insert into public.audit_events (actor_kind, event_type, entity_type)
    values ('technical', 'forged.event', 'tenant')
  $$,
  '42501',
  null,
  'authenticated cannot forge audit events'
);
reset role;

select * from finish();
rollback;
