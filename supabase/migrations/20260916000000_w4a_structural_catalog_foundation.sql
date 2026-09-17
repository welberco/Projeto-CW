-- W4A - Structural Catalog Foundation
-- Forward-only foundation for location types, locations, cost centers and sectors.

create table private.authorization_profile_rollouts (
  rollout_key text not null,
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  profile_id uuid not null,
  template_key text not null,
  grants_added integer not null default 0,
  applied_at timestamptz not null default pg_catalog.clock_timestamp(),
  constraint authorization_profile_rollouts_pk primary key (rollout_key, tenant_id, profile_id),
  constraint authorization_profile_rollouts_template_uq unique (rollout_key, tenant_id, template_key),
  constraint authorization_profile_rollouts_profile_fk foreign key (tenant_id, profile_id)
    references public.tenant_profiles (tenant_id, id) on delete restrict,
  constraint authorization_profile_rollouts_key_ck check (rollout_key ~ '^[a-z][a-z0-9_]{2,63}$'),
  constraint authorization_profile_rollouts_template_ck check (template_key ~ '^[a-z][a-z0-9_]{1,63}$'),
  constraint authorization_profile_rollouts_grants_ck check (grants_added >= 0)
);

alter table private.authorization_profile_rollouts enable row level security;
alter table private.authorization_profile_rollouts force row level security;
revoke all on table private.authorization_profile_rollouts from public, anon, authenticated, service_role, cw_worker;

insert into public.permission_catalog (
  id, code, module_code, resource_code, action_code, scope,
  required_entitlement_key, tenant_delegable, label_key, description_key, status
)
select
  ('93000000-0000-4000-8000-' || pg_catalog.lpad(ordinal::text, 12, '0'))::uuid,
  'shared.' || resource_code || '.' || action_code || '.all_tenant',
  'shared', resource_code, action_code, 'ALL_TENANT'::public.authorization_scope,
  null, true,
  'permissions.shared.' || resource_code || '.' || action_code || '.label',
  'permissions.shared.' || resource_code || '.' || action_code || '.description',
  'active'
from (
  values
    ('location_types','read',1), ('location_types','lookup',2),
    ('location_types','create',4), ('location_types','update',5),
    ('location_types','inactivate',6), ('location_types','reactivate',7),
    ('locations','read',8), ('locations','lookup',9),
    ('locations','create',11), ('locations','update',12), ('locations','move',13),
    ('locations','inactivate',14), ('locations','reactivate',15),
    ('cost_centers','read',16), ('cost_centers','lookup',17),
    ('cost_centers','create',19), ('cost_centers','update',20), ('cost_centers','move',21),
    ('cost_centers','inactivate',22), ('cost_centers','reactivate',23),
    ('sectors','read',24), ('sectors','lookup',25),
    ('sectors','create',27), ('sectors','update',28),
    ('sectors','inactivate',29), ('sectors','reactivate',30)
) as permission(resource_code, action_code, ordinal)
order by ordinal;

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
      select 1 from private.authorization_profile_templates template
      where template.id = expected.template_id
        and template.template_key = expected.template_key
        and template.template_version = 1
        and template.status = 'active'
    ) then
      raise exception using errcode = 'P0001', message = 'W4A_TEMPLATE_BASELINE_MISMATCH';
    end if;
  end loop;
end;
$$;

insert into private.authorization_profile_template_permissions (template_id, permission_id)
select template.id, permission.id
from private.authorization_profile_templates template
join public.permission_catalog permission on permission.module_code = 'shared'
where
  (template.template_key = 'manager' and (
    permission.action_code in ('read','lookup','create','update','inactivate')
    or (permission.resource_code in ('locations','cost_centers') and permission.action_code = 'move')
  ))
  or (template.template_key in ('technician','assistant')
      and permission.resource_code in ('locations','cost_centers','sectors')
      and permission.action_code = 'lookup')
  or (template.template_key = 'requester'
      and permission.resource_code in ('locations','sectors')
      and permission.action_code = 'lookup')
on conflict do nothing;

update private.authorization_profile_templates
set template_version = 2, updated_at = pg_catalog.clock_timestamp()
where template_key in ('manager','technician','assistant','requester')
  and template_version = 1;

create function private.apply_w4a_authorization_rollout(target_tenant_id uuid)
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
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(target_tenant_id::text, 0));

  for profile in
    select p.id, p.template_key
    from public.tenant_profiles p
    where p.tenant_id = target_tenant_id
      and p.template_key in ('manager','technician','assistant','requester')
    order by p.id
    for update
  loop
    insert into private.authorization_profile_rollouts (
      rollout_key, tenant_id, profile_id, template_key
    ) values ('w4_catalog_baseline_v1', target_tenant_id, profile.id, profile.template_key)
    on conflict do nothing;
    get diagnostics inserted_ledger = row_count;

    if inserted_ledger = 1 then
      insert into public.tenant_profile_permissions (tenant_id, profile_id, permission_id, created_by)
      select target_tenant_id, profile.id, mapping.permission_id, null
      from private.authorization_profile_templates template
      join private.authorization_profile_template_permissions mapping on mapping.template_id = template.id
      where template.template_key = profile.template_key
        and template.template_version = 2
        and exists (
          select 1 from public.permission_catalog permission
          where permission.id = mapping.permission_id and permission.module_code = 'shared'
        )
      on conflict do nothing;
      get diagnostics added = row_count;
      total_added := total_added + added;

      update private.authorization_profile_rollouts
      set grants_added = added
      where rollout_key = 'w4_catalog_baseline_v1'
        and tenant_id = target_tenant_id and profile_id = profile.id;

      perform private.append_audit(
        target_tenant_id,
        'technical',
        'authorization.profile.baseline_rolled_out',
        'tenant_profile',
        pg_catalog.gen_random_uuid(),
        'migration',
        null,
        'w4a.authorization_rollout',
        profile.id,
        pg_catalog.gen_random_uuid(),
        null,
        1,
        'approved W4A baseline rollout',
        pg_catalog.jsonb_build_object(
          'rollout_key','w4_catalog_baseline_v1',
          'template_key',profile.template_key,
          'grants_added',added
        )
      );
    else
      select rollout.grants_added into added
      from private.authorization_profile_rollouts rollout
      where rollout.rollout_key = 'w4_catalog_baseline_v1'
        and rollout.tenant_id = target_tenant_id
        and rollout.profile_id = profile.id;
      total_added := total_added + added;
    end if;
  end loop;
  return total_added;
