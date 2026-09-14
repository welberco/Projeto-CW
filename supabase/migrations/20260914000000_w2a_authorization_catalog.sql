-- CW ERP V2 / W2A: platform-owned authorization vocabulary and catalog.

create type public.authorization_scope as enum (
  'OWN',
  'ASSIGNED',
  'TEAM',
  'ALL_TENANT'
);

revoke all on type public.authorization_scope from public;
revoke all on type public.authorization_scope from anon;
revoke all on type public.authorization_scope from authenticated;
revoke all on type public.authorization_scope from service_role;

create table private.authorization_catalog_state (
  singleton boolean primary key default true,
  catalog_revision bigint not null default 1,
  created_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(),
  constraint authorization_catalog_state_singleton_check check (singleton),
  constraint authorization_catalog_state_revision_check check (
    catalog_revision > 0
  ),
  constraint authorization_catalog_state_timestamps_check check (
    updated_at >= created_at
  )
);

insert into private.authorization_catalog_state (singleton, catalog_revision)
values (true, 1);

create table public.permission_catalog (
  id uuid primary key,
  code text not null,
  module_code text not null,
  resource_code text not null,
  action_code text not null,
  scope public.authorization_scope not null,
  required_entitlement_key text,
  tenant_delegable boolean not null default false,
  label_key text not null,
  description_key text,
  status text not null default 'active',
  created_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(),
  deprecated_at timestamptz,
  constraint permission_catalog_code_key unique (code),
  constraint permission_catalog_combination_key unique (
    module_code,
    resource_code,
    action_code,
    scope
  ),
  constraint permission_catalog_module_code_check check (
    module_code ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
  ),
  constraint permission_catalog_resource_code_check check (
    resource_code ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
  ),
  constraint permission_catalog_action_code_check check (
    action_code ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
  ),
  constraint permission_catalog_code_check check (
    code = module_code || '.' || resource_code || '.' || action_code || '.' ||
      pg_catalog.lower(scope::text)
  ),
  constraint permission_catalog_entitlement_key_check check (
    required_entitlement_key is null
    or required_entitlement_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
  ),
  constraint permission_catalog_label_key_check check (
    label_key ~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$'
  ),
  constraint permission_catalog_description_key_check check (
    description_key is null
    or description_key ~ '^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$'
  ),
  constraint permission_catalog_status_check check (
    status in ('active', 'deprecated')
  ),
  constraint permission_catalog_lifecycle_check check (
    (status = 'active' and deprecated_at is null)
    or (status = 'deprecated' and deprecated_at is not null)
  ),
  constraint permission_catalog_timestamps_check check (
    updated_at >= created_at
    and (deprecated_at is null or deprecated_at >= created_at)
  )
);

create table private.authorization_profile_templates (
  id uuid primary key,
  template_key text not null,
  template_version bigint not null,
  default_name text not null,
  status text not null default 'active',
  created_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(),
  deprecated_at timestamptz,
  constraint authorization_profile_templates_key_key unique (template_key),
  constraint authorization_profile_templates_key_check check (
    template_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
  ),
  constraint authorization_profile_templates_version_check check (
    template_version > 0
  ),
  constraint authorization_profile_templates_name_check check (
    char_length(btrim(default_name)) between 1 and 120
    and default_name = btrim(default_name)
  ),
  constraint authorization_profile_templates_status_check check (
    status in ('active', 'deprecated')
  ),
  constraint authorization_profile_templates_lifecycle_check check (
    (status = 'active' and deprecated_at is null)
    or (status = 'deprecated' and deprecated_at is not null)
  ),
  constraint authorization_profile_templates_timestamps_check check (
    updated_at >= created_at
    and (deprecated_at is null or deprecated_at >= created_at)
  )
);

create table private.authorization_profile_template_permissions (
  template_id uuid not null
    references private.authorization_profile_templates (id) on delete restrict,
  permission_id uuid not null
    references public.permission_catalog (id) on delete restrict,
  created_at timestamptz not null default statement_timestamp(),
  primary key (template_id, permission_id)
);

create index authorization_profile_template_permissions_permission_idx
on private.authorization_profile_template_permissions (permission_id);

create function private.protect_authorization_catalog_state()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception using
      errcode = 'P0001',
      message = 'AUTHORIZATION_CATALOG_STATE_DELETE_FORBIDDEN';
  end if;

  if new.singleton is distinct from old.singleton
     or new.catalog_revision <= old.catalog_revision then
    raise exception using
      errcode = 'P0001',
      message = 'AUTHORIZATION_CATALOG_REVISION_MUST_INCREASE';
  end if;

  new.updated_at := statement_timestamp();
  return new;
