-- CW ERP V2 / W1A: tenant relationships and minimum append-only audit.

create table public.tenant_memberships (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  user_id uuid not null references public.app_users (id) on delete restrict,
  status text not null,
  joined_at timestamptz not null,
  blocked_at timestamptz,
  revoked_at timestamptz,
  created_by uuid not null references public.app_users (id) on delete restrict,
  created_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(),
  version bigint not null default 1,
  constraint tenant_memberships_status_check check (
    status in ('active', 'blocked', 'revoked')
  ),
  constraint tenant_memberships_lifecycle_check check (
    (status = 'active' and blocked_at is null and revoked_at is null)
    or (status = 'blocked' and blocked_at is not null and revoked_at is null)
    or (status = 'revoked' and revoked_at is not null)
  ),
  constraint tenant_memberships_version_check check (version > 0)
);

create unique index tenant_memberships_one_operational_per_user_uidx
on public.tenant_memberships (user_id)
where status in ('active', 'blocked');

create unique index tenant_memberships_one_operational_pair_uidx
on public.tenant_memberships (tenant_id, user_id)
where status in ('active', 'blocked');

create index tenant_memberships_user_status_idx
on public.tenant_memberships (user_id, status);

create index tenant_memberships_tenant_status_idx
on public.tenant_memberships (tenant_id, status);

create table public.tenant_invitations (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  invite_ref uuid not null default pg_catalog.gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  recipient_email_hash text not null,
  invited_user_id uuid references public.app_users (id) on delete restrict,
  status text not null default 'pending',
  expires_at timestamptz not null,
  accepted_at timestamptz,
  revoked_at timestamptz,
  created_by uuid not null references public.app_users (id) on delete restrict,
  created_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(),
  version bigint not null default 1,
  constraint tenant_invitations_invite_ref_key unique (invite_ref),
  constraint tenant_invitations_email_hash_check check (
    recipient_email_hash ~ '^[0-9a-f]{64}$'
  ),
  constraint tenant_invitations_status_check check (
    status in ('pending', 'accepted', 'revoked', 'expired')
  ),
  constraint tenant_invitations_expiry_check check (expires_at > created_at),
  constraint tenant_invitations_lifecycle_check check (
    (status = 'pending' and accepted_at is null and revoked_at is null)
    or (
      status = 'accepted'
      and accepted_at is not null
      and revoked_at is null
      and invited_user_id is not null
    )
    or (status = 'revoked' and accepted_at is null and revoked_at is not null)
    or (status = 'expired' and accepted_at is null and revoked_at is null)
  ),
  constraint tenant_invitations_version_check check (version > 0)
);

create unique index tenant_invitations_one_pending_email_uidx
on public.tenant_invitations (tenant_id, recipient_email_hash)
where status = 'pending';

create unique index tenant_invitations_one_pending_user_uidx
on public.tenant_invitations (tenant_id, invited_user_id)
where status = 'pending' and invited_user_id is not null;

create index tenant_invitations_tenant_status_idx
on public.tenant_invitations (tenant_id, status);

create table public.tenant_entitlements (
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  module_key text not null,
  enabled boolean not null,
  created_by uuid not null references public.app_users (id) on delete restrict,
  created_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(),
  version bigint not null default 1,
  primary key (tenant_id, module_key),
  constraint tenant_entitlements_module_key_check check (
    char_length(module_key) between 1 and 64
    and module_key ~ '^[a-z][a-z0-9_]*$'
  ),
  constraint tenant_entitlements_version_check check (version > 0)
);

create table public.audit_events (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  occurred_at timestamptz not null default statement_timestamp(),
  tenant_id uuid references public.tenants (id) on delete restrict,
  actor_user_id uuid references public.app_users (id) on delete restrict,
  actor_kind text not null,
  correlation_id uuid not null default pg_catalog.gen_random_uuid(),
  event_type text not null,
  entity_type text not null,
  entity_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  constraint audit_events_actor_kind_check check (
    actor_kind in ('application_user', 'technical', 'platform')
  ),
  constraint audit_events_actor_check check (
    (actor_kind = 'application_user' and actor_user_id is not null)
    or (actor_kind in ('technical', 'platform'))
  ),
  constraint audit_events_event_type_check check (
    char_length(event_type) between 1 and 120
    and event_type ~ '^[a-z][a-z0-9_.]*$'
  ),
  constraint audit_events_entity_type_check check (
    char_length(entity_type) between 1 and 80
    and entity_type ~ '^[a-z][a-z0-9_]*$'
  ),
  constraint audit_events_metadata_check check (
    jsonb_typeof(metadata) = 'object'
  )
);

create index audit_events_tenant_occurred_at_idx
on public.audit_events (tenant_id, occurred_at desc);

create index audit_events_target_idx
on public.audit_events (entity_type, entity_id, occurred_at desc);

create trigger tenant_memberships_set_updated_at_and_version
before update on public.tenant_memberships
for each row
execute function private.set_updated_at_and_version();

create trigger tenant_invitations_set_updated_at_and_version
before update on public.tenant_invitations
for each row
execute function private.set_updated_at_and_version();

create trigger tenant_entitlements_set_updated_at_and_version
before update on public.tenant_entitlements
for each row
execute function private.set_updated_at_and_version();

create function private.reject_audit_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using
    errcode = '55000',
    message = 'audit_events is append-only';
end;
$$;

revoke all on function private.reject_audit_mutation() from public;
revoke all on function private.reject_audit_mutation() from anon;
revoke all on function private.reject_audit_mutation() from authenticated;

create trigger audit_events_reject_update_delete
before update or delete on public.audit_events
for each row
execute function private.reject_audit_mutation();

create trigger audit_events_reject_truncate
before truncate on public.audit_events
for each statement
execute function private.reject_audit_mutation();

alter table public.tenant_memberships enable row level security;
alter table public.tenant_invitations enable row level security;
alter table public.tenant_entitlements enable row level security;
alter table public.audit_events enable row level security;

revoke all privileges on table public.tenant_memberships from public;
revoke all privileges on table public.tenant_memberships from anon;
revoke all privileges on table public.tenant_memberships from authenticated;
revoke all privileges on table public.tenant_invitations from public;
revoke all privileges on table public.tenant_invitations from anon;
revoke all privileges on table public.tenant_invitations from authenticated;
revoke all privileges on table public.tenant_entitlements from public;
revoke all privileges on table public.tenant_entitlements from anon;
revoke all privileges on table public.tenant_entitlements from authenticated;
revoke all privileges on table public.audit_events from public;
revoke all privileges on table public.audit_events from anon;
revoke all privileges on table public.audit_events from authenticated;

comment on table public.tenant_memberships is
  'Historical User-Tenant relationship; partial indexes allow at most one operational membership per common user.';
comment on table public.tenant_invitations is
  'Invitation lifecycle without reusable plaintext Auth tokens.';
comment on table public.tenant_entitlements is
  'Minimum tenant module availability. Commercial plans and limits are outside W1.';
comment on table public.audit_events is
  'Minimum append-only W1 audit substrate; W3 expands it without creating a competing log.';