end;
$$;
revoke all on function private.apply_w4a_authorization_rollout(uuid)
  from public, anon, authenticated, service_role, cw_worker;
alter function private.apply_w4a_authorization_rollout(uuid) owner to postgres;

do $$
declare tenant record;
begin
  for tenant in select id from public.tenants order by id loop
    perform private.apply_w4a_authorization_rollout(tenant.id);
  end loop;
end;
$$;

create table public.location_types (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  code text not null,
  name text not null,
  description text,
  status text not null default 'active',
  version bigint not null default 1,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  updated_at timestamptz not null default pg_catalog.clock_timestamp(),
  created_by uuid not null references public.app_users (id) on delete restrict,
  updated_by uuid not null references public.app_users (id) on delete restrict,
  inactivated_at timestamptz,
  constraint location_types_tenant_id_id_uq unique (tenant_id,id),
  constraint location_types_code_ck check (code = pg_catalog.btrim(code) and code ~ '^[A-Za-z0-9][A-Za-z0-9._/-]{0,63}$'),
  constraint location_types_name_ck check (name = pg_catalog.btrim(name) and pg_catalog.char_length(name) between 1 and 160),
  constraint location_types_description_ck check (description is null or (description = pg_catalog.btrim(description) and pg_catalog.char_length(description) <= 2000)),
  constraint location_types_status_ck check (status in ('active','inactive')),
  constraint location_types_version_ck check (version > 0),
  constraint location_types_lifecycle_ck check ((status='active' and inactivated_at is null) or (status='inactive' and inactivated_at is not null))
);
create unique index location_types_tenant_code_uq on public.location_types (tenant_id, pg_catalog.lower(code));
create index location_types_tenant_status_name_idx on public.location_types (tenant_id,status,name);

create table public.locations (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  location_type_id uuid not null,
  parent_id uuid,
  code text,
  name text not null,
  description text,
  status text not null default 'active',
  version bigint not null default 1,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  updated_at timestamptz not null default pg_catalog.clock_timestamp(),
  created_by uuid not null references public.app_users (id) on delete restrict,
  updated_by uuid not null references public.app_users (id) on delete restrict,
  inactivated_at timestamptz,
  constraint locations_tenant_id_id_uq unique (tenant_id,id),
  constraint locations_type_fk foreign key (tenant_id,location_type_id) references public.location_types (tenant_id,id) on delete restrict,
  constraint locations_parent_fk foreign key (tenant_id,parent_id) references public.locations (tenant_id,id) on delete restrict,
  constraint locations_not_self_ck check (parent_id is null or parent_id <> id),
  constraint locations_code_ck check (code is null or (code = pg_catalog.btrim(code) and code ~ '^[A-Za-z0-9][A-Za-z0-9._/-]{0,63}$')),
  constraint locations_name_ck check (name = pg_catalog.btrim(name) and pg_catalog.char_length(name) between 1 and 160),
  constraint locations_description_ck check (description is null or (description = pg_catalog.btrim(description) and pg_catalog.char_length(description) <= 2000)),
  constraint locations_status_ck check (status in ('active','inactive')),
  constraint locations_version_ck check (version > 0),
  constraint locations_lifecycle_ck check ((status='active' and inactivated_at is null) or (status='inactive' and inactivated_at is not null))
);
create unique index locations_tenant_code_uq on public.locations (tenant_id, pg_catalog.lower(code)) where code is not null;
create index locations_tenant_parent_idx on public.locations (tenant_id,parent_id);
create index locations_tenant_status_name_idx on public.locations (tenant_id,status,name);

create table public.cost_centers (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  parent_id uuid,
  code text not null,
  name text not null,
  description text,
  status text not null default 'active',
  version bigint not null default 1,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  updated_at timestamptz not null default pg_catalog.clock_timestamp(),
  created_by uuid not null references public.app_users (id) on delete restrict,
  updated_by uuid not null references public.app_users (id) on delete restrict,
  inactivated_at timestamptz,
  constraint cost_centers_tenant_id_id_uq unique (tenant_id,id),
  constraint cost_centers_parent_fk foreign key (tenant_id,parent_id) references public.cost_centers (tenant_id,id) on delete restrict,
  constraint cost_centers_not_self_ck check (parent_id is null or parent_id <> id),
  constraint cost_centers_code_ck check (code = pg_catalog.btrim(code) and code ~ '^[A-Za-z0-9][A-Za-z0-9._/-]{0,63}$'),
  constraint cost_centers_name_ck check (name = pg_catalog.btrim(name) and pg_catalog.char_length(name) between 1 and 160),
  constraint cost_centers_description_ck check (description is null or (description = pg_catalog.btrim(description) and pg_catalog.char_length(description) <= 2000)),
  constraint cost_centers_status_ck check (status in ('active','inactive')),
  constraint cost_centers_version_ck check (version > 0),
  constraint cost_centers_lifecycle_ck check ((status='active' and inactivated_at is null) or (status='inactive' and inactivated_at is not null))
);
create unique index cost_centers_tenant_code_uq on public.cost_centers (tenant_id, pg_catalog.lower(code));
create index cost_centers_tenant_parent_idx on public.cost_centers (tenant_id,parent_id);
create index cost_centers_tenant_status_name_idx on public.cost_centers (tenant_id,status,name);

create table public.sectors (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  code text,
  name text not null,
  description text,
  status text not null default 'active',
  version bigint not null default 1,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  updated_at timestamptz not null default pg_catalog.clock_timestamp(),
  created_by uuid not null references public.app_users (id) on delete restrict,
  updated_by uuid not null references public.app_users (id) on delete restrict,
  inactivated_at timestamptz,
  constraint sectors_tenant_id_id_uq unique (tenant_id,id),
  constraint sectors_code_ck check (code is null or (code = pg_catalog.btrim(code) and code ~ '^[A-Za-z0-9][A-Za-z0-9._/-]{0,63}$')),
  constraint sectors_name_ck check (name = pg_catalog.btrim(name) and pg_catalog.char_length(name) between 1 and 160),
  constraint sectors_description_ck check (description is null or (description = pg_catalog.btrim(description) and pg_catalog.char_length(description) <= 2000)),
  constraint sectors_status_ck check (status in ('active','inactive')),
  constraint sectors_version_ck check (version > 0),
  constraint sectors_lifecycle_ck check ((status='active' and inactivated_at is null) or (status='inactive' and inactivated_at is not null))
);
create unique index sectors_tenant_code_uq on public.sectors (tenant_id, pg_catalog.lower(code)) where code is not null;
create index sectors_tenant_status_name_idx on public.sectors (tenant_id,status,name);