end;
$$;

create trigger authorization_catalog_state_protect
before update or delete on private.authorization_catalog_state
for each row
execute function private.protect_authorization_catalog_state();

create function private.protect_permission_catalog_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception using
      errcode = 'P0001',
      message = 'PERMISSION_CATALOG_HARD_DELETE_FORBIDDEN';
  end if;

  if new.id is distinct from old.id
     or new.code is distinct from old.code
     or new.module_code is distinct from old.module_code
     or new.resource_code is distinct from old.resource_code
     or new.action_code is distinct from old.action_code
     or new.scope is distinct from old.scope then
    raise exception using
      errcode = 'P0001',
      message = 'PERMISSION_CATALOG_IDENTITY_IMMUTABLE';
  end if;

  new.updated_at := statement_timestamp();
  return new;
end;
$$;

create trigger permission_catalog_protect_mutation
before update or delete on public.permission_catalog
for each row
execute function private.protect_permission_catalog_mutation();

create function private.bump_authorization_catalog_revision()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  update private.authorization_catalog_state
  set catalog_revision = catalog_revision + 1
  where singleton;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'AUTHORIZATION_CATALOG_STATE_UNAVAILABLE';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end;
$$;

create trigger permission_catalog_bump_revision
after insert or update or delete on public.permission_catalog
for each row
execute function private.bump_authorization_catalog_revision();

alter table public.permission_catalog enable row level security;

revoke all privileges on table public.permission_catalog from public;
revoke all privileges on table public.permission_catalog from anon;
revoke all privileges on table public.permission_catalog from authenticated;
revoke all privileges on table public.permission_catalog from service_role;
revoke all privileges on table private.authorization_catalog_state from public;
revoke all privileges on table private.authorization_catalog_state from anon;
revoke all privileges on table private.authorization_catalog_state from authenticated;
revoke all privileges on table private.authorization_catalog_state from service_role;
revoke all privileges on table private.authorization_profile_templates from public;
revoke all privileges on table private.authorization_profile_templates from anon;
revoke all privileges on table private.authorization_profile_templates from authenticated;
revoke all privileges on table private.authorization_profile_templates from service_role;
revoke all privileges on table private.authorization_profile_template_permissions from public;
revoke all privileges on table private.authorization_profile_template_permissions from anon;
revoke all privileges on table private.authorization_profile_template_permissions from authenticated;
revoke all privileges on table private.authorization_profile_template_permissions from service_role;

revoke all on function private.protect_authorization_catalog_state() from public;
revoke all on function private.protect_authorization_catalog_state() from anon;
revoke all on function private.protect_authorization_catalog_state() from authenticated;
revoke all on function private.protect_authorization_catalog_state() from service_role;
revoke all on function private.protect_permission_catalog_mutation() from public;
revoke all on function private.protect_permission_catalog_mutation() from anon;
revoke all on function private.protect_permission_catalog_mutation() from authenticated;
revoke all on function private.protect_permission_catalog_mutation() from service_role;
revoke all on function private.bump_authorization_catalog_revision() from public;
revoke all on function private.bump_authorization_catalog_revision() from anon;
revoke all on function private.bump_authorization_catalog_revision() from authenticated;
revoke all on function private.bump_authorization_catalog_revision() from service_role;

comment on type public.authorization_scope is
  'Exact tenant authorization scope taxonomy. Values have no authorization hierarchy or precedence.';
comment on table public.permission_catalog is
  'Platform-owned catalog with one stable row for each valid Resource + Action + Scope combination.';
comment on column public.permission_catalog.code is
  'Stable machine code <module>.<resource>.<action>.<scope>; labels never authorize.';
comment on column public.permission_catalog.required_entitlement_key is
  'Exact entitlement required by a future evaluator; null means no module entitlement requirement.';
comment on column public.permission_catalog.tenant_delegable is
  'Structural metadata for future anti-escalation; it grants no authority by itself.';
comment on table private.authorization_catalog_state is
  'Singleton monotonic revision for structural authorization catalog invalidation.';
comment on table private.authorization_profile_templates is
  'Platform-owned versioned profile templates; they are copied during future tenant provisioning and never authorize at runtime.';
comment on table private.authorization_profile_template_permissions is
  'Platform template grants for future provisioning; no tenant or membership grant is created in W2A.';
