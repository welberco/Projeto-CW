begin;

set local search_path = public, extensions, pg_catalog;

select no_plan();

select has_table('public', 'app_users', 'app_users exists');
select has_table('public', 'tenants', 'tenants exists');
select has_table('public', 'tenant_memberships', 'tenant_memberships exists');
select has_table('public', 'tenant_invitations', 'tenant_invitations exists');
select has_table('public', 'tenant_entitlements', 'tenant_entitlements exists');
select has_table('public', 'audit_events', 'audit_events exists');

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
  'all W1A public tables have RLS enabled'
);

insert into auth.users (id, aud, role, email, created_at, updated_at)
values
  (
    '10000000-0000-4000-8000-000000000001',
    'authenticated',
    'authenticated',
    'user-a@example.invalid',
    statement_timestamp(),
    statement_timestamp()
  ),
  (
    '10000000-0000-4000-8000-000000000002',
    'authenticated',
    'authenticated',
    'user-b@example.invalid',
    statement_timestamp(),
    statement_timestamp()
  );

select is(
  (select count(*) from public.app_users),
  2::bigint,
  'Auth identity trigger creates exactly one app_user per auth user'
);

insert into public.tenants (
  id,
  tenant_ref,
  display_name,
  status,
  created_by
)
values
  (
    '20000000-0000-4000-8000-000000000001',
    '30000000-0000-4000-8000-000000000001',
    'Tenant A',
    'active',
    '10000000-0000-4000-8000-000000000001'
  ),
  (
    '20000000-0000-4000-8000-000000000002',
    '30000000-0000-4000-8000-000000000002',
    'Tenant B',
    'active',
    '10000000-0000-4000-8000-000000000002'
  );

insert into public.tenant_memberships (
  id,
  tenant_id,
  user_id,
  status,
  joined_at,
  created_by
)
values (
  '40000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  'active',
  statement_timestamp(),
  '10000000-0000-4000-8000-000000000001'
);

select throws_ok(
  $$
    insert into public.tenants (
      tenant_ref,
      display_name,
      status,
      created_by
    ) values (
      '30000000-0000-4000-8000-000000000001',
      'Duplicate Ref',
      'active',
      '10000000-0000-4000-8000-000000000001'
    )
  $$,
  '23505',
  null,
  'tenant_ref is unique'
);

select throws_ok(
  $$
    insert into public.tenants (
      tenant_ref,
      display_name,
      status,
      created_by
    ) values (
      '30000000-0000-3000-8000-000000000003',
      'Invalid Ref Version',
      'active',
      '10000000-0000-4000-8000-000000000001'
    )
  $$,
  '23514',
  null,
  'tenant_ref must be an RFC 4122 UUID v4'
);

select throws_ok(
  $$
    insert into public.tenants (display_name, status, created_by)
    values (
      'Invalid Tenant',
      'unknown',
      '10000000-0000-4000-8000-000000000001'
    )
  $$,
  '23514',
  null,
  'invalid tenant lifecycle is rejected'
);

select throws_ok(
  $$
    insert into public.tenant_memberships (
      tenant_id,
      user_id,
      status,
      joined_at,
      created_by
    ) values (
      '20000000-0000-4000-8000-000000000002',
      '10000000-0000-4000-8000-000000000001',
      'active',
      statement_timestamp(),
      '10000000-0000-4000-8000-000000000001'
    )
  $$,
  '23505',
  null,
  'a second active membership is rejected'
);

select throws_ok(
  $$
    insert into public.tenant_memberships (
      tenant_id,
      user_id,
      status,
      joined_at,
      blocked_at,
      created_by
    ) values (
      '20000000-0000-4000-8000-000000000002',
      '10000000-0000-4000-8000-000000000001',
      'blocked',
      statement_timestamp(),
      statement_timestamp(),
      '10000000-0000-4000-8000-000000000001'
    )
  $$,
  '23505',
  null,
  'blocked also prevents a second operational membership'
);

select throws_ok(
  $$
    insert into public.tenant_memberships (
      tenant_id,
      user_id,
      status,
      joined_at,
      created_by
    ) values (
      '20000000-0000-4000-8000-000000000002',
      '10000000-0000-4000-8000-000000000002',
      'blocked',
      statement_timestamp(),
      '10000000-0000-4000-8000-000000000001'
    )
  $$,
  '23514',
  null,
  'blocked membership requires blocked_at'
);

select throws_ok(
  $$
    insert into public.tenant_memberships (
      tenant_id,
      user_id,
      status,
      joined_at,
      created_by
    ) values (
      '20000000-0000-4000-8000-000000000099',
      '10000000-0000-4000-8000-000000000002',
      'active',
      statement_timestamp(),
      '10000000-0000-4000-8000-000000000001'
    )
  $$,
  '23503',
  null,
  'membership tenant foreign key is enforced'
);

update public.tenant_memberships
set status = 'revoked',
    revoked_at = statement_timestamp()
where id = '40000000-0000-4000-8000-000000000001';