create function private.protect_w4a_catalog_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '42501', message = 'STRUCTURAL_CATALOG_DELETE_FORBIDDEN';
  end if;
  if new.id <> old.id or new.tenant_id <> old.tenant_id
     or new.created_at <> old.created_at or new.created_by <> old.created_by
     or new.version <> old.version then
    raise exception using errcode = '42501', message = 'STRUCTURAL_CATALOG_PROTECTED_FIELD';
  end if;
  return new;
end;
$$;
revoke all on function private.protect_w4a_catalog_mutation() from public, anon, authenticated, service_role, cw_worker;

do $$
declare table_name text;
begin
  foreach table_name in array array['location_types','locations','cost_centers','sectors'] loop
    execute pg_catalog.format(
      'create trigger %I before update or delete on public.%I for each row execute function private.protect_w4a_catalog_mutation()',
      table_name || '_protect_mutation', table_name
    );
    execute pg_catalog.format(
      'create trigger %I before update on public.%I for each row execute function private.set_updated_at_and_version()',
      table_name || '_set_updated_at_and_version', table_name
    );
    execute pg_catalog.format('alter table public.%I enable row level security', table_name);
    execute pg_catalog.format('alter table public.%I force row level security', table_name);
    execute pg_catalog.format('revoke all on table public.%I from public, anon, authenticated, service_role, cw_worker', table_name);
    execute pg_catalog.format('grant select on table public.%I to authenticated', table_name);
  end loop;
end;
$$;

create function private.can_access_w4a_catalog(
  target_tenant_id uuid,
  target_resource_code text,
  target_action_code text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.tenant_memberships membership
    join public.app_users app_user on app_user.id = membership.user_id and app_user.status = 'active'
    join public.tenants tenant on tenant.id = membership.tenant_id and tenant.status = 'active'
    join public.tenant_profiles profile on profile.id = membership.profile_id
      and profile.tenant_id = membership.tenant_id and profile.status = 'active'
    where membership.user_id = auth.uid()
      and membership.tenant_id = target_tenant_id
      and membership.status = 'active'
      and private.has_effective_permission(
        target_resource_code, target_action_code, 'ALL_TENANT'::public.authorization_scope
      )
  );
$$;
revoke all on function private.can_access_w4a_catalog(uuid,text,text) from public, anon, authenticated, service_role, cw_worker;
alter function private.can_access_w4a_catalog(uuid,text,text) owner to postgres;

