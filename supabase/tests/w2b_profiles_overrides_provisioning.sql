begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

create temporary table w2b_expected_template_permissions (
  template_key text not null,
  permission_code text not null,
  source_wave text not null,
  primary key (template_key, permission_code)
);

insert into w2b_expected_template_permissions (template_key, permission_code, source_wave)
values
  ('manager', 'core.users.read.all_tenant', 'W2'),
  ('manager', 'core.users.invite.all_tenant', 'W2'),
  ('manager', 'core.users.assign_profile.all_tenant', 'W2'),
  ('manager', 'core.users.manage_overrides.all_tenant', 'W2'),
  ('manager', 'core.users.change_status.all_tenant', 'W2'),
  ('manager', 'core.profiles.read.all_tenant', 'W2'),
  ('manager', 'core.profiles.create.all_tenant', 'W2'),
  ('manager', 'core.profiles.update.all_tenant', 'W2'),
  ('manager', 'core.profiles.activate.all_tenant', 'W2'),
  ('manager', 'core.profiles.inactivate.all_tenant', 'W2'),
  ('manager', 'core.profiles.change_permissions.all_tenant', 'W2'),
  ('manager', 'shared.location_types.read.all_tenant', 'W4A'),
  ('manager', 'shared.location_types.lookup.all_tenant', 'W4A'),
  ('manager', 'shared.location_types.create.all_tenant', 'W4A'),
  ('manager', 'shared.location_types.update.all_tenant', 'W4A'),
  ('manager', 'shared.location_types.inactivate.all_tenant', 'W4A'),
  ('manager', 'shared.locations.read.all_tenant', 'W4A'),
  ('manager', 'shared.locations.lookup.all_tenant', 'W4A'),
  ('manager', 'shared.locations.create.all_tenant', 'W4A'),
  ('manager', 'shared.locations.update.all_tenant', 'W4A'),
  ('manager', 'shared.locations.move.all_tenant', 'W4A'),
  ('manager', 'shared.locations.inactivate.all_tenant', 'W4A'),
  ('manager', 'shared.cost_centers.read.all_tenant', 'W4A'),
  ('manager', 'shared.cost_centers.lookup.all_tenant', 'W4A'),
  ('manager', 'shared.cost_centers.create.all_tenant', 'W4A'),
  ('manager', 'shared.cost_centers.update.all_tenant', 'W4A'),
  ('manager', 'shared.cost_centers.move.all_tenant', 'W4A'),
  ('manager', 'shared.cost_centers.inactivate.all_tenant', 'W4A'),
  ('manager', 'shared.sectors.read.all_tenant', 'W4A'),
  ('manager', 'shared.sectors.lookup.all_tenant', 'W4A'),
  ('manager', 'shared.sectors.create.all_tenant', 'W4A'),
  ('manager', 'shared.sectors.update.all_tenant', 'W4A'),
  ('manager', 'shared.sectors.inactivate.all_tenant', 'W4A'),
  ('technician', 'shared.locations.lookup.all_tenant', 'W4A'),
  ('technician', 'shared.cost_centers.lookup.all_tenant', 'W4A'),
  ('technician', 'shared.sectors.lookup.all_tenant', 'W4A'),
  ('assistant', 'shared.locations.lookup.all_tenant', 'W4A'),
  ('assistant', 'shared.cost_centers.lookup.all_tenant', 'W4A'),
  ('assistant', 'shared.sectors.lookup.all_tenant', 'W4A'),
  ('requester', 'shared.locations.lookup.all_tenant', 'W4A'),
  ('requester', 'shared.sectors.lookup.all_tenant', 'W4A'),
  ('manager', 'shared.teams.read.team', 'W4B.1'),
  ('manager', 'shared.teams.read.all_tenant', 'W4B.1'),
  ('manager', 'shared.teams.lookup.team', 'W4B.1'),
  ('manager', 'shared.teams.lookup.all_tenant', 'W4B.1'),
  ('manager', 'shared.teams.create.all_tenant', 'W4B.1'),
  ('manager', 'shared.teams.update.all_tenant', 'W4B.1'),
  ('manager', 'shared.teams.inactivate.all_tenant', 'W4B.1'),
  ('manager', 'shared.team_memberships.read.all_tenant', 'W4B.1'),
  ('manager', 'shared.team_memberships.add.all_tenant', 'W4B.1'),
  ('manager', 'shared.team_memberships.end.all_tenant', 'W4B.1'),
  ('technician', 'shared.teams.read.team', 'W4B.1'),
  ('technician', 'shared.teams.lookup.team', 'W4B.1'),
  ('assistant', 'shared.teams.read.team', 'W4B.1'),
  ('assistant', 'shared.teams.lookup.team', 'W4B.1'),
  ('requester', 'shared.teams.lookup.team', 'W4B.1');

