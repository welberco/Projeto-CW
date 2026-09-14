-- W2B / W2-03: tenant-owned authorization profiles and their baseline grants.

create table public.tenant_profiles (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  name text not null,
  template_key text,
  template_version bigint,
  status text not null default 'active',
  version bigint not null default 1,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  created_by uuid,
  updated_by uuid,
  inactivated_at timestamptz,
  constraint tenant_profiles_tenant_fk
    foreign key (tenant_id)
    references public.tenants (id)
    on delete restrict,
  constraint tenant_profiles_created_by_fk
    foreign key (created_by)
    references public.app_users (id)
    on delete restrict,
  constraint tenant_profiles_updated_by_fk
    foreign key (updated_by)
    references public.app_users (id)
    on delete restrict,
  constraint tenant_profiles_name_not_blank_ck
    check (name = btrim(name) and char_length(name) between 1 and 120),
  constraint tenant_profiles_template_key_format_ck
    check (
      template_key is null
      or template_key ~ '^[a-z][a-z0-9_]{1,63}$'
    ),
  constraint tenant_profiles_template_provenance_ck
    check (
      (template_key is null and template_version is null)
      or (template_key is not null and template_version is not null and template_version > 0)
    ),
  constraint tenant_profiles_status_ck
    check (status in ('active', 'inactive')),
  constraint tenant_profiles_version_positive_ck
    check (version > 0),
  constraint tenant_profiles_lifecycle_ck
    check (
      (status = 'active' and inactivated_at is null)
      or (status = 'inactive' and inactivated_at is not null)
    ),
  constraint tenant_profiles_tenant_id_id_uq unique (tenant_id, id)
);

create unique index tenant_profiles_active_name_uq
  on public.tenant_profiles (tenant_id, lower(btrim(name)))
  where status = 'active';

create unique index tenant_profiles_template_key_uq
  on public.tenant_profiles (tenant_id, template_key)
  where template_key is not null;

create index tenant_profiles_tenant_status_idx
  on public.tenant_profiles (tenant_id, status, name);

create table public.tenant_profile_permissions (
  tenant_id uuid not null,
  profile_id uuid not null,
  permission_id uuid not null,
  created_at timestamptz not null default clock_timestamp(),
  created_by uuid,
  constraint tenant_profile_permissions_pk
    primary key (profile_id, permission_id),
  constraint tenant_profile_permissions_profile_fk
    foreign key (tenant_id, profile_id)
    references public.tenant_profiles (tenant_id, id)
    on delete restrict,
  constraint tenant_profile_permissions_permission_fk
    foreign key (permission_id)
    references public.permission_catalog (id)
    on delete restrict,
  constraint tenant_profile_permissions_created_by_fk
    foreign key (created_by)
    references public.app_users (id)
    on delete restrict
);

create index tenant_profile_permissions_tenant_permission_idx
  on public.tenant_profile_permissions (tenant_id, permission_id, profile_id);

create or replace function private.protect_tenant_profile_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception using
      errcode = '23514',
      message = 'TENANT_PROFILE_DELETE_FORBIDDEN';
  end if;

  if new.id is distinct from old.id
     or new.tenant_id is distinct from old.tenant_id
     or new.template_key is distinct from old.template_key
     or new.template_version is distinct from old.template_version then
    raise exception using
      errcode = '23514',
      message = 'TENANT_PROFILE_IDENTITY_IMMUTABLE';
  end if;

  if new.version is distinct from old.version then
    raise exception using
      errcode = '23514',
      message = 'TENANT_PROFILE_VERSION_MANAGED';
  end if;

  return new;
end;
$$;

create trigger tenant_profiles_protect_mutation
before update or delete on public.tenant_profiles
for each row
execute function private.protect_tenant_profile_mutation();

create trigger tenant_profiles_set_updated_at_and_version
before update on public.tenant_profiles
for each row
execute function private.set_updated_at_and_version();

create or replace function private.protect_tenant_profile_permission_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    raise exception using
      errcode = '23514',
      message = 'TENANT_PROFILE_PERMISSION_IDENTITY_IMMUTABLE';
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
      message = 'TENANT_PROFILE_PERMISSION_NOT_ACTIVE';
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create trigger tenant_profile_permissions_protect_mutation
before insert or update or delete on public.tenant_profile_permissions
for each row
execute function private.protect_tenant_profile_permission_mutation();

create or replace function private.bump_tenant_profile_version_for_baseline()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  profile_to_bump uuid;
begin
  profile_to_bump := case when tg_op = 'DELETE' then old.profile_id else new.profile_id end;

  update public.tenant_profiles
  set updated_by = case when tg_op = 'DELETE' then old.created_by else new.created_by end
  where id = profile_to_bump;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create trigger tenant_profile_permissions_bump_profile_version
after insert or delete on public.tenant_profile_permissions
for each row
execute function private.bump_tenant_profile_version_for_baseline();

alter table public.tenant_profiles enable row level security;
alter table public.tenant_profile_permissions enable row level security;

revoke all on table public.tenant_profiles from public, anon, authenticated, service_role;
revoke all on table public.tenant_profile_permissions from public, anon, authenticated, service_role;

revoke all on function private.protect_tenant_profile_mutation() from public, anon, authenticated, service_role;
revoke all on function private.protect_tenant_profile_permission_mutation() from public, anon, authenticated, service_role;
revoke all on function private.bump_tenant_profile_version_for_baseline() from public, anon, authenticated, service_role;
