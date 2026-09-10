-- CW ERP V2 / W1A: application identity and tenant core.

create schema if not exists private;

revoke all on schema private from public;
revoke all on schema private from anon;
revoke all on schema private from authenticated;
alter default privileges in schema private
revoke execute on functions from public;

create table public.app_users (
  id uuid primary key references auth.users (id) on delete restrict,
  display_name text,
  status text not null default 'active',
  created_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(),
  blocked_at timestamptz,
  inactivated_at timestamptz,
  version bigint not null default 1,
  constraint app_users_display_name_check check (
    display_name is null
    or (
      char_length(btrim(display_name)) between 1 and 160
      and display_name = btrim(display_name)
    )
  ),
  constraint app_users_status_check check (
    status in ('active', 'blocked', 'inactive')
  ),
  constraint app_users_lifecycle_check check (
    (status = 'active' and blocked_at is null and inactivated_at is null)
    or (status = 'blocked' and blocked_at is not null and inactivated_at is null)
    or (status = 'inactive' and inactivated_at is not null)
  ),
  constraint app_users_version_check check (version > 0)
);

create table public.tenants (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  tenant_ref uuid not null default pg_catalog.gen_random_uuid(),
  display_name text not null,
  status text not null,
  created_by uuid not null references public.app_users (id) on delete restrict,
  created_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(),
  suspended_at timestamptz,
  inactivated_at timestamptz,
  version bigint not null default 1,
  constraint tenants_tenant_ref_key unique (tenant_ref),
  constraint tenants_tenant_ref_v4_check check (
    tenant_ref::text ~
      '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  ),
  constraint tenants_display_name_check check (
    char_length(btrim(display_name)) between 1 and 200
    and display_name = btrim(display_name)
  ),
  constraint tenants_status_check check (
    status in ('active', 'suspended', 'inactive')
  ),
  constraint tenants_lifecycle_check check (
    (status = 'active' and suspended_at is null and inactivated_at is null)
    or (status = 'suspended' and suspended_at is not null and inactivated_at is null)
    or (status = 'inactive' and inactivated_at is not null)
  ),
  constraint tenants_version_check check (version > 0)
);

create function private.set_updated_at_and_version()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := statement_timestamp();
  new.version := old.version + 1;
  return new;
end;
$$;

revoke all on function private.set_updated_at_and_version() from public;
revoke all on function private.set_updated_at_and_version() from anon;
revoke all on function private.set_updated_at_and_version() from authenticated;

create trigger app_users_set_updated_at_and_version
before update on public.app_users
for each row
execute function private.set_updated_at_and_version();

create trigger tenants_set_updated_at_and_version
before update on public.tenants
for each row
execute function private.set_updated_at_and_version();

create function private.create_app_user_for_auth_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.app_users (id)
  values (new.id);

  return new;
end;
$$;

revoke all on function private.create_app_user_for_auth_identity() from public;
revoke all on function private.create_app_user_for_auth_identity() from anon;
revoke all on function private.create_app_user_for_auth_identity() from authenticated;

create trigger create_app_user_after_auth_identity
after insert on auth.users
for each row
execute function private.create_app_user_for_auth_identity();

alter table public.app_users enable row level security;
alter table public.tenants enable row level security;

revoke all privileges on table public.app_users from public;
revoke all privileges on table public.app_users from anon;
revoke all privileges on table public.app_users from authenticated;
revoke all privileges on table public.tenants from public;
revoke all privileges on table public.tenants from anon;
revoke all privileges on table public.tenants from authenticated;

comment on table public.app_users is
  'W1 application identity linked 1:1 to Supabase Auth; not an authorization profile.';
comment on column public.tenants.tenant_ref is
  'Opaque public route selector. It never grants tenant authority.';