select is(
  (
    select count(*)
    from public.permission_catalog
    where code in (
      'shared.locations.use.all_tenant',
      'shared.location_types.use.all_tenant',
      'shared.cost_centers.use.all_tenant',
      'shared.sectors.use.all_tenant'
    )
  ),
  0::bigint,
  'the four removed generic W4A use permissions remain absent'
);

-- Physical model and closed client surface.
select has_table('public', 'tenant_profiles', 'tenant profiles exist');
select has_table('public', 'tenant_profile_permissions', 'tenant profile baseline exists');
select has_table('public', 'tenant_permission_overrides', 'membership overrides exist');
select has_column('public', 'tenant_memberships', 'profile_id', 'membership carries its assigned profile');
select has_column('public', 'tenant_memberships', 'profile_assigned_at', 'membership records profile assignment time');
select has_column('public', 'tenant_memberships', 'profile_assigned_by', 'membership records the assigning actor');
select has_column('public', 'tenant_invitations', 'target_profile_id', 'invitation carries an explicit target profile');

select is(
  (
    select count(*)
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname in (
        'tenant_profiles',
        'tenant_profile_permissions',
        'tenant_permission_overrides'
      )
      and relation.relrowsecurity
  ),
  3::bigint,
  'all W2B public tables have RLS enabled'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename in (
        'tenant_profiles',
        'tenant_profile_permissions',
        'tenant_permission_overrides'
      )
  ),
  0::bigint,
  'W2B tables have no client policies before W2C'
);

select is(
  (
    select count(*)
    from information_schema.table_privileges
    where table_schema = 'public'
      and table_name in (
        'tenant_profiles',
        'tenant_profile_permissions',
        'tenant_permission_overrides'
      )
      and grantee in ('PUBLIC', 'anon', 'authenticated', 'service_role')
  ),
  0::bigint,
  'PUBLIC, client roles and service_role have no direct W2B table grants'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace on namespace.oid = relation.relnamespace
    join pg_catalog.pg_roles as owner_role on owner_role.oid = relation.relowner
    where namespace.nspname = 'public'
      and relation.relname in (
        'tenant_profiles',
        'tenant_profile_permissions',
        'tenant_permission_overrides'
      )
      and owner_role.rolname in ('anon', 'authenticated', 'service_role')
  ),
  0::bigint,
  'W2B table owners are not client-facing roles'
);

select is(
  has_function_privilege(
    'service_role',
    'private.provision_tenant_authorization(uuid,uuid,uuid,uuid)',
    'EXECUTE'
  ),
  false,
  'private provisioning is not directly exposed to service_role'
);

select is(
  has_function_privilege(
    'authenticated',
    'public.create_tenant_invitation(uuid,uuid,text,timestamptz,uuid,uuid)',
    'EXECUTE'
  ),
  false,
  'authenticated invitation administration remains closed until W2C'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.create_tenant_invitation(uuid,uuid,text,timestamptz,uuid,uuid)',
    'EXECUTE'
  ),
  'the existing controlled ops invitation command uses the profile-aware signature'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'private'
      and procedure.proname in (
        'provision_tenant_authorization',
        'protect_tenant_profile_mutation',
        'protect_tenant_profile_permission_mutation',
        'bump_tenant_profile_version_for_baseline',
        'protect_tenant_permission_override_mutation',
        'bump_membership_version_for_override',
        'enforce_membership_profile_integrity',
        'enforce_invitation_target_profile_integrity'
      )
      and not exists (
        select 1
        from pg_catalog.unnest(coalesce(procedure.proconfig, array[]::text[])) as configuration(setting)
        where pg_catalog.split_part(configuration.setting, '=', 1) = 'search_path'
          and pg_catalog.replace(pg_catalog.split_part(configuration.setting, '=', 2), '"', '') = ''
      )
  ),
  0::bigint,
  'all W2B private functions fix an empty search_path'
);

select ok(
  pg_catalog.pg_get_functiondef(
    'private.enforce_membership_profile_integrity()'::regprocedure
  ) like '%for key share%',
  'profile assignment locks the active profile against concurrent inactivation'
);

-- Bootstrap and copy-once provisioning.
insert into auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
values
  ('16000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'w2b-manager@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp()),
  ('16000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'w2b-technician@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp()),
  ('16000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'w2b-legacy@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp()),
  ('16000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'w2b-unassigned@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp()),
  ('16000000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'w2b-inactive-profile@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp());

create temporary table w2b_bootstrap as
select *
from public.bootstrap_initial_tenant(
  '16000000-0000-4000-8000-000000000001',
  'W2B Tenant',
  '56000000-0000-4000-8000-000000000001'
);