create function private.assert_w4a_catalog_access(target_resource_code text, target_action_code text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare target_tenant_id uuid;
begin
  select membership.tenant_id into target_tenant_id
  from public.tenant_memberships membership
  where membership.user_id = auth.uid() and membership.status = 'active';
  if target_tenant_id is null
     or not private.can_access_w4a_catalog(target_tenant_id,target_resource_code,target_action_code) then
    raise exception using errcode = '42501', message = 'AUTHORIZATION_DENIED';
  end if;
  return target_tenant_id;
end;
$$;
revoke all on function private.assert_w4a_catalog_access(text,text) from public, anon, authenticated, service_role, cw_worker;
alter function private.assert_w4a_catalog_access(text,text) owner to postgres;

create policy location_types_read on public.location_types for select to authenticated
using (private.can_access_w4a_catalog(tenant_id,'location_types','read'));
create policy locations_read on public.locations for select to authenticated
using (private.can_access_w4a_catalog(tenant_id,'locations','read'));
create policy cost_centers_read on public.cost_centers for select to authenticated
using (private.can_access_w4a_catalog(tenant_id,'cost_centers','read'));
create policy sectors_read on public.sectors for select to authenticated
using (private.can_access_w4a_catalog(tenant_id,'sectors','read'));

create function private.execute_w4a_catalog_command(
  target_resource text,
  target_action text,
  target_id uuid,
  expected_version bigint,
  target_code text,
  target_name text,
  target_description text,
  target_parent_id uuid,
  target_location_type_id uuid,
  command_reason text,
  command_correlation_id uuid,
  command_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor record;
  idem record;
  fingerprint bytea;
  entity_id uuid := coalesce(target_id, pg_catalog.gen_random_uuid());
  correlation_id uuid := coalesce(command_correlation_id, pg_catalog.gen_random_uuid());
  command_name text := 'cadastros.' || target_action || '_' || pg_catalog.rtrim(target_resource, 's');
  aggregate_type text;
  event_type text;
  event_action text;
  entity_version bigint;
  entity_status text;
  entity_code text;
  entity_name text;
  entity_parent_id uuid;
  entity_location_type_id uuid;
  result jsonb;
begin
  if target_resource not in ('location_types','locations','cost_centers','sectors')
     or target_action not in ('create','update','move','inactivate','reactivate')
     or (target_action = 'move' and target_resource not in ('locations','cost_centers')) then
    raise exception using errcode = '22023', message = 'INVALID_STRUCTURAL_CATALOG_COMMAND';
  end if;
  if command_reason is null or command_reason <> pg_catalog.btrim(command_reason)
     or pg_catalog.char_length(command_reason) not between 1 and 500 then
    raise exception using errcode = '22023', message = 'INVALID_COMMAND_REASON';
  end if;

  select * into actor from private.lock_authorization_actor(target_resource,target_action);
  if target_resource in ('locations','cost_centers') then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(actor.actor_tenant_id::text || ':' || target_resource, 0)
    );
  end if;

  fingerprint := private.semantic_fingerprint(pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
    'resource',target_resource,'action',target_action,'id',target_id,
    'expected_version',expected_version,'code',target_code,'name',target_name,
    'description',target_description,'parent_id',target_parent_id,
    'location_type_id',target_location_type_id
  )));
  select * into idem from private.acquire_command_idempotency(
    actor.actor_tenant_id,'application_user','user_command',command_name,
    command_idempotency_key,fingerprint,actor.actor_user_id,null,null
  );
  if idem.replayed then return idem.stored_result; end if;

  aggregate_type := case target_resource
    when 'location_types' then 'location_type'
    when 'locations' then 'location'
    when 'cost_centers' then 'cost_center'
    when 'sectors' then 'sector' end;
  event_action := case target_action when 'create' then 'created' when 'update' then 'updated'
    when 'move' then 'moved' when 'inactivate' then 'inactivated' else 'reactivated' end;
  event_type := 'cadastros.' || aggregate_type || '.' || event_action;

  if target_action = 'create' then
    if target_name is null or target_name <> pg_catalog.btrim(target_name) then
      raise exception using errcode = '22023', message = 'INVALID_CATALOG_NAME';
    end if;
    if target_resource in ('location_types','cost_centers') and target_code is null then
      raise exception using errcode = '22023', message = 'CATALOG_CODE_REQUIRED';
    end if;
    if target_resource = 'location_types' then
      insert into public.location_types(id,tenant_id,code,name,description,created_by,updated_by)
      values(entity_id,actor.actor_tenant_id,target_code,target_name,target_description,actor.actor_user_id,actor.actor_user_id)
      returning version,status,code,name into entity_version,entity_status,entity_code,entity_name;
    elsif target_resource = 'locations' then
      if not exists (select 1 from public.location_types t where t.tenant_id=actor.actor_tenant_id and t.id=target_location_type_id and t.status='active') then
        raise exception using errcode='P0001', message='LOCATION_TYPE_UNAVAILABLE';
      end if;
      if target_parent_id is not null and not exists (select 1 from public.locations p where p.tenant_id=actor.actor_tenant_id and p.id=target_parent_id and p.status='active') then
        raise exception using errcode='P0001', message='LOCATION_PARENT_UNAVAILABLE';
      end if;
      insert into public.locations(id,tenant_id,location_type_id,parent_id,code,name,description,created_by,updated_by)
      values(entity_id,actor.actor_tenant_id,target_location_type_id,target_parent_id,target_code,target_name,target_description,actor.actor_user_id,actor.actor_user_id)
      returning version,status,code,name,parent_id,location_type_id into entity_version,entity_status,entity_code,entity_name,entity_parent_id,entity_location_type_id;
    elsif target_resource = 'cost_centers' then
      if target_parent_id is not null and not exists (select 1 from public.cost_centers p where p.tenant_id=actor.actor_tenant_id and p.id=target_parent_id and p.status='active') then
        raise exception using errcode='P0001', message='COST_CENTER_PARENT_UNAVAILABLE';
      end if;
      insert into public.cost_centers(id,tenant_id,parent_id,code,name,description,created_by,updated_by)
      values(entity_id,actor.actor_tenant_id,target_parent_id,target_code,target_name,target_description,actor.actor_user_id,actor.actor_user_id)
      returning version,status,code,name,parent_id into entity_version,entity_status,entity_code,entity_name,entity_parent_id;
    else
      insert into public.sectors(id,tenant_id,code,name,description,created_by,updated_by)
      values(entity_id,actor.actor_tenant_id,target_code,target_name,target_description,actor.actor_user_id,actor.actor_user_id)
      returning version,status,code,name into entity_version,entity_status,entity_code,entity_name;
    end if;
  elsif target_action = 'update' then
    if target_id is null or expected_version is null or target_name is null then
      raise exception using errcode='22023', message='INVALID_UPDATE_INPUT';
    end if;
    if target_resource = 'location_types' then
      update public.location_types set code=target_code,name=target_name,description=target_description,updated_by=actor.actor_user_id
      where tenant_id=actor.actor_tenant_id and id=target_id and version=expected_version and status='active'
      returning version,status,code,name into entity_version,entity_status,entity_code,entity_name;
    elsif target_resource = 'locations' then
      if not exists (select 1 from public.location_types t where t.tenant_id=actor.actor_tenant_id and t.id=target_location_type_id and t.status='active') then
        raise exception using errcode='P0001', message='LOCATION_TYPE_UNAVAILABLE';
      end if;
      update public.locations set location_type_id=target_location_type_id,code=target_code,name=target_name,description=target_description,updated_by=actor.actor_user_id
      where tenant_id=actor.actor_tenant_id and id=target_id and version=expected_version and status='active'
      returning version,status,code,name,parent_id,location_type_id into entity_version,entity_status,entity_code,entity_name,entity_parent_id,entity_location_type_id;
    elsif target_resource = 'cost_centers' then
      update public.cost_centers set code=target_code,name=target_name,description=target_description,updated_by=actor.actor_user_id
      where tenant_id=actor.actor_tenant_id and id=target_id and version=expected_version and status='active'
      returning version,status,code,name,parent_id into entity_version,entity_status,entity_code,entity_name,entity_parent_id;
    else
      update public.sectors set code=target_code,name=target_name,description=target_description,updated_by=actor.actor_user_id
      where tenant_id=actor.actor_tenant_id and id=target_id and version=expected_version and status='active'
      returning version,status,code,name into entity_version,entity_status,entity_code,entity_name;
    end if;
    if not found then raise exception using errcode='P0001', message='CATALOG_VERSION_CONFLICT'; end if;
  elsif target_action = 'move' then
    if target_id is null or expected_version is null then raise exception using errcode='22023', message='INVALID_MOVE_INPUT'; end if;
    if target_resource = 'locations' then
      if target_parent_id = target_id then raise exception using errcode='23514', message='LOCATION_CYCLE'; end if;
      if target_parent_id is not null and not exists(select 1 from public.locations p where p.tenant_id=actor.actor_tenant_id and p.id=target_parent_id and p.status='active') then
        raise exception using errcode='P0001', message='LOCATION_PARENT_UNAVAILABLE';
      end if;
      if exists(with recursive descendants as (
          select l.id from public.locations l where l.tenant_id=actor.actor_tenant_id and l.parent_id=target_id
          union all select child.id from public.locations child join descendants d on child.parent_id=d.id where child.tenant_id=actor.actor_tenant_id
        ) select 1 from descendants where id=target_parent_id) then
        raise exception using errcode='23514', message='LOCATION_CYCLE';
      end if;
      update public.locations set parent_id=target_parent_id,updated_by=actor.actor_user_id
      where tenant_id=actor.actor_tenant_id and id=target_id and version=expected_version and status='active'
      returning version,status,code,name,parent_id,location_type_id into entity_version,entity_status,entity_code,entity_name,entity_parent_id,entity_location_type_id;
    else
      if target_parent_id = target_id then raise exception using errcode='23514', message='COST_CENTER_CYCLE'; end if;
      if target_parent_id is not null and not exists(select 1 from public.cost_centers p where p.tenant_id=actor.actor_tenant_id and p.id=target_parent_id and p.status='active') then
        raise exception using errcode='P0001', message='COST_CENTER_PARENT_UNAVAILABLE';
      end if;
      if exists(with recursive descendants as (
          select c.id from public.cost_centers c where c.tenant_id=actor.actor_tenant_id and c.parent_id=target_id
          union all select child.id from public.cost_centers child join descendants d on child.parent_id=d.id where child.tenant_id=actor.actor_tenant_id
        ) select 1 from descendants where id=target_parent_id) then
        raise exception using errcode='23514', message='COST_CENTER_CYCLE';
      end if;
      update public.cost_centers set parent_id=target_parent_id,updated_by=actor.actor_user_id
      where tenant_id=actor.actor_tenant_id and id=target_id and version=expected_version and status='active'
      returning version,status,code,name,parent_id into entity_version,entity_status,entity_code,entity_name,entity_parent_id;
    end if;
    if not found then raise exception using errcode='P0001', message='CATALOG_VERSION_CONFLICT'; end if;
  else
    if target_id is null or expected_version is null then raise exception using errcode='22023', message='INVALID_STATUS_INPUT'; end if;
    if target_action = 'inactivate' then
      if target_resource='location_types' and exists(select 1 from public.locations l where l.tenant_id=actor.actor_tenant_id and l.location_type_id=target_id and l.status='active') then
        raise exception using errcode='23514', message='ACTIVE_LOCATION_DEPENDENCY';
      elsif target_resource='locations' and exists(select 1 from public.locations l where l.tenant_id=actor.actor_tenant_id and l.parent_id=target_id and l.status='active') then
        raise exception using errcode='23514', message='ACTIVE_LOCATION_CHILDREN';
      elsif target_resource='cost_centers' and exists(select 1 from public.cost_centers c where c.tenant_id=actor.actor_tenant_id and c.parent_id=target_id and c.status='active') then
        raise exception using errcode='23514', message='ACTIVE_COST_CENTER_CHILDREN';
      end if;
    end if;
    if target_resource='location_types' then
      update public.location_types set status=case target_action when 'inactivate' then 'inactive' else 'active' end,
        inactivated_at=case target_action when 'inactivate' then pg_catalog.statement_timestamp() else null end,updated_by=actor.actor_user_id
      where tenant_id=actor.actor_tenant_id and id=target_id and version=expected_version
        and status=case target_action when 'inactivate' then 'active' else 'inactive' end
      returning version,status,code,name into entity_version,entity_status,entity_code,entity_name;
    elsif target_resource='locations' then
      if target_action='reactivate' and (
        not exists(select 1 from public.location_types t join public.locations l on l.location_type_id=t.id and l.tenant_id=t.tenant_id where l.id=target_id and l.tenant_id=actor.actor_tenant_id and t.status='active')
        or exists(select 1 from public.locations l join public.locations p on p.id=l.parent_id and p.tenant_id=l.tenant_id where l.id=target_id and l.tenant_id=actor.actor_tenant_id and p.status<>'active')) then
        raise exception using errcode='23514', message='LOCATION_DEPENDENCY_INACTIVE';
      end if;
      update public.locations set status=case target_action when 'inactivate' then 'inactive' else 'active' end,
        inactivated_at=case target_action when 'inactivate' then pg_catalog.statement_timestamp() else null end,updated_by=actor.actor_user_id
      where tenant_id=actor.actor_tenant_id and id=target_id and version=expected_version
        and status=case target_action when 'inactivate' then 'active' else 'inactive' end
      returning version,status,code,name,parent_id,location_type_id into entity_version,entity_status,entity_code,entity_name,entity_parent_id,entity_location_type_id;
    elsif target_resource='cost_centers' then
      if target_action='reactivate' and exists(select 1 from public.cost_centers c join public.cost_centers p on p.id=c.parent_id and p.tenant_id=c.tenant_id where c.id=target_id and c.tenant_id=actor.actor_tenant_id and p.status<>'active') then
        raise exception using errcode='23514', message='COST_CENTER_PARENT_INACTIVE';
      end if;
      update public.cost_centers set status=case target_action when 'inactivate' then 'inactive' else 'active' end,
        inactivated_at=case target_action when 'inactivate' then pg_catalog.statement_timestamp() else null end,updated_by=actor.actor_user_id
      where tenant_id=actor.actor_tenant_id and id=target_id and version=expected_version
        and status=case target_action when 'inactivate' then 'active' else 'inactive' end
      returning version,status,code,name,parent_id into entity_version,entity_status,entity_code,entity_name,entity_parent_id;
    else
      update public.sectors set status=case target_action when 'inactivate' then 'inactive' else 'active' end,
        inactivated_at=case target_action when 'inactivate' then pg_catalog.statement_timestamp() else null end,updated_by=actor.actor_user_id
      where tenant_id=actor.actor_tenant_id and id=target_id and version=expected_version
        and status=case target_action when 'inactivate' then 'active' else 'inactive' end
      returning version,status,code,name into entity_version,entity_status,entity_code,entity_name;
    end if;
    if not found then raise exception using errcode='P0001', message='CATALOG_STATE_OR_VERSION_CONFLICT'; end if;
  end if;

  perform private.append_audit(actor.actor_tenant_id,'application_user',event_type,aggregate_type,correlation_id,'user_command',
    actor.actor_user_id,null,entity_id,idem.acquired_command_id,null,1,command_reason,
    pg_catalog.jsonb_build_object('version',entity_version,'status',entity_status));
  perform private.append_history(actor.actor_tenant_id,aggregate_type,entity_id,event_type,'application_user',command_name,
    idem.acquired_command_id,correlation_id,'user_command',entity_version,entity_code,1,actor.actor_user_id,null,null,
    pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object('name',entity_name,'status',entity_status,'parent_id',entity_parent_id,'location_type_id',entity_location_type_id)));
  perform private.enqueue_event(actor.actor_tenant_id,event_type,'application_user','user_command',idem.acquired_command_id,correlation_id,
    aggregate_type,entity_id,1,entity_version,actor.actor_user_id,null,null,
    pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object('id',entity_id,'version',entity_version,'status',entity_status,'code',entity_code,'name',entity_name)),
    pg_catalog.jsonb_build_object('command',command_name));

  result := pg_catalog.jsonb_build_object('id',entity_id,'version',entity_version,'status',entity_status,'command_correlation_id',correlation_id);
  perform private.complete_command_idempotency(idem.acquired_command_id,1,result);
  return result;
