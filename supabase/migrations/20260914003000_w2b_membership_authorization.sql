-- W2B / W2-04: profile assignments, per-membership overrides and invitation targets.

alter table public.tenant_memberships
  add column profile_id uuid,
  add column profile_assigned_at timestamptz,
  add column profile_assigned_by uuid,
  add constraint tenant_memberships_tenant_id_id_uq unique (tenant_id, id),
  add constraint tenant_memberships_profile_assignment_ck
    check (
      (profile_id is null and profile_assigned_at is null and profile_assigned_by is null)
      or (profile_id is not null and profile_assigned_at is not null)
    ) not valid,
  add constraint tenant_memberships_profile_fk
    foreign key (tenant_id, profile_id)
    references public.tenant_profiles (tenant_id, id)
    on delete restrict
    not valid,
  add constraint tenant_memberships_profile_assigned_by_fk
    foreign key (profile_assigned_by)
    references public.app_users (id)
    on delete restrict
    not valid;

create index tenant_memberships_tenant_profile_status_idx
  on public.tenant_memberships (tenant_id, profile_id, status);

alter table public.tenant_invitations
  add column target_profile_id uuid,
  add constraint tenant_invitations_target_profile_fk
    foreign key (tenant_id, target_profile_id)
    references public.tenant_profiles (tenant_id, id)
    on delete restrict
    not valid;

create index tenant_invitations_tenant_target_profile_status_idx
  on public.tenant_invitations (tenant_id, target_profile_id, status);

create table public.tenant_permission_overrides (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  membership_id uuid not null,
  permission_id uuid not null,
  effect text not null,
  version bigint not null default 1,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  created_by uuid,
  updated_by uuid,
  constraint tenant_permission_overrides_membership_fk
    foreign key (tenant_id, membership_id)
    references public.tenant_memberships (tenant_id, id)
    on delete restrict,
  constraint tenant_permission_overrides_permission_fk
    foreign key (permission_id)
    references public.permission_catalog (id)
    on delete restrict,
  constraint tenant_permission_overrides_created_by_fk
    foreign key (created_by)
    references public.app_users (id)
    on delete restrict,
  constraint tenant_permission_overrides_updated_by_fk
    foreign key (updated_by)
    references public.app_users (id)
    on delete restrict,
  constraint tenant_permission_overrides_effect_ck
    check (effect in ('allow', 'deny')),
  constraint tenant_permission_overrides_version_positive_ck
    check (version > 0),
  constraint tenant_permission_overrides_membership_permission_uq
    unique (membership_id, permission_id)
);

create index tenant_permission_overrides_tenant_permission_idx
  on public.tenant_permission_overrides (tenant_id, permission_id, membership_id);

create or replace function private.protect_tenant_permission_override_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE'
     and (
       new.id is distinct from old.id
       or new.tenant_id is distinct from old.tenant_id
       or new.membership_id is distinct from old.membership_id
       or new.permission_id is distinct from old.permission_id
       or new.version is distinct from old.version
       or new.created_at is distinct from old.created_at
       or new.created_by is distinct from old.created_by
     ) then
    raise exception using
      errcode = '23514',
      message = 'TENANT_PERMISSION_OVERRIDE_IDENTITY_IMMUTABLE';
  end if;

  if tg_op = 'INSERT'
     and not exists (
       select 1
       from public.permission_catalog pc
       where pc.id = new.permission_id
         and pc.status = 'active'
     ) then
    raise exception using
      errcode = '23514',
      message = 'TENANT_PERMISSION_OVERRIDE_PERMISSION_NOT_ACTIVE';
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create trigger tenant_permission_overrides_protect_mutation
before insert or update or delete on public.tenant_permission_overrides
for each row
execute function private.protect_tenant_permission_override_mutation();

create trigger tenant_permission_overrides_set_updated_at_and_version
before update on public.tenant_permission_overrides
for each row
execute function private.set_updated_at_and_version();

create or replace function private.bump_membership_version_for_override()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  membership_to_bump uuid;
begin
  membership_to_bump := case when tg_op = 'DELETE' then old.membership_id else new.membership_id end;

  update public.tenant_memberships
  set updated_at = clock_timestamp()
  where id = membership_to_bump;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create trigger tenant_permission_overrides_bump_membership_version
after insert or update or delete on public.tenant_permission_overrides
for each row
execute function private.bump_membership_version_for_override();

alter table public.tenant_permission_overrides enable row level security;

revoke all on table public.tenant_permission_overrides from public, anon, authenticated, service_role;

revoke all on function private.protect_tenant_permission_override_mutation() from public, anon, authenticated, service_role;
revoke all on function private.bump_membership_version_for_override() from public, anon, authenticated, service_role;