select is((select count(*) from public.tenant_profiles), 4::bigint, 'bootstrap creates exactly four tenant-owned profiles');
select is(
  (
    select array_agg(profile.template_key order by profile.template_key)
    from public.tenant_profiles as profile
  ),
  array['assistant', 'manager', 'requester', 'technician']::text[],
  'the exact approved template keys are copied'
);
select is(
  (
    select array_agg(profile.name order by profile.template_key)
    from public.tenant_profiles as profile
  ),
  array['Auxiliar', 'Gestor', 'Solicitante', 'Técnico']::text[],
  'the approved default names are copied as editable display data'
);
select is(
  (
    select count(*)
    from public.tenant_profiles as profile
    join private.authorization_profile_templates as template
      on template.template_key = profile.template_key
     and template.template_version = profile.template_version
    where profile.status = 'active' and template.status = 'active'
  ),
  4::bigint,
  'tenant profiles retain authoritative current system-template provenance'
);
select is(
  (
    select count(*)
    from public.tenant_profile_permissions as baseline
    join public.tenant_profiles as profile on profile.id = baseline.profile_id
    join public.permission_catalog as permission on permission.id = baseline.permission_id
    join w2b_expected_template_permissions as expected
      on expected.template_key = profile.template_key
     and expected.permission_code = permission.code
    where profile.template_key = 'manager' and expected.source_wave = 'W2'
  ),
  11::bigint,
  'Gestor retains every approved W2 administrative baseline grant'
);
select is(
  (
    select count(*)
    from public.tenant_profile_permissions as baseline
    join public.tenant_profiles as profile on profile.id = baseline.profile_id
    join public.permission_catalog as permission on permission.id = baseline.permission_id
    join w2b_expected_template_permissions as expected
      on expected.template_key = profile.template_key
     and expected.permission_code = permission.code
    where profile.template_key in ('technician', 'assistant', 'requester')
      and expected.source_wave = 'W2'
  ),
  0::bigint,
  'Técnico, Auxiliar and Solicitante receive no W2 administrative grants'
);
select is(
  (
    select count(*)
    from (
      select profile.template_key, permission.code
      from public.tenant_profile_permissions as baseline
      join public.tenant_profiles as profile on profile.id = baseline.profile_id
      join public.permission_catalog as permission on permission.id = baseline.permission_id
      where profile.template_key is not null
      except
      select template_key, permission_code from w2b_expected_template_permissions
    ) as unexpected
  ),
  0::bigint,
  'official profiles receive no permission outside the explicit W2, W4A and W4B.1 allowlists'
);
select is(
  (
    select count(*)
    from (
      select template_key, permission_code from w2b_expected_template_permissions
      except
      select profile.template_key, permission.code
      from public.tenant_profile_permissions as baseline
      join public.tenant_profiles as profile on profile.id = baseline.profile_id
      join public.permission_catalog as permission on permission.id = baseline.permission_id
      where profile.template_key is not null
    ) as missing
  ),
  0::bigint,
  'official profiles receive every permission explicitly approved by W2, W4A and W4B.1'
);
select is(
  private.apply_w4a_authorization_rollout((select tenant_id from w2b_bootstrap)),
  0,
  'W4A rollout records already-current profiles without adding duplicate grants'
);
select is(
  (select count(*) from private.authorization_profile_rollouts where tenant_id = (select tenant_id from w2b_bootstrap) and rollout_key = 'w4_catalog_baseline_v1'),
  4::bigint,
  'W4A rollout provenance is recorded once per authoritative system profile'
);
select is(
  private.apply_w4a_authorization_rollout((select tenant_id from w2b_bootstrap)),
  0,
  'W4A rollout replay is idempotent'
);
select is(
  (
    select profile.template_key
    from public.tenant_memberships as membership
    join public.tenant_profiles as profile on profile.id = membership.profile_id
    where membership.user_id = '16000000-0000-4000-8000-000000000001'
  ),
  'manager',
  'bootstrap membership is explicitly assigned to Gestor'
);
select is(
  (
    select profile_assigned_by
    from public.tenant_memberships
    where user_id = '16000000-0000-4000-8000-000000000001'
  ),
  '16000000-0000-4000-8000-000000000001'::uuid,
  'bootstrap profile assignment records its authoritative actor'
);
select is(
  (
    select count(*)
    from public.audit_events
    where event_type = 'authorization.tenant_provisioned'
      and tenant_id = (select tenant_id from w2b_bootstrap)
  ),
  1::bigint,
  'initial provisioning emits one audit event without a competing audit framework'
);

create temporary table w2b_profile_snapshot as
select id, name, version
from public.tenant_profiles;

create temporary table w2b_retry as
select *
from private.provision_tenant_authorization(
  (select tenant_id from w2b_bootstrap),
  (select id from public.tenant_memberships where user_id = '16000000-0000-4000-8000-000000000001'),
  '16000000-0000-4000-8000-000000000001',
  '56000000-0000-4000-8000-000000000002'
);