end;
$$;
revoke all on function private.execute_w4a_catalog_command(text,text,uuid,bigint,text,text,text,uuid,uuid,text,uuid,text)
  from public, anon, authenticated, service_role, cw_worker;
alter function private.execute_w4a_catalog_command(text,text,uuid,bigint,text,text,text,uuid,uuid,text,uuid,text) owner to postgres;

-- Explicit public command boundaries. Tenant and actor are always derived server-side.
create function public.create_location_type(code text,name text,description text,reason text,correlation_id uuid,idempotency_key text) returns jsonb
language sql security definer set search_path='' as $$ select private.execute_w4a_catalog_command('location_types','create',null,null,code,name,description,null,null,reason,correlation_id,idempotency_key) $$;
create function public.update_location_type(id uuid,expected_version bigint,code text,name text,description text,reason text,correlation_id uuid,idempotency_key text) returns jsonb
language sql security definer set search_path='' as $$ select private.execute_w4a_catalog_command('location_types','update',id,expected_version,code,name,description,null,null,reason,correlation_id,idempotency_key) $$;
create function public.inactivate_location_type(id uuid,expected_version bigint,reason text,correlation_id uuid,idempotency_key text) returns jsonb
language sql security definer set search_path='' as $$ select private.execute_w4a_catalog_command('location_types','inactivate',id,expected_version,null,null,null,null,null,reason,correlation_id,idempotency_key) $$;
create function public.reactivate_location_type(id uuid,expected_version bigint,reason text,correlation_id uuid,idempotency_key text) returns jsonb
language sql security definer set search_path='' as $$ select private.execute_w4a_catalog_command('location_types','reactivate',id,expected_version,null,null,null,null,null,reason,correlation_id,idempotency_key) $$;

