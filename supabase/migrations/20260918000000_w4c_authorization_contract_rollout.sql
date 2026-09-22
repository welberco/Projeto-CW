-- W4C.1 - Authorization Contract and Rollout
-- Forward-only permission catalog and baseline rollout for maintenance catalogs.

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
    ) as t(template_key, template_id)
  loop
    if not exists (
      select 1
      from private.authorization_profile_templates as template
      where template.id = expected.template_id
        and template.template_key = expected.template_key
        and template.template_version = 3
        and template.status = 'active'
    ) then
      raise exception using errcode = 'P0001', message = 'W4C_TEMPLATE_BASELINE_MISMATCH';
    end if;
  end loop;
end;
$$;

insert into public.permission_catalog (
  id, code, module_code, resource_code, action_code, scope,
  required_entitlement_key, tenant_delegable, label_key, description_key, status
)
select
  ('95000000-0000-4000-8000-' || pg_catalog.lpad(permission.ordinal::text, 12, '0'))::uuid,
  'maintenance.' || permission.resource_code || '.' || permission.action_code || '.all_tenant',
  'maintenance',
  permission.resource_code,
  permission.action_code,
  'ALL_TENANT'::public.authorization_scope,
  'maintenance',
  true,
  'permissions.maintenance.' || permission.resource_code || '.' || permission.action_code || '.label',
  'permissions.maintenance.' || permission.resource_code || '.' || permission.action_code || '.description',
  'active'
from (values
  ('maintenance_categories','read',1),
  ('maintenance_categories','lookup',2),
  ('maintenance_categories','create',3),
  ('maintenance_categories','update',4),
  ('maintenance_categories','inactivate',5),
  ('maintenance_categories','reactivate',6),
  ('maintenance_subcategories','read',7),
  ('maintenance_subcategories','lookup',8),
  ('maintenance_subcategories','create',9),
  ('maintenance_subcategories','update',10),
  ('maintenance_subcategories','inactivate',11),
  ('maintenance_subcategories','reactivate',12),
  ('maintenance_reasons','read',13),
  ('maintenance_reasons','lookup',14),
  ('maintenance_reasons','create',15),
  ('maintenance_reasons','update',16),
  ('maintenance_reasons','inactivate',17),
  ('maintenance_reasons','reactivate',18),
  ('document_types','read',19),
  ('document_types','lookup',20),
  ('document_types','create',21),
  ('document_types','update',22),
  ('document_types','inactivate',23),
  ('document_types','reactivate',24),
  ('checklist_templates','read',25),
  ('checklist_templates','lookup',26),
  ('checklist_templates','create',27),
  ('checklist_templates','update',28),
  ('checklist_templates','inactivate',29),
  ('checklist_templates','reactivate',30),
  ('catalog_templates','apply',31)
) as permission(resource_code, action_code, ordinal);