select is((select profiles_created from w2b_retry), 0, 'provisioning retry creates no duplicate profile');
select is((select grants_created from w2b_retry), 0, 'provisioning retry creates no duplicate grant');
select is((select bootstrap_membership_assigned from w2b_retry), false, 'provisioning retry does not rewrite an assigned membership');
select is(
  (
    select count(*)
    from public.tenant_profiles as profile
    join w2b_profile_snapshot as snapshot
      on snapshot.id = profile.id and snapshot.version = profile.version
  ),
  4::bigint,
  'no-op provisioning retry preserves every profile revision'
);
select is(
  (
    select count(*)
    from public.audit_events
    where event_type = 'authorization.tenant_provisioned'
      and tenant_id = (select tenant_id from w2b_bootstrap)
  ),
  1::bigint,
  'no-op provisioning retry emits no duplicate audit event'
);

-- Tenant customization is not overwritten by provisioning retry.
update public.tenant_profiles
set name = 'Gestor local',
    updated_by = '16000000-0000-4000-8000-000000000001'
where tenant_id = (select tenant_id from w2b_bootstrap)
  and template_key = 'manager';

select is(
  (
    select count(*)
    from public.tenant_profile_permissions as baseline
    join public.tenant_profiles as profile on profile.id = baseline.profile_id
    join public.permission_catalog as permission on permission.id = baseline.permission_id
    join w2b_expected_template_permissions as expected
      on expected.permission_code = permission.code
     and expected.template_key = profile.template_key
    where profile.tenant_id = (select tenant_id from w2b_bootstrap)
      and profile.template_key = 'manager'
      and expected.source_wave = 'W2'
  ),
  11::bigint,
  'renaming Gestor does not change its W2 baseline because the name is not authority'
);

delete from public.tenant_profile_permissions
where profile_id = (
    select id from public.tenant_profiles
    where tenant_id = (select tenant_id from w2b_bootstrap)
      and template_key = 'manager'
  )
  and permission_id = '91000000-0000-4000-8000-000000000001';

do $$
begin
  perform *
  from private.provision_tenant_authorization(
    (select tenant_id from w2b_bootstrap), null, null,
    '56000000-0000-4000-8000-000000000003'
  );
end;
$$;

select is(
  (
    select name from public.tenant_profiles
    where tenant_id = (select tenant_id from w2b_bootstrap)
      and template_key = 'manager'
  ),
  'Gestor local',
  'provisioning retry preserves a tenant-local profile rename'
);
select is(
  (
    select count(*) from public.tenant_profile_permissions
    where profile_id = (
        select id from public.tenant_profiles
        where tenant_id = (select tenant_id from w2b_bootstrap)
          and template_key = 'manager'
      )
      and permission_id = '91000000-0000-4000-8000-000000000001'
  ),
  0::bigint,
  'provisioning retry does not restore a tenant-removed baseline grant'
);

insert into public.permission_catalog (
  id, code, module_code, resource_code, action_code, scope,
  tenant_delegable, label_key
)
values (
  '96000000-0000-4000-8000-000000000001',
  'core.users.update.own', 'core', 'users', 'update', 'OWN',
  true, 'authorization.permissions.w2b_test.label'
);

do $$
begin
  perform *
  from private.provision_tenant_authorization(
    (select tenant_id from w2b_bootstrap), null, null,
    '56000000-0000-4000-8000-000000000004'
  );
end;
$$;

select is(
  (
    select count(*)
    from public.tenant_profile_permissions
    where permission_id = '96000000-0000-4000-8000-000000000001'
  ),
  0::bigint,
  'a future catalog permission is not auto-granted to an existing tenant profile'
);

-- Profile identity, lifecycle, baseline isolation and revisions.
insert into public.tenant_profiles (
  id, tenant_id, name, status, created_by, updated_by
)
values (
  '96000000-0000-4000-8000-000000000010',
  (select tenant_id from w2b_bootstrap),
  'Perfil customizado',
  'active',
  '16000000-0000-4000-8000-000000000001',
  '16000000-0000-4000-8000-000000000001'
);

select is(
  private.apply_w4a_authorization_rollout((select tenant_id from w2b_bootstrap)),
  0,
  'W4A rollout replay remains a no-op after a custom profile is created'
);
select is(
  (
    select count(*)
    from public.tenant_profile_permissions
    where profile_id = '96000000-0000-4000-8000-000000000010'
  ),
  0::bigint,
  'custom profiles receive no silent W2, W4A or W4B.1 baseline grant'
);

select throws_ok(
  $$
    insert into public.tenant_profiles (tenant_id, name)
    values ((select tenant_id from w2b_bootstrap), 'PERFIL CUSTOMIZADO')
  $$,
  '23505',
  null,
  'active profile names are unique per tenant after normalization'
);

