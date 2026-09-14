-- W2B / W2-06: finalize profile integrity after the safe provisioning/backfill pass.

create or replace function private.enforce_membership_profile_integrity()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status in ('active', 'blocked') and new.profile_id is null then
    raise exception using
      errcode = '23514',
      message = 'OPERATIONAL_MEMBERSHIP_PROFILE_REQUIRED';
  end if;

  if new.profile_id is null
     and (new.profile_assigned_at is not null or new.profile_assigned_by is not null) then
    raise exception using
      errcode = '23514',
      message = 'MEMBERSHIP_PROFILE_ASSIGNMENT_INCOHERENT';
  end if;

  if new.profile_id is not null and new.profile_assigned_at is null then
    raise exception using
      errcode = '23514',
      message = 'MEMBERSHIP_PROFILE_ASSIGNMENT_INCOHERENT';
  end if;

  if tg_op = 'UPDATE'
     and new.profile_id is distinct from old.profile_id
     and new.profile_assigned_at is not distinct from old.profile_assigned_at then
    raise exception using
      errcode = '23514',
      message = 'MEMBERSHIP_PROFILE_ASSIGNMENT_TIMESTAMP_REQUIRED';
  end if;

  if new.profile_id is not null
     and (
       tg_op = 'INSERT'
       or new.profile_id is distinct from old.profile_id
       or new.tenant_id is distinct from old.tenant_id
       or new.status in ('active', 'blocked')
     ) then
    perform 1
    from public.tenant_profiles as profile
    where profile.id = new.profile_id
      and profile.status = 'active'
    for key share;

    if not found then
      raise exception using
        errcode = '23514',
        message = 'MEMBERSHIP_PROFILE_NOT_ACTIVE';
    end if;
  end if;

  return new;
end;
$$;

create trigger tenant_memberships_enforce_profile_integrity
before insert or update on public.tenant_memberships
for each row
execute function private.enforce_membership_profile_integrity();

create or replace function private.enforce_invitation_target_profile_integrity()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE'
     and new.target_profile_id is distinct from old.target_profile_id then
    raise exception using
      errcode = '23514',
      message = 'INVITATION_TARGET_PROFILE_IMMUTABLE';
  end if;

  if new.status = 'pending' and new.target_profile_id is null then
    raise exception using
      errcode = '23514',
      message = 'PENDING_INVITATION_PROFILE_REQUIRED';
  end if;

  if new.status = 'pending'
     and not exists (
       select 1
       from public.tenant_profiles as profile
       where profile.id = new.target_profile_id
         and profile.status = 'active'
     ) then
    raise exception using
      errcode = '23514',
      message = 'INVITATION_PROFILE_NOT_ACTIVE';
  end if;

  return new;
end;
$$;

create trigger tenant_invitations_enforce_target_profile_integrity
before insert or update on public.tenant_invitations
for each row
execute function private.enforce_invitation_target_profile_integrity();

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

  if old.status <> 'inactive'
     and new.status = 'inactive'
     and exists (
       select 1
       from public.tenant_memberships as membership
       where membership.tenant_id = old.tenant_id
         and membership.profile_id = old.id
         and membership.status in ('active', 'blocked')
     ) then
    raise exception using
      errcode = '23514',
      message = 'TENANT_PROFILE_ASSIGNED_TO_OPERATIONAL_MEMBERSHIP';
  end if;

  return new;
end;
$$;

alter table public.tenant_memberships
  add constraint tenant_memberships_operational_profile_ck
    check (status not in ('active', 'blocked') or profile_id is not null)
    not valid;

alter table public.tenant_memberships
  validate constraint tenant_memberships_profile_assignment_ck;

alter table public.tenant_memberships
  validate constraint tenant_memberships_profile_fk;

alter table public.tenant_memberships
  validate constraint tenant_memberships_profile_assigned_by_fk;

alter table public.tenant_memberships
  validate constraint tenant_memberships_operational_profile_ck;

alter table public.tenant_invitations
  validate constraint tenant_invitations_target_profile_fk;

revoke all on function private.enforce_membership_profile_integrity()
  from public, anon, authenticated, service_role;
revoke all on function private.enforce_invitation_target_profile_integrity()
  from public, anon, authenticated, service_role;
revoke all on function private.protect_tenant_profile_mutation()
  from public, anon, authenticated, service_role;

comment on table public.tenant_profiles is
  'Tenant-owned authorization profiles copied once from private platform templates; display name is not authorization authority.';
comment on table public.tenant_profile_permissions is
  'Exact ALLOW baseline for a tenant profile. Row absence means no baseline grant.';
comment on table public.tenant_permission_overrides is
  'Sparse per-membership ALLOW or DENY exception. Row absence means inherit the profile baseline.';
comment on column public.tenant_memberships.profile_id is
  'Required for operational memberships after W2B; same-tenant active profile enforced structurally.';
comment on column public.tenant_invitations.target_profile_id is
  'Explicit same-tenant profile copied to the membership at acceptance; never inferred from display data.';
