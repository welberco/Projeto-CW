-- W5A - Asset and Storage authorization contract and rollout.
-- Forward-only catalog extension; no Asset or Storage domain object is created here.

do $$
declare
  expected record;
begin
  for expected in
    select * from (values
      ('manager','92000000-0000-4000-8000-000000000001'::uuid),
      ('technician','92000000-0000-4000-8000-000000000002'::uuid),
      ('assistant','92000000-0000-4000-8000-000000000003'::uuid),
      ('requester','92000000-0000-4000-8000-000000000004'::uuid)
    ) as approved(template_key, template_id)
  loop
    if not exists (
      select 1
      from private.authorization_profile_templates as template
      where template.id = expected.template_id
        and template.template_key = expected.template_key
        and template.template_version = 4
        and template.status = 'active'
    ) then
      raise exception using
        errcode = 'P0001',
        message = 'W5A_TEMPLATE_BASELINE_MISMATCH';
    end if;
  end loop;
end;
$$;

do $$
declare
  proposed record;
begin
  for proposed in
    select * from (values
      ('97000000-0000-4000-8000-000000000001'::uuid,'shared.asset_types.read.all_tenant'),
      ('97000000-0000-4000-8000-000000000002'::uuid,'shared.asset_types.lookup.all_tenant'),
      ('97000000-0000-4000-8000-000000000003'::uuid,'shared.asset_types.create.all_tenant'),
      ('97000000-0000-4000-8000-000000000004'::uuid,'shared.asset_types.update.all_tenant'),
      ('97000000-0000-4000-8000-000000000005'::uuid,'shared.asset_types.inactivate.all_tenant'),
      ('97000000-0000-4000-8000-000000000006'::uuid,'shared.asset_types.reactivate.all_tenant'),
      ('97000000-0000-4000-8000-000000000007'::uuid,'shared.assets.read.all_tenant'),
      ('97000000-0000-4000-8000-000000000008'::uuid,'shared.assets.lookup.all_tenant'),
      ('97000000-0000-4000-8000-000000000009'::uuid,'shared.assets.create.all_tenant'),
      ('97000000-0000-4000-8000-000000000010'::uuid,'shared.assets.update.all_tenant'),
      ('97000000-0000-4000-8000-000000000011'::uuid,'shared.assets.move.all_tenant'),
      ('97000000-0000-4000-8000-000000000012'::uuid,'shared.assets.inactivate.all_tenant'),
      ('97000000-0000-4000-8000-000000000013'::uuid,'shared.assets.reactivate.all_tenant'),
      ('97000000-0000-4000-8000-000000000014'::uuid,'shared.assets.decommission.all_tenant'),
      ('97000000-0000-4000-8000-000000000015'::uuid,'shared.asset_files.read.all_tenant'),
      ('97000000-0000-4000-8000-000000000016'::uuid,'shared.asset_files.reserve.all_tenant'),
      ('97000000-0000-4000-8000-000000000017'::uuid,'shared.asset_files.finalize.all_tenant'),
      ('97000000-0000-4000-8000-000000000018'::uuid,'shared.asset_files.delete.all_tenant'),
      ('97000000-0000-4000-8000-000000000019'::uuid,'shared.asset_files.retry.all_tenant')
    ) as permission(id, code)
  loop
    if exists (
      select 1 from public.permission_catalog as existing
      where (existing.id = proposed.id and existing.code <> proposed.code)
         or (existing.code = proposed.code and existing.id <> proposed.id)
    ) then
      raise exception using
        errcode = 'P0001',
        message = 'W5A_PERMISSION_ID_OR_CODE_COLLISION';
    end if;
  end loop;

  if exists (
    select 1
    from public.permission_catalog as existing
    where existing.resource_code in ('asset_types','assets','asset_files')
      and existing.code <> all (array[
        'shared.asset_types.read.all_tenant',
        'shared.asset_types.lookup.all_tenant',
        'shared.asset_types.create.all_tenant',
        'shared.asset_types.update.all_tenant',
        'shared.asset_types.inactivate.all_tenant',
        'shared.asset_types.reactivate.all_tenant',
        'shared.assets.read.all_tenant',
        'shared.assets.lookup.all_tenant',
        'shared.assets.create.all_tenant',
        'shared.assets.update.all_tenant',
        'shared.assets.move.all_tenant',
        'shared.assets.inactivate.all_tenant',
        'shared.assets.reactivate.all_tenant',
        'shared.assets.decommission.all_tenant',
        'shared.asset_files.read.all_tenant',
        'shared.asset_files.reserve.all_tenant',
        'shared.asset_files.finalize.all_tenant',
        'shared.asset_files.delete.all_tenant',
        'shared.asset_files.retry.all_tenant'
      ]::text[])
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'W5A_UNAPPROVED_ASSET_PERMISSION_PRESENT';
  end if;
end;
$$;

insert into public.permission_catalog (
  id, code, module_code, resource_code, action_code, scope,
  required_entitlement_key, tenant_delegable, label_key, description_key, status
)
select
  ('97000000-0000-4000-8000-' || pg_catalog.lpad(permission.ordinal::text, 12, '0'))::uuid,
  'shared.' || permission.resource_code || '.' || permission.action_code || '.all_tenant',
  'shared',
  permission.resource_code,
  permission.action_code,
  'ALL_TENANT'::public.authorization_scope,
  null,
  true,
  'permissions.shared.' || permission.resource_code || '.' || permission.action_code || '.label',
  'permissions.shared.' || permission.resource_code || '.' || permission.action_code || '.description',
  'active'
from (values
  ('asset_types','read',1),
  ('asset_types','lookup',2),
  ('asset_types','create',3),
  ('asset_types','update',4),
  ('asset_types','inactivate',5),
  ('asset_types','reactivate',6),
  ('assets','read',7),
  ('assets','lookup',8),
  ('assets','create',9),
  ('assets','update',10),
  ('assets','move',11),
  ('assets','inactivate',12),
  ('assets','reactivate',13),
  ('assets','decommission',14),
  ('asset_files','read',15),
  ('asset_files','reserve',16),
  ('asset_files','finalize',17),
  ('asset_files','delete',18),
  ('asset_files','retry',19)
) as permission(resource_code, action_code, ordinal);

insert into private.authorization_profile_template_permissions (template_id, permission_id)
select template.id, permission.id
from (values
  ('manager','shared.asset_types.read.all_tenant'),
  ('manager','shared.asset_types.lookup.all_tenant'),
  ('manager','shared.asset_types.create.all_tenant'),
  ('manager','shared.asset_types.update.all_tenant'),
  ('manager','shared.asset_types.inactivate.all_tenant'),
  ('manager','shared.asset_types.reactivate.all_tenant'),
  ('manager','shared.assets.read.all_tenant'),
  ('manager','shared.assets.lookup.all_tenant'),
  ('manager','shared.assets.create.all_tenant'),
  ('manager','shared.assets.update.all_tenant'),
  ('manager','shared.assets.move.all_tenant'),
  ('manager','shared.assets.inactivate.all_tenant'),
  ('manager','shared.assets.reactivate.all_tenant'),
  ('manager','shared.assets.decommission.all_tenant'),
  ('manager','shared.asset_files.read.all_tenant'),
  ('manager','shared.asset_files.reserve.all_tenant'),
  ('manager','shared.asset_files.finalize.all_tenant'),
  ('manager','shared.asset_files.delete.all_tenant'),
  ('manager','shared.asset_files.retry.all_tenant'),
  ('technician','shared.asset_types.lookup.all_tenant'),
  ('technician','shared.assets.read.all_tenant'),
  ('technician','shared.assets.lookup.all_tenant'),
  ('technician','shared.asset_files.read.all_tenant'),
  ('technician','shared.asset_files.reserve.all_tenant'),
  ('technician','shared.asset_files.finalize.all_tenant'),
  ('technician','shared.asset_files.retry.all_tenant'),
  ('assistant','shared.asset_types.lookup.all_tenant'),
  ('assistant','shared.assets.read.all_tenant'),
  ('assistant','shared.assets.lookup.all_tenant'),
  ('assistant','shared.asset_files.read.all_tenant'),
  ('requester','shared.assets.lookup.all_tenant')
) as approved(template_key, permission_code)
join private.authorization_profile_templates as template
  on template.template_key = approved.template_key
join public.permission_catalog as permission
  on permission.code = approved.permission_code
on conflict do nothing;

do $$
declare
  mapping_count integer;
  updated_templates integer;
begin
  select pg_catalog.count(*)::integer
  into mapping_count
  from private.authorization_profile_template_permissions as mapping
  join private.authorization_profile_templates as template on template.id = mapping.template_id
  join public.permission_catalog as permission on permission.id = mapping.permission_id
  where template.template_key in ('manager','technician','assistant','requester')
    and permission.resource_code in ('asset_types','assets','asset_files');

  if mapping_count <> 31 then
    raise exception using errcode = 'P0001', message = 'W5A_TEMPLATE_MAPPING_COUNT_MISMATCH';
  end if;

  update private.authorization_profile_templates
  set template_version = 5,
      updated_at = pg_catalog.clock_timestamp()
  where template_key in ('manager','technician','assistant','requester')
    and template_version = 4;

  get diagnostics updated_templates = row_count;
  if updated_templates <> 4 then
    raise exception using errcode = 'P0001', message = 'W5A_TEMPLATE_VERSION_UPDATE_MISMATCH';
  end if;
end;
$$;

create function private.apply_w5a_authorization_rollout(target_tenant_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  profile record;
  added integer;
  total_added integer := 0;
  inserted_ledger integer;
begin
  if target_tenant_id is null then
    raise exception using errcode = '22023', message = 'TENANT_REQUIRED';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(target_tenant_id::text, 0)
  );

  for profile in
    select tenant_profile.id, tenant_profile.template_key
    from public.tenant_profiles as tenant_profile
    where tenant_profile.tenant_id = target_tenant_id
      and tenant_profile.template_key in ('manager','technician','assistant','requester')
    order by tenant_profile.id
    for update
  loop
    insert into private.authorization_profile_rollouts (
      rollout_key, tenant_id, profile_id, template_key
    ) values (
      'w5a_assets_storage_v1', target_tenant_id, profile.id, profile.template_key
    )
    on conflict do nothing;
    get diagnostics inserted_ledger = row_count;

    if inserted_ledger = 1 then
      insert into public.tenant_profile_permissions (
        tenant_id, profile_id, permission_id, created_by
      )
      select target_tenant_id, profile.id, mapping.permission_id, null
      from private.authorization_profile_templates as template
      join private.authorization_profile_template_permissions as mapping
        on mapping.template_id = template.id
      join public.permission_catalog as permission
        on permission.id = mapping.permission_id
      where template.template_key = profile.template_key
        and template.template_version = 5
        and permission.module_code = 'shared'
        and permission.resource_code in ('asset_types','assets','asset_files')
      on conflict do nothing;
      get diagnostics added = row_count;
      total_added := total_added + added;

      update private.authorization_profile_rollouts
      set grants_added = added
      where rollout_key = 'w5a_assets_storage_v1'
        and tenant_id = target_tenant_id
        and profile_id = profile.id;

      perform private.append_audit(
        target_tenant_id,
        'technical',
        'authorization.profile.baseline_rolled_out',
        'tenant_profile',
        pg_catalog.gen_random_uuid(),
        'migration',
        null,
        'w5a.authorization_rollout',
        profile.id,
        pg_catalog.gen_random_uuid(),
        null,
        1,
        'approved W5A baseline rollout',
        pg_catalog.jsonb_build_object(
          'rollout_key','w5a_assets_storage_v1',
          'template_key',profile.template_key,
          'grants_added',added
        )
      );
    else
      select rollout.grants_added
      into added
      from private.authorization_profile_rollouts as rollout
      where rollout.rollout_key = 'w5a_assets_storage_v1'
        and rollout.tenant_id = target_tenant_id
        and rollout.profile_id = profile.id;

      total_added := total_added + added;
    end if;
  end loop;

  return total_added;
end;
$$;

revoke all on function private.apply_w5a_authorization_rollout(uuid)
  from public, anon, authenticated, service_role, cw_worker;
alter function private.apply_w5a_authorization_rollout(uuid) owner to postgres;

do $$
declare
  tenant record;
begin
  for tenant in select id from public.tenants order by id loop
    perform private.apply_w5a_authorization_rollout(tenant.id);
  end loop;
end;
$$;

comment on function private.apply_w5a_authorization_rollout(uuid) is
  'Applies the exact add-only W5A Asset and Storage baseline to official tenant profile instances.';