select throws_ok(
  $$
    update public.tenant_profiles
    set tenant_id = '26000000-0000-4000-8000-000000000099'
    where id = '96000000-0000-4000-8000-000000000010'
  $$,
  '23514',
  'TENANT_PROFILE_IDENTITY_IMMUTABLE',
  'profile tenant identity is immutable'
);

select throws_ok(
  $$ delete from public.tenant_profiles where id = '96000000-0000-4000-8000-000000000010' $$,
  '23514',
  'TENANT_PROFILE_DELETE_FORBIDDEN',
  'tenant profiles cannot be hard deleted'
);

select throws_ok(
  $$
    update public.tenant_profiles
    set status = 'inactive', inactivated_at = statement_timestamp()
    where tenant_id = (select tenant_id from w2b_bootstrap)
      and template_key = 'manager'
  $$,
  '23514',
  'TENANT_PROFILE_ASSIGNED_TO_OPERATIONAL_MEMBERSHIP',
  'an operationally assigned profile cannot be inactivated'
);

create temporary table w2b_custom_version as
select version
from public.tenant_profiles
where id = '96000000-0000-4000-8000-000000000010';

update public.tenant_profiles
set name = 'Perfil customizado renomeado',
    updated_by = '16000000-0000-4000-8000-000000000001'
where id = '96000000-0000-4000-8000-000000000010';

select is(
  (select version from public.tenant_profiles where id = '96000000-0000-4000-8000-000000000010'),
  (select version + 1 from w2b_custom_version),
  'profile revision advances once for a protected aggregate change'
);

create temporary table w2b_baseline_version as
select version
from public.tenant_profiles
where id = '96000000-0000-4000-8000-000000000010';

insert into public.tenant_profile_permissions (
  tenant_id, profile_id, permission_id, created_by
)
values (
  (select tenant_id from w2b_bootstrap),
  '96000000-0000-4000-8000-000000000010',
  '91000000-0000-4000-8000-000000000001',
  '16000000-0000-4000-8000-000000000001'
);

select is(
  (select version from public.tenant_profiles where id = '96000000-0000-4000-8000-000000000010'),
  (select version + 1 from w2b_baseline_version),
  'adding one baseline grant advances the profile revision exactly once'
);

select throws_ok(
  $$
    insert into public.tenant_profile_permissions (tenant_id, profile_id, permission_id)
    values (
      (select tenant_id from w2b_bootstrap),
      '96000000-0000-4000-8000-000000000010',
      '91000000-0000-4000-8000-000000000001'
    )
  $$,
  '23505',
  null,
  'duplicate profile and permission baseline is rejected'
);

select throws_ok(
  $$
    update public.tenant_profile_permissions
    set permission_id = '91000000-0000-4000-8000-000000000002'
    where profile_id = '96000000-0000-4000-8000-000000000010'
  $$,
  '23514',
  'TENANT_PROFILE_PERMISSION_IDENTITY_IMMUTABLE',
  'baseline grant identity cannot be rewritten'
);

insert into public.tenants (
  id, tenant_ref, display_name, status, created_by
)
values (
  '26000000-0000-4000-8000-000000000002',
  '36000000-0000-4000-8000-000000000002',
  'W2B Tenant B',
  'active',
  '16000000-0000-4000-8000-000000000001'
);

do $$
begin
  perform *
  from private.provision_tenant_authorization(
    '26000000-0000-4000-8000-000000000002', null, null,
    '56000000-0000-4000-8000-000000000005'
  );
end;
$$;

select isnt(
  (
    select id from public.tenant_profiles
    where tenant_id = (select tenant_id from w2b_bootstrap)
      and template_key = 'manager'
  ),
  (
    select id from public.tenant_profiles
    where tenant_id = '26000000-0000-4000-8000-000000000002'
      and template_key = 'manager'
  ),
  'each tenant receives a distinct operational profile identity'
);
select is(
  (
    select name from public.tenant_profiles
    where tenant_id = '26000000-0000-4000-8000-000000000002'
      and template_key = 'manager'
  ),
  'Gestor',
  'renaming Tenant A Gestor does not rename Tenant B Gestor'
);
select is(
  (
    select count(*)
    from public.tenant_profile_permissions as baseline
    join public.tenant_profiles as profile on profile.id = baseline.profile_id
    where profile.tenant_id = '26000000-0000-4000-8000-000000000002'
      and profile.template_key = 'manager'
      and baseline.permission_id = '91000000-0000-4000-8000-000000000001'
  ),
  1::bigint,
  'removing Tenant A baseline does not alter Tenant B baseline'
);
select is(
  (
    select count(*)
    from information_schema.columns
    where table_schema = 'private'
      and table_name = 'authorization_profile_templates'
      and column_name = 'tenant_id'
  ),
  0::bigint,
  'private platform templates remain separate from runtime tenant profiles'
);

