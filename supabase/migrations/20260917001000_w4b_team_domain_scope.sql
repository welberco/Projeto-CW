-- W4B.2: Team domain and exact TEAM-scope enforcement.

create table public.teams (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  sector_id uuid,
  code text,
  name text not null,
  description text,
  status text not null default 'active',
  created_by uuid not null references public.app_users (id) on delete restrict,
  updated_by uuid not null references public.app_users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  updated_at timestamptz not null default pg_catalog.statement_timestamp(),
  inactivated_at timestamptz,
  version bigint not null default 1,
  constraint teams_tenant_id_id_uq unique (tenant_id, id),
  constraint teams_sector_fk foreign key (tenant_id, sector_id)
    references public.sectors (tenant_id, id) on delete restrict,
  constraint teams_code_check check (
    code is null or (
      code = pg_catalog.btrim(code)
      and code ~ '^[A-Za-z0-9][A-Za-z0-9._/-]{0,63}$'
    )
  ),
  constraint teams_name_check check (
    name = pg_catalog.btrim(name)
    and pg_catalog.char_length(name) between 1 and 160
  ),
  constraint teams_description_check check (
    description is null or (
      description = pg_catalog.btrim(description)
      and pg_catalog.char_length(description) <= 2000
    )
  ),
  constraint teams_status_check check (status in ('active', 'inactive')),
  constraint teams_lifecycle_check check (
    (status = 'active' and inactivated_at is null)
    or (status = 'inactive' and inactivated_at is not null)
  ),
  constraint teams_version_check check (version > 0)
);

create unique index teams_tenant_code_uidx
  on public.teams (tenant_id, pg_catalog.lower(code))
  where code is not null;
create index teams_tenant_status_name_idx
  on public.teams (tenant_id, status, name, id);
create index teams_tenant_sector_status_idx
  on public.teams (tenant_id, sector_id, status);

create table public.team_memberships (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  tenant_id uuid not null,
  team_id uuid not null,
  membership_id uuid not null,
  status text not null default 'active',
  joined_at timestamptz not null default pg_catalog.statement_timestamp(),
  ended_at timestamptz,
  created_by uuid not null references public.app_users (id) on delete restrict,
  updated_by uuid not null references public.app_users (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.statement_timestamp(),
  updated_at timestamptz not null default pg_catalog.statement_timestamp(),
  version bigint not null default 1,
  constraint team_memberships_tenant_id_id_uq unique (tenant_id, id),
  constraint team_memberships_team_fk foreign key (tenant_id, team_id)
    references public.teams (tenant_id, id) on delete restrict,
  constraint team_memberships_membership_fk foreign key (tenant_id, membership_id)
    references public.tenant_memberships (tenant_id, id) on delete restrict,
  constraint team_memberships_status_check check (status in ('active', 'ended')),
  constraint team_memberships_lifecycle_check check (
    (status = 'active' and ended_at is null)
    or (status = 'ended' and ended_at is not null and ended_at >= joined_at)
  ),
  constraint team_memberships_version_check check (version > 0)
);

create unique index team_memberships_one_active_pair_uidx
  on public.team_memberships (tenant_id, team_id, membership_id)
  where status = 'active';
create index team_memberships_team_status_idx
  on public.team_memberships (tenant_id, team_id, status, id);
create index team_memberships_membership_status_idx
  on public.team_memberships (tenant_id, membership_id, status, id);

comment on table public.teams is
  'Tenant-owned operational teams. An optional sector is a same-tenant structural parent.';
comment on table public.team_memberships is
  'Append-oriented team participation. Ended rows are immutable; a return creates a new row.';

create function private.protect_team_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '23514', message = 'TEAM_DELETE_FORBIDDEN';
  end if;
  if new.id is distinct from old.id
     or new.tenant_id is distinct from old.tenant_id
     or new.created_by is distinct from old.created_by
     or new.created_at is distinct from old.created_at then
    raise exception using errcode = '23514', message = 'TEAM_IDENTITY_IMMUTABLE';
  end if;
  if new.version is distinct from old.version then
    raise exception using errcode = '23514', message = 'TEAM_VERSION_MANAGED';
  end if;
  return new;
end;
$$;

create function private.enforce_team_integrity()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.status = 'active' and new.sector_id is not null and not exists (
    select 1 from public.sectors as sector
    where sector.tenant_id = new.tenant_id
      and sector.id = new.sector_id
      and sector.status = 'active'
  ) then
    raise exception using errcode = '23514', message = 'TEAM_SECTOR_UNAVAILABLE';
  end if;

  if tg_op = 'UPDATE'
     and old.status = 'active'
     and new.status = 'inactive'
     and exists (
       select 1 from public.team_memberships as association
       where association.tenant_id = old.tenant_id
         and association.team_id = old.id
         and association.status = 'active'
     ) then
    raise exception using errcode = '23514', message = 'ACTIVE_TEAM_MEMBERSHIP_DEPENDENCY';
  end if;
  return new;
end;
$$;

create function private.protect_team_membership_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '23514', message = 'TEAM_MEMBERSHIP_DELETE_FORBIDDEN';
  end if;
  if old.status = 'ended' then
    raise exception using errcode = '23514', message = 'ENDED_TEAM_MEMBERSHIP_IMMUTABLE';
  end if;
  if new.id is distinct from old.id
     or new.tenant_id is distinct from old.tenant_id
     or new.team_id is distinct from old.team_id
     or new.membership_id is distinct from old.membership_id
     or new.joined_at is distinct from old.joined_at
     or new.created_by is distinct from old.created_by
     or new.created_at is distinct from old.created_at then
    raise exception using errcode = '23514', message = 'TEAM_MEMBERSHIP_IDENTITY_IMMUTABLE';
  end if;
  if new.version is distinct from old.version then
    raise exception using errcode = '23514', message = 'TEAM_MEMBERSHIP_VERSION_MANAGED';
  end if;
  if old.status = 'active' and new.status not in ('active', 'ended') then
    raise exception using errcode = '23514', message = 'INVALID_TEAM_MEMBERSHIP_TRANSITION';
  end if;
  return new;
end;
$$;

create function private.enforce_team_membership_integrity()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' and (
    not exists (
      select 1 from public.teams as team
      where team.tenant_id = new.tenant_id
        and team.id = new.team_id
        and team.status = 'active'
    )
    or not exists (
      select 1
      from public.tenant_memberships as membership
      join public.app_users as app_user on app_user.id = membership.user_id
      where membership.tenant_id = new.tenant_id
        and membership.id = new.membership_id
        and membership.status = 'active'
        and app_user.status = 'active'
    )
  ) then
    raise exception using errcode = '23514', message = 'TEAM_MEMBERSHIP_TARGET_UNAVAILABLE';
  end if;
  return new;