insert into private.authorization_profile_template_permissions (template_id, permission_id)
select template.id, permission.id
from (values
  ('manager','maintenance.maintenance_categories.read.all_tenant'),
  ('manager','maintenance.maintenance_categories.lookup.all_tenant'),
  ('manager','maintenance.maintenance_categories.create.all_tenant'),
  ('manager','maintenance.maintenance_categories.update.all_tenant'),
  ('manager','maintenance.maintenance_categories.inactivate.all_tenant'),
  ('manager','maintenance.maintenance_subcategories.read.all_tenant'),
  ('manager','maintenance.maintenance_subcategories.lookup.all_tenant'),
  ('manager','maintenance.maintenance_subcategories.create.all_tenant'),
  ('manager','maintenance.maintenance_subcategories.update.all_tenant'),
  ('manager','maintenance.maintenance_subcategories.inactivate.all_tenant'),
  ('manager','maintenance.maintenance_reasons.read.all_tenant'),
  ('manager','maintenance.maintenance_reasons.lookup.all_tenant'),
  ('manager','maintenance.maintenance_reasons.create.all_tenant'),
  ('manager','maintenance.maintenance_reasons.update.all_tenant'),
  ('manager','maintenance.maintenance_reasons.inactivate.all_tenant'),
  ('manager','maintenance.document_types.read.all_tenant'),
  ('manager','maintenance.document_types.lookup.all_tenant'),
  ('manager','maintenance.checklist_templates.read.all_tenant'),
  ('manager','maintenance.checklist_templates.lookup.all_tenant'),
  ('manager','maintenance.catalog_templates.apply.all_tenant'),
  ('technician','maintenance.maintenance_categories.lookup.all_tenant'),
  ('technician','maintenance.maintenance_subcategories.lookup.all_tenant'),
  ('technician','maintenance.maintenance_reasons.lookup.all_tenant'),
  ('technician','maintenance.document_types.lookup.all_tenant'),
  ('technician','maintenance.checklist_templates.lookup.all_tenant'),
  ('assistant','maintenance.maintenance_categories.lookup.all_tenant'),
  ('assistant','maintenance.maintenance_subcategories.lookup.all_tenant'),
  ('assistant','maintenance.maintenance_reasons.lookup.all_tenant'),
  ('assistant','maintenance.document_types.lookup.all_tenant'),
  ('assistant','maintenance.checklist_templates.lookup.all_tenant'),
  ('requester','maintenance.maintenance_categories.lookup.all_tenant'),
  ('requester','maintenance.maintenance_subcategories.lookup.all_tenant')
) as approved(template_key, permission_code)
join private.authorization_profile_templates as template
  on template.template_key = approved.template_key
join public.permission_catalog as permission
  on permission.code = approved.permission_code
on conflict do nothing;

do $$
declare
  updated_templates integer;
begin
  update private.authorization_profile_templates
  set template_version = 4,
      updated_at = pg_catalog.clock_timestamp()
  where template_key in ('manager','technician','assistant','requester')
    and template_version = 3;

  get diagnostics updated_templates = row_count;
  if updated_templates <> 4 then
    raise exception using errcode = 'P0001', message = 'W4C_TEMPLATE_VERSION_UPDATE_MISMATCH';
  end if;
end;
$$;

create function private.apply_w4c_authorization_rollout(target_tenant_id uuid)
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
      'w4c_maintenance_catalogs_v1', target_tenant_id, profile.id, profile.template_key
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
        and template.template_version = 4
        and permission.module_code = 'maintenance'
        and permission.resource_code in (
          'maintenance_categories', 'maintenance_subcategories',
          'maintenance_reasons', 'document_types', 'checklist_templates',
          'catalog_templates'
        )
      on conflict do nothing;
      get diagnostics added = row_count;
      total_added := total_added + added;

      update private.authorization_profile_rollouts
      set grants_added = added
      where rollout_key = 'w4c_maintenance_catalogs_v1'
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
        'w4c.authorization_rollout',
        profile.id,
        pg_catalog.gen_random_uuid(),
        null,
        1,
        'approved W4C.1 baseline rollout',
        pg_catalog.jsonb_build_object(
          'rollout_key','w4c_maintenance_catalogs_v1',
          'template_key',profile.template_key,
          'grants_added',added
        )
      );
    else
      select rollout.grants_added
      into added
      from private.authorization_profile_rollouts as rollout
      where rollout.rollout_key = 'w4c_maintenance_catalogs_v1'
        and rollout.tenant_id = target_tenant_id
        and rollout.profile_id = profile.id;

      total_added := total_added + added;
    end if;
  end loop;

  return total_added;
end;
$$;

revoke all on function private.apply_w4c_authorization_rollout(uuid)
  from public, anon, authenticated, service_role, cw_worker;
alter function private.apply_w4c_authorization_rollout(uuid) owner to postgres;

do $$
declare
  tenant record;
begin
  for tenant in select id from public.tenants order by id loop
    perform private.apply_w4c_authorization_rollout(tenant.id);
  end loop;
end;
$$;

comment on function private.apply_w4c_authorization_rollout(uuid) is
  'Applies the exact add-only W4C.1 baseline to official tenant profile instances.';