select throws_ok(
  $$
    insert into public.tenant_profile_permissions (tenant_id, profile_id, permission_id)
    values (
      '26000000-0000-4000-8000-000000000002',
      '96000000-0000-4000-8000-000000000010',
      '91000000-0000-4000-8000-000000000002'
    )
  $$,
  '23503',
  null,
  'a cross-tenant profile baseline is rejected by the composite key'
);

update public.permission_catalog
set status = 'deprecated', deprecated_at = statement_timestamp()
where id = '96000000-0000-4000-8000-000000000001';

select throws_ok(
  $$
    insert into public.tenant_profile_permissions (tenant_id, profile_id, permission_id)
    values (
      (select tenant_id from w2b_bootstrap),
      '96000000-0000-4000-8000-000000000010',
      '96000000-0000-4000-8000-000000000001'
    )
  $$,
  '23514',
  'TENANT_PROFILE_PERMISSION_NOT_ACTIVE',
  'a deprecated catalog entry cannot receive a new baseline grant'
);

update public.tenant_profiles
set status = 'inactive',
    inactivated_at = statement_timestamp(),
    updated_by = '16000000-0000-4000-8000-000000000001'
where id = '96000000-0000-4000-8000-000000000010';

select is(
  (select status from public.tenant_profiles where id = '96000000-0000-4000-8000-000000000010'),
  'inactive',
  'an unassigned profile can be inactivated without losing history'
);

select throws_ok(
  $$
    insert into public.tenant_memberships (
      tenant_id, user_id, status, joined_at, created_by,
      profile_id, profile_assigned_at
    ) values (
      (select tenant_id from w2b_bootstrap),
      '16000000-0000-4000-8000-000000000005',
      'active', statement_timestamp(),
      '16000000-0000-4000-8000-000000000001',
      '96000000-0000-4000-8000-000000000010',
      statement_timestamp()
    )
  $$,
  '23514',
  'MEMBERSHIP_PROFILE_NOT_ACTIVE',
  'an inactive profile cannot be assigned to a new operational membership'
);

-- Membership assignment and sparse override precedence representation.
select throws_ok(
  $$
    insert into public.tenant_memberships (
      tenant_id, user_id, status, joined_at, created_by
    ) values (
      (select tenant_id from w2b_bootstrap),
      '16000000-0000-4000-8000-000000000004',
      'active', statement_timestamp(),
      '16000000-0000-4000-8000-000000000001'
    )
  $$,
  '23514',
  null,
  'an operational membership requires an explicit profile'
);

select lives_ok(
  $$
    insert into public.tenant_memberships (
      id, tenant_id, user_id, status, joined_at, revoked_at, created_by
    ) values (
      '46000000-0000-4000-8000-000000000004',
      (select tenant_id from w2b_bootstrap),
      '16000000-0000-4000-8000-000000000004',
      'revoked', statement_timestamp(), statement_timestamp(),
      '16000000-0000-4000-8000-000000000001'
    )
  $$,
  'historical revoked membership may retain a null pre-W2 profile'
);

select throws_ok(
  $$
    update public.tenant_memberships
    set status = 'active',
        revoked_at = null,
        profile_id = (
          select id from public.tenant_profiles
          where tenant_id = '26000000-0000-4000-8000-000000000002'
            and template_key = 'manager'
        ),
        profile_assigned_at = statement_timestamp()
    where id = '46000000-0000-4000-8000-000000000004'
  $$,
  '23503',
  null,
  'membership cannot receive a profile from another tenant'
);

create temporary table w2b_membership_version_before_assignment as
select version
from public.tenant_memberships
where id = '46000000-0000-4000-8000-000000000004';

update public.tenant_memberships
set status = 'active',
    revoked_at = null,
    profile_id = (
      select id from public.tenant_profiles
      where tenant_id = (select tenant_id from w2b_bootstrap)
        and template_key = 'technician'
    ),
    profile_assigned_at = statement_timestamp(),
    profile_assigned_by = '16000000-0000-4000-8000-000000000001'
where id = '46000000-0000-4000-8000-000000000004';

select is(
  (select version from public.tenant_memberships where id = '46000000-0000-4000-8000-000000000004'),
  (select version + 1 from w2b_membership_version_before_assignment),
  'profile assignment advances membership revision exactly once'
);

create temporary table w2b_membership_version_before_override as
select version
from public.tenant_memberships
where id = '46000000-0000-4000-8000-000000000004';

insert into public.tenant_permission_overrides (
  id, tenant_id, membership_id, permission_id, effect, created_by, updated_by
)
values (
  '96000000-0000-4000-8000-000000000020',
  (select tenant_id from w2b_bootstrap),
  '46000000-0000-4000-8000-000000000004',
  '91000000-0000-4000-8000-000000000001',
  'allow',
  '16000000-0000-4000-8000-000000000001',
  '16000000-0000-4000-8000-000000000001'
);

