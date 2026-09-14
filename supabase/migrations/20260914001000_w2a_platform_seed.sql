-- CW ERP V2 / W2A: deterministic platform seed for the minimum admin catalog.

insert into public.permission_catalog (
  id,
  code,
  module_code,
  resource_code,
  action_code,
  scope,
  required_entitlement_key,
  tenant_delegable,
  label_key,
  description_key
)
values
  ('91000000-0000-4000-8000-000000000001', 'core.users.read.all_tenant', 'core', 'users', 'read', 'ALL_TENANT', null, true, 'authorization.permissions.core.users.read.all_tenant.label', 'authorization.permissions.core.users.read.all_tenant.description'),
  ('91000000-0000-4000-8000-000000000002', 'core.users.invite.all_tenant', 'core', 'users', 'invite', 'ALL_TENANT', null, true, 'authorization.permissions.core.users.invite.all_tenant.label', 'authorization.permissions.core.users.invite.all_tenant.description'),
  ('91000000-0000-4000-8000-000000000003', 'core.users.assign_profile.all_tenant', 'core', 'users', 'assign_profile', 'ALL_TENANT', null, true, 'authorization.permissions.core.users.assign_profile.all_tenant.label', 'authorization.permissions.core.users.assign_profile.all_tenant.description'),
  ('91000000-0000-4000-8000-000000000004', 'core.users.manage_overrides.all_tenant', 'core', 'users', 'manage_overrides', 'ALL_TENANT', null, true, 'authorization.permissions.core.users.manage_overrides.all_tenant.label', 'authorization.permissions.core.users.manage_overrides.all_tenant.description'),
  ('91000000-0000-4000-8000-000000000005', 'core.users.change_status.all_tenant', 'core', 'users', 'change_status', 'ALL_TENANT', null, true, 'authorization.permissions.core.users.change_status.all_tenant.label', 'authorization.permissions.core.users.change_status.all_tenant.description'),
  ('91000000-0000-4000-8000-000000000006', 'core.profiles.read.all_tenant', 'core', 'profiles', 'read', 'ALL_TENANT', null, true, 'authorization.permissions.core.profiles.read.all_tenant.label', 'authorization.permissions.core.profiles.read.all_tenant.description'),
  ('91000000-0000-4000-8000-000000000007', 'core.profiles.create.all_tenant', 'core', 'profiles', 'create', 'ALL_TENANT', null, true, 'authorization.permissions.core.profiles.create.all_tenant.label', 'authorization.permissions.core.profiles.create.all_tenant.description'),
  ('91000000-0000-4000-8000-000000000008', 'core.profiles.update.all_tenant', 'core', 'profiles', 'update', 'ALL_TENANT', null, true, 'authorization.permissions.core.profiles.update.all_tenant.label', 'authorization.permissions.core.profiles.update.all_tenant.description'),
  ('91000000-0000-4000-8000-000000000009', 'core.profiles.activate.all_tenant', 'core', 'profiles', 'activate', 'ALL_TENANT', null, true, 'authorization.permissions.core.profiles.activate.all_tenant.label', 'authorization.permissions.core.profiles.activate.all_tenant.description'),
  ('91000000-0000-4000-8000-000000000010', 'core.profiles.inactivate.all_tenant', 'core', 'profiles', 'inactivate', 'ALL_TENANT', null, true, 'authorization.permissions.core.profiles.inactivate.all_tenant.label', 'authorization.permissions.core.profiles.inactivate.all_tenant.description'),
  ('91000000-0000-4000-8000-000000000011', 'core.profiles.change_permissions.all_tenant', 'core', 'profiles', 'change_permissions', 'ALL_TENANT', null, true, 'authorization.permissions.core.profiles.change_permissions.all_tenant.label', 'authorization.permissions.core.profiles.change_permissions.all_tenant.description')
on conflict (id) do nothing;

insert into private.authorization_profile_templates (
  id,
  template_key,
  template_version,
  default_name
)
values
  ('92000000-0000-4000-8000-000000000001', 'manager', 1, 'Gestor'),
  ('92000000-0000-4000-8000-000000000002', 'technician', 1, 'Técnico'),
  ('92000000-0000-4000-8000-000000000003', 'assistant', 1, 'Auxiliar'),
  ('92000000-0000-4000-8000-000000000004', 'requester', 1, 'Solicitante')
on conflict (id) do nothing;

insert into private.authorization_profile_template_permissions (
  template_id,
  permission_id
)
values
  ('92000000-0000-4000-8000-000000000001', '91000000-0000-4000-8000-000000000001'),
  ('92000000-0000-4000-8000-000000000001', '91000000-0000-4000-8000-000000000002'),
  ('92000000-0000-4000-8000-000000000001', '91000000-0000-4000-8000-000000000003'),
  ('92000000-0000-4000-8000-000000000001', '91000000-0000-4000-8000-000000000004'),
  ('92000000-0000-4000-8000-000000000001', '91000000-0000-4000-8000-000000000005'),
  ('92000000-0000-4000-8000-000000000001', '91000000-0000-4000-8000-000000000006'),
  ('92000000-0000-4000-8000-000000000001', '91000000-0000-4000-8000-000000000007'),
  ('92000000-0000-4000-8000-000000000001', '91000000-0000-4000-8000-000000000008'),
  ('92000000-0000-4000-8000-000000000001', '91000000-0000-4000-8000-000000000009'),
  ('92000000-0000-4000-8000-000000000001', '91000000-0000-4000-8000-000000000010'),
  ('92000000-0000-4000-8000-000000000001', '91000000-0000-4000-8000-000000000011')
on conflict (template_id, permission_id) do nothing;