create function public.create_location(location_type_id uuid,parent_id uuid,code text,name text,description text,reason text,correlation_id uuid,idempotency_key text) returns jsonb
language sql security definer set search_path='' as $$ select private.execute_w4a_catalog_command('locations','create',null,null,code,name,description,parent_id,location_type_id,reason,correlation_id,idempotency_key) $$;
create function public.update_location(id uuid,expected_version bigint,location_type_id uuid,code text,name text,description text,reason text,correlation_id uuid,idempotency_key text) returns jsonb
language sql security definer set search_path='' as $$ select private.execute_w4a_catalog_command('locations','update',id,expected_version,code,name,description,null,location_type_id,reason,correlation_id,idempotency_key) $$;
create function public.move_location(id uuid,expected_version bigint,parent_id uuid,reason text,correlation_id uuid,idempotency_key text) returns jsonb
language sql security definer set search_path='' as $$ select private.execute_w4a_catalog_command('locations','move',id,expected_version,null,null,null,parent_id,null,reason,correlation_id,idempotency_key) $$;
create function public.inactivate_location(id uuid,expected_version bigint,reason text,correlation_id uuid,idempotency_key text) returns jsonb
language sql security definer set search_path='' as $$ select private.execute_w4a_catalog_command('locations','inactivate',id,expected_version,null,null,null,null,null,reason,correlation_id,idempotency_key) $$;
create function public.reactivate_location(id uuid,expected_version bigint,reason text,correlation_id uuid,idempotency_key text) returns jsonb
language sql security definer set search_path='' as $$ select private.execute_w4a_catalog_command('locations','reactivate',id,expected_version,null,null,null,null,null,reason,correlation_id,idempotency_key) $$;

create function public.create_cost_center(parent_id uuid,code text,name text,description text,reason text,correlation_id uuid,idempotency_key text) returns jsonb
language sql security definer set search_path='' as $$ select private.execute_w4a_catalog_command('cost_centers','create',null,null,code,name,description,parent_id,null,reason,correlation_id,idempotency_key) $$;
create function public.update_cost_center(id uuid,expected_version bigint,code text,name text,description text,reason text,correlation_id uuid,idempotency_key text) returns jsonb
language sql security definer set search_path='' as $$ select private.execute_w4a_catalog_command('cost_centers','update',id,expected_version,code,name,description,null,null,reason,correlation_id,idempotency_key) $$;
create function public.move_cost_center(id uuid,expected_version bigint,parent_id uuid,reason text,correlation_id uuid,idempotency_key text) returns jsonb
language sql security definer set search_path='' as $$ select private.execute_w4a_catalog_command('cost_centers','move',id,expected_version,null,null,null,parent_id,null,reason,correlation_id,idempotency_key) $$;
create function public.inactivate_cost_center(id uuid,expected_version bigint,reason text,correlation_id uuid,idempotency_key text) returns jsonb
language sql security definer set search_path='' as $$ select private.execute_w4a_catalog_command('cost_centers','inactivate',id,expected_version,null,null,null,null,null,reason,correlation_id,idempotency_key) $$;
create function public.reactivate_cost_center(id uuid,expected_version bigint,reason text,correlation_id uuid,idempotency_key text) returns jsonb
language sql security definer set search_path='' as $$ select private.execute_w4a_catalog_command('cost_centers','reactivate',id,expected_version,null,null,null,null,null,reason,correlation_id,idempotency_key) $$;

create function public.create_sector(code text,name text,description text,reason text,correlation_id uuid,idempotency_key text) returns jsonb
language sql security definer set search_path='' as $$ select private.execute_w4a_catalog_command('sectors','create',null,null,code,name,description,null,null,reason,correlation_id,idempotency_key) $$;
create function public.update_sector(id uuid,expected_version bigint,code text,name text,description text,reason text,correlation_id uuid,idempotency_key text) returns jsonb
language sql security definer set search_path='' as $$ select private.execute_w4a_catalog_command('sectors','update',id,expected_version,code,name,description,null,null,reason,correlation_id,idempotency_key) $$;
create function public.inactivate_sector(id uuid,expected_version bigint,reason text,correlation_id uuid,idempotency_key text) returns jsonb
language sql security definer set search_path='' as $$ select private.execute_w4a_catalog_command('sectors','inactivate',id,expected_version,null,null,null,null,null,reason,correlation_id,idempotency_key) $$;
create function public.reactivate_sector(id uuid,expected_version bigint,reason text,correlation_id uuid,idempotency_key text) returns jsonb
language sql security definer set search_path='' as $$ select private.execute_w4a_catalog_command('sectors','reactivate',id,expected_version,null,null,null,null,null,reason,correlation_id,idempotency_key) $$;