select is(
  (select version from public.tenant_memberships where id = '46000000-0000-4000-8000-000000000004'),
  (select version + 1 from w2b_membership_version_before_override),
  'adding one override advances membership revision exactly once'
);

select ok(
  (
    select case override.effect
      when 'deny' then false
      when 'allow' then true
      else exists (
        select 1
        from public.tenant_profile_permissions as baseline
        where baseline.profile_id = membership.profile_id
          and baseline.permission_id = '91000000-0000-4000-8000-000000000001'
      )
    end
    from public.tenant_memberships as membership
    left join public.tenant_permission_overrides as override
      on override.membership_id = membership.id
     and override.permission_id = '91000000-0000-4000-8000-000000000001'
    where membership.id = '46000000-0000-4000-8000-000000000004'
  ),
  'explicit ALLOW overrides an empty Técnico baseline in the W2B representation'
);

create temporary table w2b_override_version as
select version
from public.tenant_permission_overrides
where id = '96000000-0000-4000-8000-000000000020';

update public.tenant_permission_overrides
set effect = 'deny',
    updated_by = '16000000-0000-4000-8000-000000000001'
where id = '96000000-0000-4000-8000-000000000020';

select is(
  (select version from public.tenant_permission_overrides where id = '96000000-0000-4000-8000-000000000020'),
  (select version + 1 from w2b_override_version),
  'override revision advances once when ALLOW changes to DENY'
);

select is(
  (
    select case override.effect
      when 'deny' then false
      when 'allow' then true
      else null
    end
    from public.tenant_permission_overrides as override
    where override.id = '96000000-0000-4000-8000-000000000020'
  ),
  false,
  'explicit DENY has precedence in the stored override representation'
);

select throws_ok(
  $$
    insert into public.tenant_permission_overrides (
      tenant_id, membership_id, permission_id, effect
    ) values (
      (select tenant_id from w2b_bootstrap),
      '46000000-0000-4000-8000-000000000004',
      '91000000-0000-4000-8000-000000000001',
      'allow'
    )
  $$,
  '23505',
  null,
  'only one sparse override exists per membership and permission'
);

select throws_ok(
  $$
    insert into public.tenant_permission_overrides (
      tenant_id, membership_id, permission_id, effect
    ) values (
      '26000000-0000-4000-8000-000000000002',
      '46000000-0000-4000-8000-000000000004',
      '91000000-0000-4000-8000-000000000002',
      'allow'
    )
  $$,
  '23503',
  null,
  'override cannot cross tenant and membership boundaries'
);

select throws_ok(
  $$
    insert into public.tenant_permission_overrides (
      tenant_id, membership_id, permission_id, effect
    ) values (
      (select tenant_id from w2b_bootstrap),
      '46000000-0000-4000-8000-000000000004',
      '96000000-0000-4000-8000-000000000001',
      'deny'
    )
  $$,
  '23514',
  'TENANT_PERMISSION_OVERRIDE_PERMISSION_NOT_ACTIVE',
  'a deprecated catalog entry cannot receive a new override'
);

create temporary table w2b_membership_version_before_delete as
select version
from public.tenant_memberships
where id = '46000000-0000-4000-8000-000000000004';

delete from public.tenant_permission_overrides
where id = '96000000-0000-4000-8000-000000000020';

select is(
  (select version from public.tenant_memberships where id = '46000000-0000-4000-8000-000000000004'),
  (select version + 1 from w2b_membership_version_before_delete),
  'removing an override returns to inheritance and advances membership revision once'
);
select is(
  (
    select count(*)
    from public.tenant_permission_overrides
    where membership_id = '46000000-0000-4000-8000-000000000004'
      and permission_id = '91000000-0000-4000-8000-000000000001'
  ),
  0::bigint,
  'override absence represents inheritance'
);

-- Invitation profile target and acceptance copy semantics.
create temporary table w2b_invitation as
select *
from public.create_tenant_invitation(
  (select tenant_id from w2b_bootstrap),
  (
    select id from public.tenant_profiles
    where tenant_id = (select tenant_id from w2b_bootstrap)
      and template_key = 'technician'
  ),
  'w2b-technician@example.invalid',
  statement_timestamp() + interval '1 day',
  '16000000-0000-4000-8000-000000000001',
  '56000000-0000-4000-8000-000000000006'
);
grant select on w2b_invitation to authenticated;

select is(
  (
    select profile.template_key
    from public.tenant_invitations as invitation
    join public.tenant_profiles as profile on profile.id = invitation.target_profile_id
    where invitation.invite_ref = (select invite_ref from w2b_invitation)
  ),
  'technician',
  'invitation persists the explicit target profile'
);

