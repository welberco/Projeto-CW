-- W4B.1 - Authorization Contract and Rollout
-- Forward-only permission catalog and baseline rollout for Teams and TEAM scope.

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
        and template.template_version = 2
        and template.status = 'active'
    ) then
      raise exception using errcode = 'P0001', message = 'W4B_TEMPLATE_BASELINE_MISMATCH';
    end if;
  end loop;
end;
$$;

insert into public.permission_catalog (
  id, code, module_code, resource_code, action_code, scope,
  required_entitlement_key, tenant_delegable, label_key, description_key, status
)
values
  ('94000000-0000-4000-8000-000000000001','shared.teams.read.team','shared','teams','read','TEAM',null,true,'permissions.shared.teams.read.team.label','permissions.shared.teams.read.team.description','active'),
  ('94000000-0000-4000-8000-000000000002','shared.teams.read.all_tenant','shared','teams','read','ALL_TENANT',null,true,'permissions.shared.teams.read.all_tenant.label','permissions.shared.teams.read.all_tenant.description','active'),
  ('94000000-0000-4000-8000-000000000003','shared.teams.lookup.team','shared','teams','lookup','TEAM',null,true,'permissions.shared.teams.lookup.team.label','permissions.shared.teams.lookup.team.description','active'),
  ('94000000-0000-4000-8000-000000000004','shared.teams.lookup.all_tenant','shared','teams','lookup','ALL_TENANT',null,true,'permissions.shared.teams.lookup.all_tenant.label','permissions.shared.teams.lookup.all_tenant.description','active'),
  ('94000000-0000-4000-8000-000000000005','shared.teams.create.all_tenant','shared','teams','create','ALL_TENANT',null,true,'permissions.shared.teams.create.all_tenant.label','permissions.shared.teams.create.all_tenant.description','active'),
  ('94000000-0000-4000-8000-000000000006','shared.teams.update.all_tenant','shared','teams','update','ALL_TENANT',null,true,'permissions.shared.teams.update.all_tenant.label','permissions.shared.teams.update.all_tenant.description','active'),
  ('94000000-0000-4000-8000-000000000007','shared.teams.inactivate.all_tenant','shared','teams','inactivate','ALL_TENANT',null,true,'permissions.shared.teams.inactivate.all_tenant.label','permissions.shared.teams.inactivate.all_tenant.description','active'),
  ('94000000-0000-4000-8000-000000000008','shared.teams.reactivate.all_tenant','shared','teams','reactivate','ALL_TENANT',null,true,'permissions.shared.teams.reactivate.all_tenant.label','permissions.shared.teams.reactivate.all_tenant.description','active'),
  ('94000000-0000-4000-8000-000000000009','shared.team_memberships.read.all_tenant','shared','team_memberships','read','ALL_TENANT',null,true,'permissions.shared.team_memberships.read.all_tenant.label','permissions.shared.team_memberships.read.all_tenant.description','active'),
  ('94000000-0000-4000-8000-000000000010','shared.team_memberships.add.all_tenant','shared','team_memberships','add','ALL_TENANT',null,true,'permissions.shared.team_memberships.add.all_tenant.label','permissions.shared.team_memberships.add.all_tenant.description','active'),
  ('94000000-0000-4000-8000-000000000011','shared.team_memberships.end.all_tenant','shared','team_memberships','end','ALL_TENANT',null,true,'permissions.shared.team_memberships.end.all_tenant.label','permissions.shared.team_memberships.end.all_tenant.description','active');

insert into private.authorization_profile_template_permissions (template_id, permission_id)
select template.id, permission.id
from (values
  ('manager','shared.teams.read.team'),
  ('manager','shared.teams.read.all_tenant'),
  ('manager','shared.teams.lookup.team'),
  ('manager','shared.teams.lookup.all_tenant'),
  ('manager','shared.teams.create.all_tenant'),
  ('manager','shared.teams.update.all_tenant'),
  ('manager','shared.teams.inactivate.all_tenant'),
  ('manager','shared.team_memberships.read.all_tenant'),
  ('manager','shared.team_memberships.add.all_tenant'),
  ('manager','shared.team_memberships.end.all_tenant'),
  ('technician','shared.teams.read.team'),
  ('technician','shared.teams.lookup.team'),
  ('assistant','shared.teams.read.team'),
  ('assistant','shared.teams.lookup.team'),
  ('requester','shared.teams.lookup.team')
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
  set template_version = 3,
      updated_at = pg_catalog.clock_timestamp()
  where template_key in ('manager','technician','assistant','requester')
    and template_version = 2;

  get diagnostics updated_templates = row_count;
  if updated_templates <> 4 then
    raise exception using errcode = 'P0001', message = 'W4B_TEMPLATE_VERSION_UPDATE_MISMATCH';
  end if;
end;
$$;

create function private.apply_w4b_authorization_rollout(target_tenant_id uuid)
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
      'w4b_team_scope_v1', target_tenant_id, profile.id, profile.template_key
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
        and template.template_version = 3
        and permission.code = any (array[
          'shared.teams.read.team',
          'shared.teams.read.all_tenant',
          'shared.teams.lookup.team',
          'shared.teams.lookup.all_tenant',
          'shared.teams.create.all_tenant',
          'shared.teams.update.all_tenant',
          'shared.teams.inactivate.all_tenant',
          'shared.teams.reactivate.all_tenant',
          'shared.team_memberships.read.all_tenant',
          'shared.team_memberships.add.all_tenant',
          'shared.team_memberships.end.all_tenant'
        ]::text[])
      on conflict do nothing;
      get diagnostics added = row_count;
      total_added := total_added + added;

      update private.authorization_profile_rollouts
      set grants_added = added
      where rollout_key = 'w4b_team_scope_v1'
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
        'w4b.authorization_rollout',
        profile.id,
        pg_catalog.gen_random_uuid(),
        null,
        1,
        'approved W4B.1 baseline rollout',
        pg_catalog.jsonb_build_object(
          'rollout_key','w4b_team_scope_v1',
          'template_key',profile.template_key,
          'grants_added',added
        )
      );
    else
      select rollout.grants_added
      into added
      from private.authorization_profile_rollouts as rollout
      where rollout.rollout_key = 'w4b_team_scope_v1'
        and rollout.tenant_id = target_tenant_id
        and rollout.profile_id = profile.id;

      total_added := total_added + added;
    end if;
  end loop;

  return total_added;
end;
$$;

revoke all on function private.apply_w4b_authorization_rollout(uuid)
  from public, anon, authenticated, service_role, cw_worker;
alter function private.apply_w4b_authorization_rollout(uuid) owner to postgres;

do $$
declare
  tenant record;
begin
  for tenant in select id from public.tenants order by id loop
    perform private.apply_w4b_authorization_rollout(tenant.id);
  end loop;
end;
$$;

comment on function private.apply_w4b_authorization_rollout(uuid) is
  'Applies the exact add-only W4B.1 baseline to official tenant profile instances.';