end;
$$;

create function private.bump_tenant_membership_revision_for_team()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  update public.tenant_memberships
  set updated_at = pg_catalog.statement_timestamp()
  where tenant_id = new.tenant_id and id = new.membership_id;
  return new;
end;
$$;

create function private.protect_sector_team_dependency()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if old.status = 'active' and new.status = 'inactive' and exists (
    select 1 from public.teams as team
    where team.tenant_id = old.tenant_id
      and team.sector_id = old.id
      and team.status = 'active'
  ) then
    raise exception using errcode = '23514', message = 'ACTIVE_TEAM_SECTOR_DEPENDENCY';
  end if;
  return new;
end;
$$;

create trigger teams_10_protect
before update or delete on public.teams
for each row execute function private.protect_team_mutation();
create trigger teams_20_integrity
before insert or update on public.teams
for each row execute function private.enforce_team_integrity();
create trigger teams_90_set_updated_at_and_version
before update on public.teams
for each row execute function private.set_updated_at_and_version();

create trigger team_memberships_10_protect
before update or delete on public.team_memberships
for each row execute function private.protect_team_membership_mutation();
create trigger team_memberships_20_integrity
before insert or update on public.team_memberships
for each row execute function private.enforce_team_membership_integrity();
create trigger team_memberships_90_set_updated_at_and_version
before update on public.team_memberships
for each row execute function private.set_updated_at_and_version();
create trigger team_memberships_95_bump_authorization_revision
after insert or update of status on public.team_memberships
for each row execute function private.bump_tenant_membership_revision_for_team();

create trigger sectors_25_protect_team_dependency
before update of status on public.sectors
for each row execute function private.protect_sector_team_dependency();