select throws_ok(
  $$
    select *
    from public.create_tenant_invitation(
      (select tenant_id from w2b_bootstrap),
      (
        select id from public.tenant_profiles
        where tenant_id = '26000000-0000-4000-8000-000000000002'
          and template_key = 'manager'
      ),
      'cross-tenant@example.invalid',
      statement_timestamp() + interval '1 day',
      '16000000-0000-4000-8000-000000000001',
      pg_catalog.gen_random_uuid()
    )
  $$,
  'P0001',
  'INVITATION_PROFILE_UNAVAILABLE',
  'invitation rejects a profile from another tenant'
);

select throws_ok(
  $$
    insert into public.tenant_invitations (
      tenant_id, recipient_email_hash, expires_at, created_by
    ) values (
      (select tenant_id from w2b_bootstrap), repeat('d', 64),
      statement_timestamp() + interval '1 day',
      '16000000-0000-4000-8000-000000000001'
    )
  $$,
  '23514',
  'PENDING_INVITATION_PROFILE_REQUIRED',
  'new pending invitations cannot omit their target profile'
);

select throws_ok(
  $$
    update public.tenant_invitations
    set target_profile_id = (
      select id from public.tenant_profiles
      where tenant_id = (select tenant_id from w2b_bootstrap)
        and template_key = 'assistant'
    )
    where invite_ref = (select invite_ref from w2b_invitation)
  $$,
  '23514',
  'INVITATION_TARGET_PROFILE_IMMUTABLE',
  'invitation target profile cannot be switched after creation'
);

set local role authenticated;
set local "request.jwt.claim.sub" = '16000000-0000-4000-8000-000000000002';
select lives_ok(
  format(
    'select * from public.accept_tenant_invitation(%L, %L)',
    (select invitation_token from w2b_invitation),
    '56000000-0000-4000-8000-000000000007'
  ),
  'the intended principal accepts the profile-aware invitation'
);
reset role;

select is(
  (
    select profile.template_key
    from public.tenant_memberships as membership
    join public.tenant_profiles as profile on profile.id = membership.profile_id
    where membership.user_id = '16000000-0000-4000-8000-000000000002'
      and membership.status = 'active'
  ),
  'technician',
  'acceptance copies the invitation target profile to the membership'
);
select is(
  (
    select profile_assigned_by
    from public.tenant_memberships
    where user_id = '16000000-0000-4000-8000-000000000002'
      and status = 'active'
  ),
  '16000000-0000-4000-8000-000000000001'::uuid,
  'accepted assignment preserves the inviter as assignment authority'
);

alter table public.tenant_invitations disable trigger tenant_invitations_enforce_target_profile_integrity;
insert into public.tenant_invitations (
  tenant_id, recipient_email_hash, token_hash, expires_at, created_by
)
values (
  (select tenant_id from w2b_bootstrap),
  private.sha256_hex('w2b-legacy@example.invalid'),
  private.sha256_hex(repeat('e', 64)),
  statement_timestamp() + interval '1 day',
  '16000000-0000-4000-8000-000000000001'
);
alter table public.tenant_invitations enable trigger tenant_invitations_enforce_target_profile_integrity;

set local role authenticated;
set local "request.jwt.claim.sub" = '16000000-0000-4000-8000-000000000003';
select throws_ok(
  $$ select * from public.accept_tenant_invitation(repeat('e', 64), pg_catalog.gen_random_uuid()) $$,
  'P0001',
  'INVITATION_UNAVAILABLE',
  'a legacy pending invitation without target profile fails closed'
);
reset role;

-- Closed W2B data surface and explicit deferral of W2C-W2E.
set local role authenticated;
set local "request.jwt.claim.sub" = '16000000-0000-4000-8000-000000000001';
select throws_ok(
  $$ select * from public.tenant_profiles $$,
  '42501', null,
  'authenticated cannot directly read tenant profiles before W2C'
);
select throws_ok(
  $$ select * from public.tenant_profile_permissions $$,
  '42501', null,
  'authenticated cannot directly read tenant baseline before W2C'
);
select throws_ok(
  $$ select * from public.tenant_permission_overrides $$,
  '42501', null,
  'authenticated cannot directly read membership overrides before W2C'
);
select throws_ok(
  $$
    insert into public.tenant_profiles (tenant_id, name)
    values ('26000000-0000-4000-8000-000000000002', 'Forged profile')
  $$,
  '42501', null,
  'authenticated cannot mutate tenant profiles directly'
);
reset role;

select is(
  (
    select count(*)
    from pg_catalog.pg_proc as procedure
    join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname in ('public', 'private')
      and procedure.proname in (
        'authorize_action',
        'evaluate_permission',
        'project_authorization'
      )
  ),
  0::bigint,
  'W2C evaluator and W2D projection functions remain absent'
);
select is(to_regclass('public.authorization_projection'), null::regclass, 'W2D authorization projection remains absent');

select * from finish();
rollback;