-- Explicit read models. Administrative lists/details require read; selectors require lookup.
create function public.list_location_types(search_text text default null,status_filter text default null,result_limit integer default 50,result_offset integer default 0)
returns table(id uuid,code text,name text,description text,status text,version bigint,updated_at timestamptz)
language plpgsql security definer set search_path='' as $$ declare t uuid; begin t:=private.assert_w4a_catalog_access('location_types','read');
if result_limit not between 1 and 100 or result_offset<0 or (status_filter is not null and status_filter not in ('active','inactive')) then raise exception using errcode='22023',message='INVALID_QUERY_INPUT'; end if;
return query select x.id,x.code,x.name,x.description,x.status,x.version,x.updated_at from public.location_types x where x.tenant_id=t and (status_filter is null or x.status=status_filter) and (search_text is null or x.name ilike '%'||search_text||'%' or x.code ilike '%'||search_text||'%') order by x.name,x.id limit result_limit offset result_offset; end $$;
create function public.get_location_type(target_id uuid)
returns table(id uuid,code text,name text,description text,status text,version bigint,created_at timestamptz,updated_at timestamptz)
language plpgsql security definer set search_path='' as $$ declare t uuid; begin t:=private.assert_w4a_catalog_access('location_types','read'); return query select x.id,x.code,x.name,x.description,x.status,x.version,x.created_at,x.updated_at from public.location_types x where x.tenant_id=t and x.id=target_id; end $$;
create function public.lookup_location_types(search_text text default null,result_limit integer default 20)
returns table(id uuid,code text,name text)
language plpgsql security definer set search_path='' as $$ declare t uuid; begin t:=private.assert_w4a_catalog_access('location_types','lookup'); if result_limit not between 1 and 100 then raise exception using errcode='22023',message='INVALID_QUERY_INPUT'; end if; return query select x.id,x.code,x.name from public.location_types x where x.tenant_id=t and x.status='active' and (search_text is null or x.name ilike '%'||search_text||'%' or x.code ilike '%'||search_text||'%') order by x.name,x.id limit result_limit; end $$;

create function public.list_locations(search_text text default null,status_filter text default null,result_limit integer default 50,result_offset integer default 0)
returns table(id uuid,location_type_id uuid,parent_id uuid,code text,name text,description text,status text,version bigint,updated_at timestamptz)
language plpgsql security definer set search_path='' as $$ declare t uuid; begin t:=private.assert_w4a_catalog_access('locations','read'); if result_limit not between 1 and 100 or result_offset<0 or (status_filter is not null and status_filter not in ('active','inactive')) then raise exception using errcode='22023',message='INVALID_QUERY_INPUT'; end if; return query select x.id,x.location_type_id,x.parent_id,x.code,x.name,x.description,x.status,x.version,x.updated_at from public.locations x where x.tenant_id=t and (status_filter is null or x.status=status_filter) and (search_text is null or x.name ilike '%'||search_text||'%' or x.code ilike '%'||search_text||'%') order by x.name,x.id limit result_limit offset result_offset; end $$;
create function public.get_location(target_id uuid)
returns table(id uuid,location_type_id uuid,parent_id uuid,code text,name text,description text,status text,version bigint,created_at timestamptz,updated_at timestamptz)
language plpgsql security definer set search_path='' as $$ declare t uuid; begin t:=private.assert_w4a_catalog_access('locations','read'); return query select x.id,x.location_type_id,x.parent_id,x.code,x.name,x.description,x.status,x.version,x.created_at,x.updated_at from public.locations x where x.tenant_id=t and x.id=target_id; end $$;
create function public.lookup_locations(search_text text default null,result_limit integer default 20)
returns table(id uuid,code text,name text)
language plpgsql security definer set search_path='' as $$ declare t uuid; begin t:=private.assert_w4a_catalog_access('locations','lookup'); if result_limit not between 1 and 100 then raise exception using errcode='22023',message='INVALID_QUERY_INPUT'; end if; return query select x.id,x.code,x.name from public.locations x where x.tenant_id=t and x.status='active' and (search_text is null or x.name ilike '%'||search_text||'%' or x.code ilike '%'||search_text||'%') order by x.name,x.id limit result_limit; end $$;
create function public.list_location_children(target_parent_id uuid default null)
returns table(id uuid,location_type_id uuid,parent_id uuid,code text,name text,status text,version bigint)
language plpgsql security definer set search_path='' as $$ declare t uuid; begin t:=private.assert_w4a_catalog_access('locations','read'); return query select x.id,x.location_type_id,x.parent_id,x.code,x.name,x.status,x.version from public.locations x where x.tenant_id=t and x.parent_id is not distinct from target_parent_id order by x.name,x.id; end $$;

create function public.list_cost_centers(search_text text default null,status_filter text default null,result_limit integer default 50,result_offset integer default 0)
returns table(id uuid,parent_id uuid,code text,name text,description text,status text,version bigint,updated_at timestamptz)
language plpgsql security definer set search_path='' as $$ declare t uuid; begin t:=private.assert_w4a_catalog_access('cost_centers','read'); if result_limit not between 1 and 100 or result_offset<0 or (status_filter is not null and status_filter not in ('active','inactive')) then raise exception using errcode='22023',message='INVALID_QUERY_INPUT'; end if; return query select x.id,x.parent_id,x.code,x.name,x.description,x.status,x.version,x.updated_at from public.cost_centers x where x.tenant_id=t and (status_filter is null or x.status=status_filter) and (search_text is null or x.name ilike '%'||search_text||'%' or x.code ilike '%'||search_text||'%') order by x.name,x.id limit result_limit offset result_offset; end $$;
create function public.get_cost_center(target_id uuid)
returns table(id uuid,parent_id uuid,code text,name text,description text,status text,version bigint,created_at timestamptz,updated_at timestamptz)
language plpgsql security definer set search_path='' as $$ declare t uuid; begin t:=private.assert_w4a_catalog_access('cost_centers','read'); return query select x.id,x.parent_id,x.code,x.name,x.description,x.status,x.version,x.created_at,x.updated_at from public.cost_centers x where x.tenant_id=t and x.id=target_id; end $$;
create function public.lookup_cost_centers(search_text text default null,result_limit integer default 20)
returns table(id uuid,code text,name text)
language plpgsql security definer set search_path='' as $$ declare t uuid; begin t:=private.assert_w4a_catalog_access('cost_centers','lookup'); if result_limit not between 1 and 100 then raise exception using errcode='22023',message='INVALID_QUERY_INPUT'; end if; return query select x.id,x.code,x.name from public.cost_centers x where x.tenant_id=t and x.status='active' and (search_text is null or x.name ilike '%'||search_text||'%' or x.code ilike '%'||search_text||'%') order by x.name,x.id limit result_limit; end $$;
create function public.list_cost_center_children(target_parent_id uuid default null)
returns table(id uuid,parent_id uuid,code text,name text,status text,version bigint)
language plpgsql security definer set search_path='' as $$ declare t uuid; begin t:=private.assert_w4a_catalog_access('cost_centers','read'); return query select x.id,x.parent_id,x.code,x.name,x.status,x.version from public.cost_centers x where x.tenant_id=t and x.parent_id is not distinct from target_parent_id order by x.name,x.id; end $$;