-- TEAM reach is a current database fact. No tenant, actor or scope comes from payload.
create function private.team_reaches(target_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(exists (
    select 1
    from public.app_users as app_user
    join public.tenant_memberships as membership
      on membership.user_id = app_user.id and membership.status = 'active'
    join public.tenants as tenant
      on tenant.id = membership.tenant_id and tenant.status = 'active'
    join public.teams as team
      on team.id = target_team_id
     and team.tenant_id = tenant.id
     and team.status = 'active'
    join public.team_memberships as association
      on association.tenant_id = tenant.id
     and association.team_id = team.id
     and association.membership_id = membership.id
     and association.status = 'active'
     and association.ended_at is null
    where app_user.id = auth.uid() and app_user.status = 'active'
  ), false)
$$;

create function private.can_access_team(target_team_id uuid, target_action text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(exists (
    select 1
    from public.teams as team
    join public.tenant_memberships as membership
      on membership.tenant_id = team.tenant_id
     and membership.user_id = auth.uid()
     and membership.status = 'active'
    join public.app_users as app_user
      on app_user.id = membership.user_id and app_user.status = 'active'
    join public.tenants as tenant
      on tenant.id = membership.tenant_id and tenant.status = 'active'
    where team.id = target_team_id
      and target_action in ('read', 'lookup')
      and (
        private.has_effective_permission('teams', target_action, 'ALL_TENANT'::public.authorization_scope)
        or (
          private.has_effective_permission('teams', target_action, 'TEAM'::public.authorization_scope)
          and private.team_reaches(team.id)
        )
      )
  ), false)
$$;

create function private.assert_w4b_all_tenant_access(target_resource text, target_action text)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  resolved_tenant_id uuid;
begin
  select membership.tenant_id
  into resolved_tenant_id
  from public.tenant_memberships as membership
  join public.app_users as app_user
    on app_user.id = membership.user_id and app_user.status = 'active'
  join public.tenants as tenant
    on tenant.id = membership.tenant_id and tenant.status = 'active'
  where membership.user_id = auth.uid()
    and membership.status = 'active'
    and private.has_effective_permission(
      target_resource,
      target_action,
      'ALL_TENANT'::public.authorization_scope
    );
  if resolved_tenant_id is null then
    raise exception using errcode = '42501', message = 'AUTHORIZATION_DENIED';
  end if;
  return resolved_tenant_id;
end;
$$;

alter table public.teams enable row level security;
alter table public.teams force row level security;
alter table public.team_memberships enable row level security;
alter table public.team_memberships force row level security;

revoke all on table public.teams from public, anon, authenticated, service_role, cw_worker;
revoke all on table public.team_memberships from public, anon, authenticated, service_role, cw_worker;
grant select on table public.teams to authenticated;

create policy teams_read on public.teams
for select to authenticated
using (private.can_access_team(id, 'read'));

-- No client policy exists for team_memberships. Roster access is RPC-only.

create function private.execute_team_command(
  target_action text,
  target_id uuid,
  expected_version bigint,
  target_sector_id uuid,
  target_code text,
  target_name text,
  target_description text,
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
  command_name text := 'cadastros.' || target_action || '_team';
  event_type text;
  entity_version bigint;
  entity_status text;
  entity_code text;
  entity_name text;
  entity_sector_id uuid;
  current_sector_id uuid;
  result jsonb;
begin
  if target_action not in ('create', 'update', 'inactivate', 'reactivate') then
    raise exception using errcode = '22023', message = 'INVALID_TEAM_COMMAND';
  end if;
  if command_reason is null or command_reason <> pg_catalog.btrim(command_reason)
     or pg_catalog.char_length(command_reason) not between 1 and 500 then
    raise exception using errcode = '22023', message = 'INVALID_COMMAND_REASON';
  end if;

  select * into actor from private.lock_authorization_actor('teams', target_action);
  fingerprint := private.semantic_fingerprint(pg_catalog.jsonb_strip_nulls(
    pg_catalog.jsonb_build_object(
      'action', target_action,
      'id', target_id,
      'expected_version', expected_version,
      'sector_id', target_sector_id,
      'code', target_code,
      'name', target_name,
      'description', target_description
    )
  ));
  select * into idem from private.acquire_command_idempotency(
    actor.actor_tenant_id, 'application_user', 'user_command', command_name,
    command_idempotency_key, fingerprint, actor.actor_user_id, null, null
  );
  if idem.replayed then return idem.stored_result; end if;

  if target_action in ('update', 'reactivate') and target_id is not null then
    select team.sector_id into current_sector_id
    from public.teams as team
    where team.tenant_id = actor.actor_tenant_id and team.id = target_id;
  end if;

  if coalesce(target_sector_id, current_sector_id) is not null then
    perform 1 from public.sectors as sector
    where sector.tenant_id = actor.actor_tenant_id
      and sector.id = coalesce(target_sector_id, current_sector_id)
      and sector.status = 'active'
    for update;
    if not found then
      raise exception using errcode = 'P0001', message = 'TEAM_SECTOR_UNAVAILABLE';
    end if;
  end if;

  if target_action <> 'create' then
    perform 1 from public.teams as team
    where team.tenant_id = actor.actor_tenant_id and team.id = target_id
    for update;
  end if;

  -- Re-evaluate current actor facts after domain locks and immediately before validation/mutation.
  select * into actor from private.lock_authorization_actor('teams', target_action);

  if target_action = 'create' then
    if target_name is null or target_name <> pg_catalog.btrim(target_name) then
      raise exception using errcode = '22023', message = 'INVALID_TEAM_NAME';
    end if;
    insert into public.teams (
      id, tenant_id, sector_id, code, name, description, created_by, updated_by
    ) values (
      entity_id, actor.actor_tenant_id, target_sector_id, target_code, target_name,
      target_description, actor.actor_user_id, actor.actor_user_id
    )
    returning version, status, code, name, sector_id
      into entity_version, entity_status, entity_code, entity_name, entity_sector_id;
  elsif target_action = 'update' then
    if target_id is null or expected_version is null or target_name is null then
      raise exception using errcode = '22023', message = 'INVALID_TEAM_UPDATE_INPUT';
    end if;
    update public.teams
    set sector_id = target_sector_id,
        code = target_code,
        name = target_name,
        description = target_description,
        updated_by = actor.actor_user_id
    where tenant_id = actor.actor_tenant_id
      and id = target_id
      and version = expected_version
      and status = 'active'
    returning version, status, code, name, sector_id
      into entity_version, entity_status, entity_code, entity_name, entity_sector_id;
    if not found then
      raise exception using errcode = 'P0001', message = 'TEAM_VERSION_CONFLICT';
    end if;
  else
    if target_id is null or expected_version is null then
      raise exception using errcode = '22023', message = 'INVALID_TEAM_STATUS_INPUT';
    end if;
    update public.teams
    set status = case target_action when 'inactivate' then 'inactive' else 'active' end,
        inactivated_at = case target_action when 'inactivate'
          then pg_catalog.statement_timestamp() else null end,
        updated_by = actor.actor_user_id
    where tenant_id = actor.actor_tenant_id
      and id = target_id
      and version = expected_version
      and status = case target_action when 'inactivate' then 'active' else 'inactive' end
    returning version, status, code, name, sector_id
      into entity_version, entity_status, entity_code, entity_name, entity_sector_id;
    if not found then
      raise exception using errcode = 'P0001', message = 'TEAM_STATE_OR_VERSION_CONFLICT';
    end if;
  end if;

  event_type := 'cadastros.team.' || case target_action
    when 'create' then 'created'
    when 'update' then 'updated'
    when 'inactivate' then 'inactivated'
    else 'reactivated'
  end;
  perform private.append_audit(
    actor.actor_tenant_id, 'application_user', event_type, 'team', correlation_id,
    'user_command', actor.actor_user_id, null, entity_id, idem.acquired_command_id,
    null, 1, command_reason,
    pg_catalog.jsonb_build_object('version', entity_version, 'status', entity_status)
  );
  perform private.append_history(
    actor.actor_tenant_id, 'team', entity_id, event_type, 'application_user',
    command_name, idem.acquired_command_id, correlation_id, 'user_command',
    entity_version, entity_code, 1, actor.actor_user_id, null, null,
    pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
      'name', entity_name, 'status', entity_status, 'sector_id', entity_sector_id
    ))
  );
  perform private.enqueue_event(
    actor.actor_tenant_id, event_type, 'application_user', 'user_command',
    idem.acquired_command_id, correlation_id, 'team', entity_id, 1, entity_version,
    actor.actor_user_id, null, null,
    pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
      'id', entity_id, 'version', entity_version, 'status', entity_status,
      'code', entity_code, 'sector_id', entity_sector_id
    )),
    pg_catalog.jsonb_build_object('command', command_name)
  );

  result := pg_catalog.jsonb_build_object(
    'id', entity_id,
    'version', entity_version,
    'status', entity_status,
    'command_correlation_id', correlation_id
  );
  perform private.complete_command_idempotency(idem.acquired_command_id, 1, result);
  return result;