select lives_ok(
  $$
    insert into public.tenant_memberships (
      tenant_id,
      user_id,
      status,
      joined_at,
      created_by
    ) values (
      '20000000-0000-4000-8000-000000000002',
      '10000000-0000-4000-8000-000000000001',
      'active',
      statement_timestamp(),
      '10000000-0000-4000-8000-000000000001'
    )
  $$,
  'a user can join another tenant after its prior membership is revoked'
);

update public.tenant_memberships
set status = 'revoked',
    revoked_at = statement_timestamp()
where user_id = '10000000-0000-4000-8000-000000000001'
  and status = 'active';

select lives_ok(
  $$
    insert into public.tenant_memberships (
      tenant_id,
      user_id,
      status,
      joined_at,
      created_by
    ) values (
      '20000000-0000-4000-8000-000000000001',
      '10000000-0000-4000-8000-000000000001',
      'active',
      statement_timestamp(),
      '10000000-0000-4000-8000-000000000001'
    )
  $$,
  'same-tenant re-entry creates a new row after revocation'
);

select is(
  (
    select count(*)
    from public.tenant_memberships
    where tenant_id = '20000000-0000-4000-8000-000000000001'
      and user_id = '10000000-0000-4000-8000-000000000001'
  ),
  2::bigint,
  'same-tenant re-entry preserves the revoked historical row'
);

insert into public.tenant_invitations (
  tenant_id,
  recipient_email_hash,
  expires_at,
  created_by
)
values (
  '20000000-0000-4000-8000-000000000001',
  repeat('a', 64),
  statement_timestamp() + interval '1 day',
  '10000000-0000-4000-8000-000000000001'
);

select throws_ok(
  $$
    insert into public.tenant_invitations (
      tenant_id,
      recipient_email_hash,
      expires_at,
      created_by
    ) values (
      '20000000-0000-4000-8000-000000000001',
      repeat('a', 64),
      statement_timestamp() + interval '2 days',
      '10000000-0000-4000-8000-000000000001'
    )
  $$,
  '23505',
  null,
  'equivalent pending invitation is unique'
);

select throws_ok(
  $$
    insert into public.tenant_invitations (
      tenant_id,
      recipient_email_hash,
      expires_at,
      created_by
    ) values (
      '20000000-0000-4000-8000-000000000001',
      'not-a-sha256-hash',
      statement_timestamp() + interval '1 day',
      '10000000-0000-4000-8000-000000000001'
    )
  $$,
  '23514',
  null,
  'invitation recipient uses a normalized SHA-256 hash'
);

select throws_ok(
  $$
    insert into public.tenant_invitations (
      tenant_id,
      recipient_email_hash,
      expires_at,
      created_by
    ) values (
      '20000000-0000-4000-8000-000000000001',
      repeat('d', 64),
      statement_timestamp() - interval '1 second',
      '10000000-0000-4000-8000-000000000001'
    )
  $$,
  '23514',
  null,
  'pending invitation must expire after creation'
);

select throws_ok(
  $$
    insert into public.tenant_invitations (
      tenant_id,
      recipient_email_hash,
      status,
      expires_at,
      accepted_at,
      created_by
    ) values (
      '20000000-0000-4000-8000-000000000001',
      repeat('b', 64),
      'accepted',
      statement_timestamp() + interval '1 day',
      statement_timestamp(),
      '10000000-0000-4000-8000-000000000001'
    )
  $$,
  '23514',
  null,
  'accepted invitation requires an invited user'
);

insert into public.tenant_entitlements (
  tenant_id,
  module_key,
  enabled,
  created_by
)
values (
  '20000000-0000-4000-8000-000000000001',
  'maintenance',
  true,
  '10000000-0000-4000-8000-000000000001'
);

select throws_ok(
  $$
    insert into public.tenant_entitlements (
      tenant_id,
      module_key,
      enabled,
      created_by
    ) values (
      '20000000-0000-4000-8000-000000000001',
      'maintenance',
      false,
      '10000000-0000-4000-8000-000000000001'
    )
  $$,
  '23505',
  null,
  'entitlement key is unique per tenant'
);

select throws_ok(
  $$
    insert into public.tenant_entitlements (
      tenant_id,
      module_key,
      enabled,
      created_by
    ) values (
      '20000000-0000-4000-8000-000000000002',
      'Maintenance Admin',
      true,
      '10000000-0000-4000-8000-000000000002'
    )
  $$,
  '23514',
  null,
  'entitlement module key uses a stable lowercase format'
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
  '20000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  'application_user',
  'tenant.created',
  'tenant',
  '20000000-0000-4000-8000-000000000001'
);

select throws_ok(
  $$ update public.audit_events set metadata = '{"changed": true}'::jsonb $$,
  '55000',
  'audit_events is append-only',
  'audit events cannot be updated'
);

select throws_ok(
  $$ delete from public.audit_events $$,
  '55000',
  'audit_events is append-only',
  'audit events cannot be deleted'
);

select * from finish();
rollback;