create function public.list_sectors(search_text text default null,status_filter text default null,result_limit integer default 50,result_offset integer default 0)
returns table(id uuid,code text,name text,description text,status text,version bigint,updated_at timestamptz)
language plpgsql security definer set search_path='' as $$ declare t uuid; begin t:=private.assert_w4a_catalog_access('sectors','read'); if result_limit not between 1 and 100 or result_offset<0 or (status_filter is not null and status_filter not in ('active','inactive')) then raise exception using errcode='22023',message='INVALID_QUERY_INPUT'; end if; return query select x.id,x.code,x.name,x.description,x.status,x.version,x.updated_at from public.sectors x where x.tenant_id=t and (status_filter is null or x.status=status_filter) and (search_text is null or x.name ilike '%'||search_text||'%' or x.code ilike '%'||search_text||'%') order by x.name,x.id limit result_limit offset result_offset; end $$;
create function public.get_sector(target_id uuid)
returns table(id uuid,code text,name text,description text,status text,version bigint,created_at timestamptz,updated_at timestamptz)
language plpgsql security definer set search_path='' as $$ declare t uuid; begin t:=private.assert_w4a_catalog_access('sectors','read'); return query select x.id,x.code,x.name,x.description,x.status,x.version,x.created_at,x.updated_at from public.sectors x where x.tenant_id=t and x.id=target_id; end $$;
create function public.lookup_sectors(search_text text default null,result_limit integer default 20)
returns table(id uuid,code text,name text)
language plpgsql security definer set search_path='' as $$ declare t uuid; begin t:=private.assert_w4a_catalog_access('sectors','lookup'); if result_limit not between 1 and 100 then raise exception using errcode='22023',message='INVALID_QUERY_INPUT'; end if; return query select x.id,x.code,x.name from public.sectors x where x.tenant_id=t and x.status='active' and (search_text is null or x.name ilike '%'||search_text||'%' or x.code ilike '%'||search_text||'%') order by x.name,x.id limit result_limit; end $$;

do $$
declare boundary record;
begin
  for boundary in
    select procedure.oid
    from pg_catalog.pg_proc procedure
    join pg_catalog.pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname = any(array[
        'create_location_type','update_location_type','inactivate_location_type','reactivate_location_type',
        'create_location','update_location','move_location','inactivate_location','reactivate_location',
        'create_cost_center','update_cost_center','move_cost_center','inactivate_cost_center','reactivate_cost_center',
        'create_sector','update_sector','inactivate_sector','reactivate_sector',
        'list_location_types','get_location_type','lookup_location_types',
        'list_locations','get_location','lookup_locations','list_location_children',
        'list_cost_centers','get_cost_center','lookup_cost_centers','list_cost_center_children',
        'list_sectors','get_sector','lookup_sectors'
      ])
  loop
    execute pg_catalog.format(
      'revoke all on function %s from public, anon, service_role, cw_worker', boundary.oid::pg_catalog.regprocedure
    );
  end loop;
end;
$$;

-- The repository default privileges already deny PUBLIC. Explicitly grant only W4A boundaries.
grant execute on function public.create_location_type(text,text,text,text,uuid,text) to authenticated;
grant execute on function public.update_location_type(uuid,bigint,text,text,text,text,uuid,text) to authenticated;
grant execute on function public.inactivate_location_type(uuid,bigint,text,uuid,text) to authenticated;
grant execute on function public.reactivate_location_type(uuid,bigint,text,uuid,text) to authenticated;
grant execute on function public.create_location(uuid,uuid,text,text,text,text,uuid,text) to authenticated;
grant execute on function public.update_location(uuid,bigint,uuid,text,text,text,text,uuid,text) to authenticated;
grant execute on function public.move_location(uuid,bigint,uuid,text,uuid,text) to authenticated;
grant execute on function public.inactivate_location(uuid,bigint,text,uuid,text) to authenticated;
grant execute on function public.reactivate_location(uuid,bigint,text,uuid,text) to authenticated;
grant execute on function public.create_cost_center(uuid,text,text,text,text,uuid,text) to authenticated;
grant execute on function public.update_cost_center(uuid,bigint,text,text,text,text,uuid,text) to authenticated;
grant execute on function public.move_cost_center(uuid,bigint,uuid,text,uuid,text) to authenticated;
grant execute on function public.inactivate_cost_center(uuid,bigint,text,uuid,text) to authenticated;
grant execute on function public.reactivate_cost_center(uuid,bigint,text,uuid,text) to authenticated;
grant execute on function public.create_sector(text,text,text,text,uuid,text) to authenticated;
grant execute on function public.update_sector(uuid,bigint,text,text,text,text,uuid,text) to authenticated;
grant execute on function public.inactivate_sector(uuid,bigint,text,uuid,text) to authenticated;
grant execute on function public.reactivate_sector(uuid,bigint,text,uuid,text) to authenticated;
grant execute on function public.list_location_types(text,text,integer,integer) to authenticated;
grant execute on function public.get_location_type(uuid) to authenticated;
grant execute on function public.lookup_location_types(text,integer) to authenticated;
grant execute on function public.list_locations(text,text,integer,integer) to authenticated;
grant execute on function public.get_location(uuid) to authenticated;
grant execute on function public.lookup_locations(text,integer) to authenticated;
grant execute on function public.list_location_children(uuid) to authenticated;
grant execute on function public.list_cost_centers(text,text,integer,integer) to authenticated;
grant execute on function public.get_cost_center(uuid) to authenticated;
grant execute on function public.lookup_cost_centers(text,integer) to authenticated;
grant execute on function public.list_cost_center_children(uuid) to authenticated;
grant execute on function public.list_sectors(text,text,integer,integer) to authenticated;
grant execute on function public.get_sector(uuid) to authenticated;
grant execute on function public.lookup_sectors(text,integer) to authenticated;

comment on table public.location_types is 'W4A tenant-owned structural catalog of location classifications.';
comment on table public.locations is 'W4A tenant-owned hierarchical locations.';
comment on table public.cost_centers is 'W4A tenant-owned hierarchical cost centers.';
comment on table public.sectors is 'W4A tenant-owned sectors.';