end;
$$;

create function private.execute_team_membership_command(
  target_action text,
  target_id uuid,
  target_team_id uuid,
  target_membership_id uuid,
  expected_version bigint,
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
  command_name text := 'cadastros.' || target_action || '_team_member';
  event_type text;
  entity_version bigint;
  entity_status text;
  entity_team_id uuid;
  entity_membership_id uuid;
  result jsonb;
begin
  if target_action not in ('add', 'end') then
    raise exception using errcode = '22023', message = 'INVALID_TEAM_MEMBERSHIP_COMMAND';
  end if;
  if command_reason is null or command_reason <> pg_catalog.btrim(command_reason)
     or pg_catalog.char_length(command_reason) not between 1 and 500 then
    raise exception using errcode = '22023', message = 'INVALID_COMMAND_REASON';
  end if;

  select * into actor from private.lock_authorization_actor(
    'team_memberships', target_action
  );
  fingerprint := private.semantic_fingerprint(pg_catalog.jsonb_strip_nulls(
    pg_catalog.jsonb_build_object(
      'action', target_action,
      'id', target_id,
      'team_id', target_team_id,
      'membership_id', target_membership_id,
      'expected_version', expected_version
    )
  ));
  select * into idem from private.acquire_command_idempotency(
    actor.actor_tenant_id, 'application_user', 'user_command', command_name,
    command_idempotency_key, fingerprint, actor.actor_user_id, null, null
  );
  if idem.replayed then return idem.stored_result; end if;

  if target_action = 'add' then
    if target_team_id is null or target_membership_id is null then
      raise exception using errcode = '22023', message = 'INVALID_TEAM_MEMBER_ADD_INPUT';
    end if;
    perform 1 from public.teams as team
    where team.tenant_id = actor.actor_tenant_id
      and team.id = target_team_id and team.status = 'active'
    for update;
    if not found then
      raise exception using errcode = 'P0001', message = 'TEAM_UNAVAILABLE';
    end if;
    perform 1
    from public.tenant_memberships as membership
    join public.app_users as app_user on app_user.id = membership.user_id
    where membership.tenant_id = actor.actor_tenant_id
      and membership.id = target_membership_id
      and membership.status = 'active'
      and app_user.status = 'active'
    for update of membership, app_user;
    if not found then
      raise exception using errcode = 'P0001', message = 'TEAM_MEMBER_TARGET_UNAVAILABLE';
    end if;
    select * into actor from private.lock_authorization_actor(
      'team_memberships', target_action
    );
    insert into public.team_memberships (
      id, tenant_id, team_id, membership_id, created_by, updated_by
    ) values (
      entity_id, actor.actor_tenant_id, target_team_id, target_membership_id,
      actor.actor_user_id, actor.actor_user_id
    )
    returning version, status, team_id, membership_id
      into entity_version, entity_status, entity_team_id, entity_membership_id;
  else
    if target_id is null or expected_version is null then
      raise exception using errcode = '22023', message = 'INVALID_TEAM_MEMBER_END_INPUT';
    end if;
    select association.team_id, association.membership_id
    into entity_team_id, entity_membership_id
    from public.team_memberships as association
    where association.tenant_id = actor.actor_tenant_id
      and association.id = target_id;
    if not found then
      raise exception using errcode = 'P0001', message = 'TEAM_MEMBERSHIP_UNAVAILABLE';
    end if;
    perform 1 from public.teams as team
    where team.tenant_id = actor.actor_tenant_id and team.id = entity_team_id
    for update;
    perform 1 from public.tenant_memberships as membership
    where membership.tenant_id = actor.actor_tenant_id
      and membership.id = entity_membership_id
    for update;
    perform 1 from public.team_memberships as association
    where association.tenant_id = actor.actor_tenant_id
      and association.id = target_id
    for update;
    select * into actor from private.lock_authorization_actor(
      'team_memberships', target_action
    );
    update public.team_memberships
    set status = 'ended',
        ended_at = pg_catalog.statement_timestamp(),
        updated_by = actor.actor_user_id
    where tenant_id = actor.actor_tenant_id
      and id = target_id
      and version = expected_version
      and status = 'active'
    returning version, status, team_id, membership_id
      into entity_version, entity_status, entity_team_id, entity_membership_id;
    if not found then
      raise exception using errcode = 'P0001', message = 'TEAM_MEMBERSHIP_STATE_OR_VERSION_CONFLICT';
    end if;
  end if;

  event_type := 'cadastros.team_membership.' || case target_action
    when 'add' then 'added' else 'ended' end;
  perform private.append_audit(
    actor.actor_tenant_id, 'application_user', event_type, 'team_membership',
    correlation_id, 'user_command', actor.actor_user_id, null, entity_id,
    idem.acquired_command_id, null, 1, command_reason,
    pg_catalog.jsonb_build_object(
      'version', entity_version, 'status', entity_status,
      'team_id', entity_team_id, 'membership_id', entity_membership_id
    )
  );
  perform private.append_history(
    actor.actor_tenant_id, 'team_membership', entity_id, event_type,
    'application_user', command_name, idem.acquired_command_id, correlation_id,
    'user_command', entity_version, null, 1, actor.actor_user_id, null, null,
    pg_catalog.jsonb_build_object(
      'status', entity_status, 'team_id', entity_team_id,
      'membership_id', entity_membership_id
    )
  );
  perform private.enqueue_event(
    actor.actor_tenant_id, event_type, 'application_user', 'user_command',
    idem.acquired_command_id, correlation_id, 'team_membership', entity_id, 1,
    entity_version, actor.actor_user_id, null, null,
    pg_catalog.jsonb_build_object(
      'id', entity_id, 'version', entity_version, 'status', entity_status,
      'team_id', entity_team_id, 'membership_id', entity_membership_id
    ),
    pg_catalog.jsonb_build_object('command', command_name)
  );

  result := pg_catalog.jsonb_build_object(
    'id', entity_id,
    'version', entity_version,
    'status', entity_status,
    'command_correlation_id', correlation_id
  );
  perform private.complete_command_idempotency(idem.acquired_command_id, 1, result);
  return result;
end;
$$;

-- Explicit public commands. Actor and tenant are always database-derived.
create function public.create_team(
  sector_id uuid, code text, name text, description text, reason text,
  correlation_id uuid, idempotency_key text
)
returns jsonb language sql security definer set search_path = '' as $$
  select private.execute_team_command(
    'create', null, null, sector_id, code, name, description,
    reason, correlation_id, idempotency_key
  )
$$;
create function public.update_team(
  id uuid, expected_version bigint, sector_id uuid, code text, name text,
  description text, reason text, correlation_id uuid, idempotency_key text
)
returns jsonb language sql security definer set search_path = '' as $$
  select private.execute_team_command(
    'update', id, expected_version, sector_id, code, name, description,
    reason, correlation_id, idempotency_key
  )
$$;
create function public.inactivate_team(
  id uuid, expected_version bigint, reason text, correlation_id uuid,
  idempotency_key text
)
returns jsonb language sql security definer set search_path = '' as $$
  select private.execute_team_command(
    'inactivate', id, expected_version, null, null, null, null,
    reason, correlation_id, idempotency_key
  )
$$;
create function public.reactivate_team(
  id uuid, expected_version bigint, reason text, correlation_id uuid,
  idempotency_key text
)
returns jsonb language sql security definer set search_path = '' as $$
  select private.execute_team_command(
    'reactivate', id, expected_version, null, null, null, null,
    reason, correlation_id, idempotency_key
  )
$$;
create function public.add_team_member(
  team_id uuid, membership_id uuid, reason text, correlation_id uuid,
  idempotency_key text
)
returns jsonb language sql security definer set search_path = '' as $$
  select private.execute_team_membership_command(
    'add', null, team_id, membership_id, null, reason, correlation_id,
    idempotency_key
  )
$$;
create function public.end_team_member(
  id uuid, expected_version bigint, reason text, correlation_id uuid,
  idempotency_key text
)
returns jsonb language sql security definer set search_path = '' as $$
  select private.execute_team_membership_command(
    'end', id, null, null, expected_version, reason, correlation_id,
    idempotency_key
  )
$$;

-- Read models. Administrative roster reads never piggyback on teams read/lookup.
create function public.list_teams(
  search_text text default null,
  status_filter text default null,
  result_limit integer default 50,
  result_offset integer default 0
)
returns table(
  id uuid, sector_id uuid, code text, name text, description text,
  status text, version bigint, updated_at timestamptz
)
language plpgsql security definer set search_path = '' as $$
begin
  if result_limit not between 1 and 100 or result_offset < 0
     or (status_filter is not null and status_filter not in ('active', 'inactive')) then
    raise exception using errcode = '22023', message = 'INVALID_QUERY_INPUT';
  end if;
  return query
  select team.id, team.sector_id, team.code, team.name, team.description,
         team.status, team.version, team.updated_at
  from public.teams as team
  where private.can_access_team(team.id, 'read')
    and (status_filter is null or team.status = status_filter)
    and (
      search_text is null
      or team.name ilike '%' || search_text || '%'
      or team.code ilike '%' || search_text || '%'
    )
  order by team.name, team.id
  limit result_limit offset result_offset;
end;
$$;

create function public.get_team(target_id uuid)
returns table(
  id uuid, sector_id uuid, code text, name text, description text,
  status text, version bigint, created_at timestamptz, updated_at timestamptz
)
language sql stable security definer set search_path = '' as $$
  select team.id, team.sector_id, team.code, team.name, team.description,
         team.status, team.version, team.created_at, team.updated_at
  from public.teams as team
  where team.id = target_id and private.can_access_team(team.id, 'read')
$$;

create function public.lookup_teams(
  search_text text default null,
  result_limit integer default 20
)
returns table(id uuid, code text, name text)
language plpgsql security definer set search_path = '' as $$
begin
  if result_limit not between 1 and 100 then
    raise exception using errcode = '22023', message = 'INVALID_QUERY_INPUT';
  end if;
  return query
  select team.id, team.code, team.name
  from public.teams as team
  where team.status = 'active'
    and private.can_access_team(team.id, 'lookup')
    and (
      search_text is null
      or team.name ilike '%' || search_text || '%'
      or team.code ilike '%' || search_text || '%'
    )
  order by team.name, team.id
  limit result_limit;
end;
$$;

create function public.list_my_teams()
returns table(id uuid, sector_id uuid, code text, name text)
language sql stable security definer set search_path = '' as $$
  select team.id, team.sector_id, team.code, team.name
  from public.teams as team
  where team.status = 'active'
    and private.has_effective_permission(
      'teams', 'lookup', 'TEAM'::public.authorization_scope
    )
    and private.team_reaches(team.id)
  order by team.name, team.id
$$;

create function public.list_team_members(
  target_team_id uuid,
  status_filter text default null,
  result_limit integer default 50,
  result_offset integer default 0
)
returns table(
  id uuid, team_id uuid, membership_id uuid, user_id uuid, display_name text,
  status text, joined_at timestamptz, ended_at timestamptz, version bigint
)
language plpgsql security definer set search_path = '' as $$
declare
  actor_tenant_id uuid;
begin
  actor_tenant_id := private.assert_w4b_all_tenant_access(
    'team_memberships', 'read'
  );
  if result_limit not between 1 and 100 or result_offset < 0
     or (status_filter is not null and status_filter not in ('active', 'ended')) then
    raise exception using errcode = '22023', message = 'INVALID_QUERY_INPUT';
  end if;
  if not exists (
    select 1 from public.teams as team
    where team.tenant_id = actor_tenant_id and team.id = target_team_id
  ) then
    raise exception using errcode = 'P0001', message = 'TEAM_UNAVAILABLE';
  end if;
  return query
  select association.id, association.team_id, association.membership_id,
         membership.user_id, app_user.display_name, association.status,
         association.joined_at, association.ended_at, association.version
  from public.team_memberships as association
  join public.tenant_memberships as membership
    on membership.tenant_id = association.tenant_id
   and membership.id = association.membership_id
  join public.app_users as app_user on app_user.id = membership.user_id
  where association.tenant_id = actor_tenant_id
    and association.team_id = target_team_id
    and (status_filter is null or association.status = status_filter)
  order by association.joined_at desc, association.id
  limit result_limit offset result_offset;
end;
$$;

create function public.list_teams_for_membership(
  target_membership_id uuid,
  status_filter text default null,
  result_limit integer default 50,
  result_offset integer default 0
)
returns table(
  association_id uuid, team_id uuid, sector_id uuid, code text, name text,
  membership_status text, joined_at timestamptz, ended_at timestamptz,
  membership_version bigint
)
language plpgsql security definer set search_path = '' as $$
declare
  actor_tenant_id uuid;
begin
  actor_tenant_id := private.assert_w4b_all_tenant_access(
    'team_memberships', 'read'
  );
  if result_limit not between 1 and 100 or result_offset < 0
     or (status_filter is not null and status_filter not in ('active', 'ended')) then
    raise exception using errcode = '22023', message = 'INVALID_QUERY_INPUT';
  end if;
  if not exists (
    select 1 from public.tenant_memberships as membership
    where membership.tenant_id = actor_tenant_id
      and membership.id = target_membership_id
  ) then
    raise exception using errcode = 'P0001', message = 'MEMBERSHIP_UNAVAILABLE';
  end if;
  return query
  select association.id, team.id, team.sector_id, team.code, team.name,
         association.status, association.joined_at, association.ended_at,
         association.version
  from public.team_memberships as association
  join public.teams as team
    on team.tenant_id = association.tenant_id and team.id = association.team_id
  where association.tenant_id = actor_tenant_id
    and association.membership_id = target_membership_id
    and (status_filter is null or association.status = status_filter)
  order by team.name, association.joined_at desc, association.id
  limit result_limit offset result_offset;
end;
$$;

-- Ownership and grants close all privileged helpers and expose only explicit RPCs.
alter function private.protect_team_mutation() owner to postgres;
alter function private.enforce_team_integrity() owner to postgres;
alter function private.protect_team_membership_mutation() owner to postgres;
alter function private.enforce_team_membership_integrity() owner to postgres;
alter function private.bump_tenant_membership_revision_for_team() owner to postgres;
alter function private.protect_sector_team_dependency() owner to postgres;
alter function private.team_reaches(uuid) owner to postgres;
alter function private.can_access_team(uuid, text) owner to postgres;
alter function private.assert_w4b_all_tenant_access(text, text) owner to postgres;
alter function private.execute_team_command(text,uuid,bigint,uuid,text,text,text,text,uuid,text) owner to postgres;
alter function private.execute_team_membership_command(text,uuid,uuid,uuid,bigint,text,uuid,text) owner to postgres;

revoke all on function private.protect_team_mutation() from public, anon, authenticated, service_role, cw_worker;
revoke all on function private.enforce_team_integrity() from public, anon, authenticated, service_role, cw_worker;
revoke all on function private.protect_team_membership_mutation() from public, anon, authenticated, service_role, cw_worker;
revoke all on function private.enforce_team_membership_integrity() from public, anon, authenticated, service_role, cw_worker;
revoke all on function private.bump_tenant_membership_revision_for_team() from public, anon, authenticated, service_role, cw_worker;
revoke all on function private.protect_sector_team_dependency() from public, anon, authenticated, service_role, cw_worker;
revoke all on function private.team_reaches(uuid) from public, anon, authenticated, service_role, cw_worker;
revoke all on function private.can_access_team(uuid,text) from public, anon, authenticated, service_role, cw_worker;
revoke all on function private.assert_w4b_all_tenant_access(text,text) from public, anon, authenticated, service_role, cw_worker;
revoke all on function private.execute_team_command(text,uuid,bigint,uuid,text,text,text,text,uuid,text) from public, anon, authenticated, service_role, cw_worker;
revoke all on function private.execute_team_membership_command(text,uuid,uuid,uuid,bigint,text,uuid,text) from public, anon, authenticated, service_role, cw_worker;

alter function public.create_team(uuid,text,text,text,text,uuid,text) owner to postgres;
alter function public.update_team(uuid,bigint,uuid,text,text,text,text,uuid,text) owner to postgres;
alter function public.inactivate_team(uuid,bigint,text,uuid,text) owner to postgres;
alter function public.reactivate_team(uuid,bigint,text,uuid,text) owner to postgres;
alter function public.add_team_member(uuid,uuid,text,uuid,text) owner to postgres;
alter function public.end_team_member(uuid,bigint,text,uuid,text) owner to postgres;
alter function public.list_teams(text,text,integer,integer) owner to postgres;
alter function public.get_team(uuid) owner to postgres;
alter function public.lookup_teams(text,integer) owner to postgres;
alter function public.list_my_teams() owner to postgres;
alter function public.list_team_members(uuid,text,integer,integer) owner to postgres;
alter function public.list_teams_for_membership(uuid,text,integer,integer) owner to postgres;

revoke all on function public.create_team(uuid,text,text,text,text,uuid,text) from public, anon, authenticated, service_role, cw_worker;
revoke all on function public.update_team(uuid,bigint,uuid,text,text,text,text,uuid,text) from public, anon, authenticated, service_role, cw_worker;
revoke all on function public.inactivate_team(uuid,bigint,text,uuid,text) from public, anon, authenticated, service_role, cw_worker;
revoke all on function public.reactivate_team(uuid,bigint,text,uuid,text) from public, anon, authenticated, service_role, cw_worker;
revoke all on function public.add_team_member(uuid,uuid,text,uuid,text) from public, anon, authenticated, service_role, cw_worker;
revoke all on function public.end_team_member(uuid,bigint,text,uuid,text) from public, anon, authenticated, service_role, cw_worker;
revoke all on function public.list_teams(text,text,integer,integer) from public, anon, authenticated, service_role, cw_worker;
revoke all on function public.get_team(uuid) from public, anon, authenticated, service_role, cw_worker;
revoke all on function public.lookup_teams(text,integer) from public, anon, authenticated, service_role, cw_worker;
revoke all on function public.list_my_teams() from public, anon, authenticated, service_role, cw_worker;
revoke all on function public.list_team_members(uuid,text,integer,integer) from public, anon, authenticated, service_role, cw_worker;
revoke all on function public.list_teams_for_membership(uuid,text,integer,integer) from public, anon, authenticated, service_role, cw_worker;

grant execute on function public.create_team(uuid,text,text,text,text,uuid,text) to authenticated;
grant execute on function public.update_team(uuid,bigint,uuid,text,text,text,text,uuid,text) to authenticated;
grant execute on function public.inactivate_team(uuid,bigint,text,uuid,text) to authenticated;
grant execute on function public.reactivate_team(uuid,bigint,text,uuid,text) to authenticated;
grant execute on function public.add_team_member(uuid,uuid,text,uuid,text) to authenticated;
grant execute on function public.end_team_member(uuid,bigint,text,uuid,text) to authenticated;
grant execute on function public.list_teams(text,text,integer,integer) to authenticated;
grant execute on function public.get_team(uuid) to authenticated;
grant execute on function public.lookup_teams(text,integer) to authenticated;
grant execute on function public.list_my_teams() to authenticated;
grant execute on function public.list_team_members(uuid,text,integer,integer) to authenticated;
grant execute on function public.list_teams_for_membership(uuid,text,integer,integer) to authenticated;
