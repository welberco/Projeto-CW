begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

create temp view w2e_authorization_functions as
select
  procedure.oid,
  namespace.nspname as schema_name,
  procedure.proname,
  procedure.prosecdef,
  procedure.provolatile,
  procedure.proconfig,
  procedure.proowner,
  procedure.prosrc
from pg_catalog.pg_proc as procedure
join pg_catalog.pg_namespace as namespace
  on namespace.oid = procedure.pronamespace
where (
    namespace.nspname = 'private'
    and procedure.proname not in (
      'append_audit', 'append_history', 'jsonb_has_forbidden_history_keys',
      'prepare_audit_event', 'reject_history_mutation',
      'enqueue_event', 'jsonb_has_forbidden_event_keys', 'protect_outbox_event',
      'semantic_fingerprint', 'protect_command_idempotency',
      'acquire_command_idempotency', 'complete_command_idempotency',
      'reject_event_handler_receipt_mutation', 'record_event_handler_receipt',
      'assert_current_outbox_lease', 'sanitize_worker_error', 'requeue_dead_letter'
    )
  )
   or (
     namespace.nspname = 'public'
     and procedure.proname in (
       'bootstrap_initial_tenant', 'create_tenant_invitation',
       'revoke_tenant_invitation', 'expire_tenant_invitation',
       'accept_tenant_invitation', 'resolve_my_tenant_context',
       'create_tenant_profile', 'update_tenant_profile',
       'change_tenant_profile_status', 'set_tenant_profile_permission',
       'assign_tenant_membership_profile', 'set_tenant_permission_override',
       'delete_tenant_permission_override', 'change_tenant_membership_status',
       'invite_tenant_user', 'revoke_tenant_invitation_authenticated',
       'expire_tenant_invitation_authenticated', 'resolve_my_authorization',
       'create_team', 'update_team', 'inactivate_team', 'reactivate_team',
       'add_team_member', 'end_team_member', 'list_teams', 'get_team',
       'lookup_teams', 'list_my_teams', 'list_team_members',
       'list_teams_for_membership',
       'create_maintenance_category', 'update_maintenance_category',
       'inactivate_maintenance_category', 'reactivate_maintenance_category',
       'create_maintenance_subcategory', 'update_maintenance_subcategory',
       'inactivate_maintenance_subcategory', 'reactivate_maintenance_subcategory',
       'list_maintenance_categories', 'get_maintenance_category',
       'lookup_maintenance_categories', 'list_maintenance_subcategories',
       'get_maintenance_subcategory', 'lookup_maintenance_subcategories',
       'get_cw_catalog_template_preview', 'apply_cw_catalog_template',
       'create_maintenance_reason', 'update_maintenance_reason',
       'inactivate_maintenance_reason', 'reactivate_maintenance_reason',
       'create_document_type', 'update_document_type',
       'inactivate_document_type', 'reactivate_document_type',
       'create_checklist_template', 'update_checklist_template_definition',
       'inactivate_checklist_template', 'reactivate_checklist_template',
       'list_maintenance_reasons', 'get_maintenance_reason',
       'lookup_maintenance_reasons', 'list_document_types',
       'get_document_type', 'lookup_document_types',
       'list_checklist_templates', 'get_checklist_template',
       'lookup_checklist_templates'
     )
     and not (procedure.proname = 'create_tenant_profile' and procedure.pronargs = 4)
   );

create temporary table w2e_expected_authorization_functions (
  source_wave text not null,
  schema_name text not null,
  proname text not null,
  prosecdef boolean not null,
  primary key (schema_name, proname)
);

insert into w2e_expected_authorization_functions (source_wave, schema_name, proname, prosecdef)
values
  ('W1', 'private', 'set_updated_at_and_version', false),
  ('W1', 'private', 'create_app_user_for_auth_identity', true),
  ('W1', 'private', 'reject_audit_mutation', false),
  ('W1', 'private', 'is_active_principal', true),
  ('W1', 'private', 'can_access_tenant', true),
  ('W1', 'private', 'normalize_invitation_email', false),
  ('W1', 'private', 'sha256_hex', false),
  ('W2', 'private', 'protect_authorization_catalog_state', false),
  ('W2', 'private', 'protect_permission_catalog_mutation', false),
  ('W2', 'private', 'bump_authorization_catalog_revision', false),
  ('W2', 'private', 'protect_tenant_profile_mutation', false),
  ('W2', 'private', 'protect_tenant_profile_permission_mutation', false),
  ('W2', 'private', 'bump_tenant_profile_version_for_baseline', false),
  ('W2', 'private', 'protect_tenant_permission_override_mutation', false),
  ('W2', 'private', 'bump_membership_version_for_override', false),
  ('W2', 'private', 'provision_tenant_authorization', false),
  ('W2', 'private', 'enforce_membership_profile_integrity', false),
  ('W2', 'private', 'enforce_invitation_target_profile_integrity', false),
  ('W2', 'private', 'resolve_effective_scopes', true),
  ('W2', 'private', 'has_effective_permission', true),
  ('W2', 'private', 'resolve_profile_permission_ids', true),
  ('W2', 'private', 'resolve_membership_permission_ids', true),
  ('W2', 'private', 'can_delegate_permission', true),
  ('W2', 'private', 'tenant_has_authorization_administrator', true),
  ('W2', 'private', 'require_authorization_reason', false),
  ('W2', 'private', 'lock_authorization_actor', true),
  ('W2', 'private', 'assert_tenant_has_authorization_administrator', true),
  ('W2', 'private', 'write_authorization_audit', true),
  ('W1', 'public', 'bootstrap_initial_tenant', true),
  ('W1', 'public', 'create_tenant_invitation', true),
  ('W1', 'public', 'revoke_tenant_invitation', true),
  ('W1', 'public', 'expire_tenant_invitation', true),
  ('W1', 'public', 'accept_tenant_invitation', true),
  ('W1', 'public', 'resolve_my_tenant_context', true),
  ('W2', 'public', 'create_tenant_profile', true),
  ('W2', 'public', 'update_tenant_profile', true),
  ('W2', 'public', 'change_tenant_profile_status', true),
  ('W2', 'public', 'set_tenant_profile_permission', true),
  ('W2', 'public', 'assign_tenant_membership_profile', true),
  ('W2', 'public', 'set_tenant_permission_override', true),
  ('W2', 'public', 'delete_tenant_permission_override', true),
  ('W2', 'public', 'change_tenant_membership_status', true),
  ('W2', 'public', 'invite_tenant_user', true),
  ('W2', 'public', 'revoke_tenant_invitation_authenticated', true),
  ('W2', 'public', 'expire_tenant_invitation_authenticated', true),
  ('W2', 'public', 'resolve_my_authorization', true),
  ('W4A', 'private', 'apply_w4a_authorization_rollout', true),
  ('W4A', 'private', 'protect_w4a_catalog_mutation', false),
  ('W4A', 'private', 'can_access_w4a_catalog', true),
  ('W4A', 'private', 'assert_w4a_catalog_access', true),
  ('W4A', 'private', 'execute_w4a_catalog_command', true),
  ('W4B.1', 'private', 'apply_w4b_authorization_rollout', true),
  ('W4B.2', 'private', 'protect_team_mutation', false),
  ('W4B.2', 'private', 'enforce_team_integrity', false),
  ('W4B.2', 'private', 'protect_team_membership_mutation', false),
  ('W4B.2', 'private', 'enforce_team_membership_integrity', false),
  ('W4B.2', 'private', 'bump_tenant_membership_revision_for_team', false),
  ('W4B.2', 'private', 'protect_sector_team_dependency', false),
  ('W4B.2', 'private', 'team_reaches', true),
  ('W4B.2', 'private', 'can_access_team', true),
  ('W4B.2', 'private', 'assert_w4b_all_tenant_access', true),
  ('W4B.2', 'private', 'execute_team_command', true),
  ('W4B.2', 'private', 'execute_team_membership_command', true),
  ('W4B.2', 'public', 'create_team', true),
  ('W4B.2', 'public', 'update_team', true),
  ('W4B.2', 'public', 'inactivate_team', true),
  ('W4B.2', 'public', 'reactivate_team', true),
  ('W4B.2', 'public', 'add_team_member', true),
  ('W4B.2', 'public', 'end_team_member', true),
  ('W4B.2', 'public', 'list_teams', true),
  ('W4B.2', 'public', 'get_team', true),
  ('W4B.2', 'public', 'lookup_teams', true),
  ('W4B.2', 'public', 'list_my_teams', true),
  ('W4B.2', 'public', 'list_team_members', true),
  ('W4B.2', 'public', 'list_teams_for_membership', true),
  ('W4C.1', 'private', 'apply_w4c_authorization_rollout', true);

insert into w2e_expected_authorization_functions (source_wave, schema_name, proname, prosecdef)
values
  ('W4C.2', 'private', 'protect_w4c_taxonomy_mutation', false),
  ('W4C.2', 'private', 'can_access_w4c_taxonomy', true),
  ('W4C.2', 'private', 'assert_w4c_taxonomy_access', true),
  ('W4C.2', 'private', 'execute_w4c_taxonomy_command', true),
  ('W4C.2', 'public', 'create_maintenance_category', true),
  ('W4C.2', 'public', 'update_maintenance_category', true),
  ('W4C.2', 'public', 'inactivate_maintenance_category', true),
  ('W4C.2', 'public', 'reactivate_maintenance_category', true),
  ('W4C.2', 'public', 'create_maintenance_subcategory', true),
  ('W4C.2', 'public', 'update_maintenance_subcategory', true),
  ('W4C.2', 'public', 'inactivate_maintenance_subcategory', true),
  ('W4C.2', 'public', 'reactivate_maintenance_subcategory', true),
  ('W4C.2', 'public', 'list_maintenance_categories', true),
  ('W4C.2', 'public', 'get_maintenance_category', true),
  ('W4C.2', 'public', 'lookup_maintenance_categories', true),
  ('W4C.2', 'public', 'list_maintenance_subcategories', true),
  ('W4C.2', 'public', 'get_maintenance_subcategory', true),
  ('W4C.2', 'public', 'lookup_maintenance_subcategories', true),
  ('W4C.2', 'public', 'get_cw_catalog_template_preview', true),
  ('W4C.2', 'public', 'apply_cw_catalog_template', true);

insert into w2e_expected_authorization_functions (source_wave, schema_name, proname, prosecdef)
values
  ('W4C.3', 'private', 'protect_w4c3_catalog_mutation', false),
  ('W4C.3', 'private', 'protect_category_checklist_dependency', false),
  ('W4C.3', 'private', 'can_access_w4c3_catalog', true),
  ('W4C.3', 'private', 'assert_w4c3_catalog_access', true),
  ('W4C.3', 'private', 'execute_w4c3_simple_catalog_command', true),
  ('W4C.3', 'private', 'validate_checklist_template_items', false),
  ('W4C.3', 'private', 'execute_checklist_template_command', true),
  ('W4C.3', 'public', 'create_maintenance_reason', true),
  ('W4C.3', 'public', 'update_maintenance_reason', true),
  ('W4C.3', 'public', 'inactivate_maintenance_reason', true),
  ('W4C.3', 'public', 'reactivate_maintenance_reason', true),
  ('W4C.3', 'public', 'create_document_type', true),
  ('W4C.3', 'public', 'update_document_type', true),
  ('W4C.3', 'public', 'inactivate_document_type', true),
  ('W4C.3', 'public', 'reactivate_document_type', true),
  ('W4C.3', 'public', 'create_checklist_template', true),
  ('W4C.3', 'public', 'update_checklist_template_definition', true),
  ('W4C.3', 'public', 'inactivate_checklist_template', true),
  ('W4C.3', 'public', 'reactivate_checklist_template', true),
  ('W4C.3', 'public', 'list_maintenance_reasons', true),
  ('W4C.3', 'public', 'get_maintenance_reason', true),
  ('W4C.3', 'public', 'lookup_maintenance_reasons', true),
  ('W4C.3', 'public', 'list_document_types', true),
  ('W4C.3', 'public', 'get_document_type', true),
  ('W4C.3', 'public', 'lookup_document_types', true),
  ('W4C.3', 'public', 'list_checklist_templates', true),
  ('W4C.3', 'public', 'get_checklist_template', true),
  ('W4C.3', 'public', 'lookup_checklist_templates', true);

create temporary table w2e_expected_public_security_definers (
  routine regprocedure primary key
);

insert into w2e_expected_public_security_definers (routine)
values
  ('public.bootstrap_initial_tenant(uuid,text,uuid)'::regprocedure),
  ('public.create_tenant_invitation(uuid,uuid,text,timestamptz,uuid,uuid)'::regprocedure),
  ('public.revoke_tenant_invitation(uuid,uuid,uuid)'::regprocedure),
  ('public.expire_tenant_invitation(uuid,uuid,uuid)'::regprocedure),
  ('public.accept_tenant_invitation(text,uuid)'::regprocedure),
  ('public.resolve_my_tenant_context(uuid)'::regprocedure),
  ('public.create_tenant_profile(text,text,uuid)'::regprocedure),
  ('public.create_tenant_profile(text,text,uuid,text)'::regprocedure),
  ('public.update_tenant_profile(uuid,bigint,text,text,uuid)'::regprocedure),
  ('public.change_tenant_profile_status(uuid,bigint,text,text,uuid)'::regprocedure),
  ('public.set_tenant_profile_permission(uuid,uuid,boolean,bigint,text,uuid)'::regprocedure),
  ('public.assign_tenant_membership_profile(uuid,uuid,bigint,text,uuid)'::regprocedure),
  ('public.set_tenant_permission_override(uuid,uuid,text,bigint,text,bigint,uuid)'::regprocedure),
  ('public.delete_tenant_permission_override(uuid,bigint,bigint,text,uuid)'::regprocedure),
  ('public.change_tenant_membership_status(uuid,bigint,text,text,uuid)'::regprocedure),
  ('public.invite_tenant_user(uuid,bigint,text,timestamptz,text,uuid)'::regprocedure),
  ('public.revoke_tenant_invitation_authenticated(uuid,bigint,text,uuid)'::regprocedure),
  ('public.expire_tenant_invitation_authenticated(uuid,bigint,text,uuid)'::regprocedure),
  ('public.resolve_my_authorization()'::regprocedure),
  ('public.claim_outbox_batch(text,integer)'::regprocedure),
  ('public.read_profile_created_origin(uuid,text,uuid,bigint)'::regprocedure),
  ('public.complete_outbox_event(uuid,text,uuid,bigint,integer,jsonb)'::regprocedure),
  ('public.fail_outbox_event(uuid,text,uuid,bigint,text,text,text)'::regprocedure),
  ('public.create_location_type(text,text,text,text,uuid,text)'::regprocedure),
  ('public.update_location_type(uuid,bigint,text,text,text,text,uuid,text)'::regprocedure),
  ('public.inactivate_location_type(uuid,bigint,text,uuid,text)'::regprocedure),
  ('public.reactivate_location_type(uuid,bigint,text,uuid,text)'::regprocedure),
  ('public.create_location(uuid,uuid,text,text,text,text,uuid,text)'::regprocedure),
  ('public.update_location(uuid,bigint,uuid,text,text,text,text,uuid,text)'::regprocedure),
  ('public.move_location(uuid,bigint,uuid,text,uuid,text)'::regprocedure),
  ('public.inactivate_location(uuid,bigint,text,uuid,text)'::regprocedure),
  ('public.reactivate_location(uuid,bigint,text,uuid,text)'::regprocedure),
  ('public.create_cost_center(uuid,text,text,text,text,uuid,text)'::regprocedure),
  ('public.update_cost_center(uuid,bigint,text,text,text,text,uuid,text)'::regprocedure),
  ('public.move_cost_center(uuid,bigint,uuid,text,uuid,text)'::regprocedure),
  ('public.inactivate_cost_center(uuid,bigint,text,uuid,text)'::regprocedure),
  ('public.reactivate_cost_center(uuid,bigint,text,uuid,text)'::regprocedure),
  ('public.create_sector(text,text,text,text,uuid,text)'::regprocedure),
  ('public.update_sector(uuid,bigint,text,text,text,text,uuid,text)'::regprocedure),
  ('public.inactivate_sector(uuid,bigint,text,uuid,text)'::regprocedure),
  ('public.reactivate_sector(uuid,bigint,text,uuid,text)'::regprocedure),
  ('public.list_location_types(text,text,integer,integer)'::regprocedure),
  ('public.get_location_type(uuid)'::regprocedure),
  ('public.lookup_location_types(text,integer)'::regprocedure),
  ('public.list_locations(text,text,integer,integer)'::regprocedure),
  ('public.get_location(uuid)'::regprocedure),
  ('public.lookup_locations(text,integer)'::regprocedure),
  ('public.list_location_children(uuid)'::regprocedure),
  ('public.list_cost_centers(text,text,integer,integer)'::regprocedure),
  ('public.get_cost_center(uuid)'::regprocedure),
  ('public.lookup_cost_centers(text,integer)'::regprocedure),
  ('public.list_cost_center_children(uuid)'::regprocedure),
  ('public.list_sectors(text,text,integer,integer)'::regprocedure),
  ('public.get_sector(uuid)'::regprocedure),
  ('public.lookup_sectors(text,integer)'::regprocedure),
  ('public.create_team(uuid,text,text,text,text,uuid,text)'::regprocedure),
  ('public.update_team(uuid,bigint,uuid,text,text,text,text,uuid,text)'::regprocedure),
  ('public.inactivate_team(uuid,bigint,text,uuid,text)'::regprocedure),
  ('public.reactivate_team(uuid,bigint,text,uuid,text)'::regprocedure),
  ('public.add_team_member(uuid,uuid,text,uuid,text)'::regprocedure),
  ('public.end_team_member(uuid,bigint,text,uuid,text)'::regprocedure),
  ('public.list_teams(text,text,integer,integer)'::regprocedure),
  ('public.get_team(uuid)'::regprocedure),
  ('public.lookup_teams(text,integer)'::regprocedure),
  ('public.list_my_teams()'::regprocedure),
  ('public.list_team_members(uuid,text,integer,integer)'::regprocedure),
  ('public.list_teams_for_membership(uuid,text,integer,integer)'::regprocedure);

insert into w2e_expected_public_security_definers (routine)
values
  ('public.create_maintenance_category(text,text,text,text,uuid,text)'::regprocedure),
  ('public.update_maintenance_category(uuid,bigint,text,text,text,text,uuid,text)'::regprocedure),
  ('public.inactivate_maintenance_category(uuid,bigint,text,uuid,text)'::regprocedure),
  ('public.reactivate_maintenance_category(uuid,bigint,text,uuid,text)'::regprocedure),
  ('public.create_maintenance_subcategory(uuid,text,text,text,text,uuid,text)'::regprocedure),
  ('public.update_maintenance_subcategory(uuid,bigint,uuid,text,text,text,text,uuid,text)'::regprocedure),
  ('public.inactivate_maintenance_subcategory(uuid,bigint,text,uuid,text)'::regprocedure),
  ('public.reactivate_maintenance_subcategory(uuid,bigint,text,uuid,text)'::regprocedure),
  ('public.list_maintenance_categories(text,text,integer,integer)'::regprocedure),
  ('public.get_maintenance_category(uuid)'::regprocedure),
  ('public.lookup_maintenance_categories(text,integer)'::regprocedure),
  ('public.list_maintenance_subcategories(uuid,text,text,integer,integer)'::regprocedure),
  ('public.get_maintenance_subcategory(uuid)'::regprocedure),
  ('public.lookup_maintenance_subcategories(uuid,text,integer)'::regprocedure),
  ('public.get_cw_catalog_template_preview(text,bigint)'::regprocedure),
  ('public.apply_cw_catalog_template(text,bigint,text,uuid,text)'::regprocedure),
  ('public.create_maintenance_reason(text,text,text,text,text,uuid,text)'::regprocedure),
  ('public.update_maintenance_reason(uuid,bigint,text,text,text,text,uuid,text)'::regprocedure),
  ('public.inactivate_maintenance_reason(uuid,bigint,text,uuid,text)'::regprocedure),
  ('public.reactivate_maintenance_reason(uuid,bigint,text,uuid,text)'::regprocedure),
  ('public.create_document_type(text,text,text,text,uuid,text)'::regprocedure),
  ('public.update_document_type(uuid,bigint,text,text,text,text,uuid,text)'::regprocedure),
  ('public.inactivate_document_type(uuid,bigint,text,uuid,text)'::regprocedure),
  ('public.reactivate_document_type(uuid,bigint,text,uuid,text)'::regprocedure),
  ('public.create_checklist_template(uuid,text,text,text,jsonb,text,uuid,text)'::regprocedure),
  ('public.update_checklist_template_definition(uuid,bigint,uuid,text,text,text,jsonb,text,uuid,text)'::regprocedure),
  ('public.inactivate_checklist_template(uuid,bigint,text,uuid,text)'::regprocedure),
  ('public.reactivate_checklist_template(uuid,bigint,text,uuid,text)'::regprocedure),
  ('public.list_maintenance_reasons(text,text,text,integer,integer)'::regprocedure),
  ('public.get_maintenance_reason(uuid)'::regprocedure),
  ('public.lookup_maintenance_reasons(text,text,integer)'::regprocedure),
  ('public.list_document_types(text,text,integer,integer)'::regprocedure),
  ('public.get_document_type(uuid)'::regprocedure),
  ('public.lookup_document_types(text,integer)'::regprocedure),
  ('public.list_checklist_templates(uuid,text,text,integer,integer)'::regprocedure),
  ('public.get_checklist_template(uuid)'::regprocedure),
  ('public.lookup_checklist_templates(uuid,text,integer)'::regprocedure);

-- Integrated RLS, grants, function and default-privilege inventory.
select is(
  (
    select count(*)
    from pg_catalog.pg_class as relation
    join pg_catalog.pg_namespace as namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relkind = 'r'
      and relation.relname in (
        'app_users', 'tenants', 'tenant_memberships', 'tenant_invitations',
        'tenant_entitlements', 'audit_events', 'permission_catalog',
        'tenant_profiles', 'tenant_profile_permissions', 'tenant_permission_overrides'
      )
      and relation.relrowsecurity
  ),
  10::bigint,
  'all W1/W2 public tables have RLS enabled'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename in (
        'app_users', 'tenants', 'tenant_memberships', 'tenant_invitations',
        'tenant_entitlements', 'audit_events', 'permission_catalog',
        'tenant_profiles', 'tenant_profile_permissions', 'tenant_permission_overrides'
      )
      and not (
        cmd = 'SELECT'
        and tablename in ('app_users', 'tenants', 'tenant_memberships', 'tenant_entitlements')
      )
  ),
  0::bigint,
  'the only W1/W2 policies are the four intentional read policies'
);

select is(
  (
    select count(*)
    from information_schema.table_privileges
    where table_schema in ('public', 'private')
      and grantee in ('PUBLIC', 'anon')
      and table_name in (
        'app_users', 'tenants', 'tenant_memberships', 'tenant_invitations',
        'tenant_entitlements', 'audit_events', 'permission_catalog',
        'tenant_profiles', 'tenant_profile_permissions', 'tenant_permission_overrides',
        'platform_bootstrap_state', 'authorization_catalog_state',
        'authorization_profile_templates', 'authorization_profile_template_permissions'
      )
  ),
  0::bigint,
  'PUBLIC and anon have no W1/W2 table privileges'
);

select is(
  (
    select count(*)
    from information_schema.table_privileges
    where table_schema = 'public'
      and grantee = 'authenticated'
      and privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'TRIGGER')
      and table_name in (
        'app_users', 'tenants', 'tenant_memberships', 'tenant_invitations',
        'tenant_entitlements', 'audit_events', 'permission_catalog',
        'tenant_profiles', 'tenant_profile_permissions', 'tenant_permission_overrides'
      )
  ),
  0::bigint,
  'authenticated has no direct W1/W2 mutation privilege'
);

select is(
  (
    select count(*)
    from information_schema.table_privileges
    where table_schema = 'public'
      and grantee = 'service_role'
      and table_name in (
        'app_users', 'tenants', 'tenant_memberships', 'tenant_invitations',
        'tenant_entitlements', 'audit_events', 'permission_catalog',
        'tenant_profiles', 'tenant_profile_permissions', 'tenant_permission_overrides'
      )
  ),
  0::bigint,
  'service_role cannot bypass authorization through direct W1/W2 tables'
);

select is(
  (
    select count(*)
    from pg_catalog.pg_default_acl as default_acl
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = default_acl.defaclnamespace
    cross join lateral pg_catalog.aclexplode(default_acl.defaclacl) as privilege
    left join pg_catalog.pg_roles as grantee on grantee.oid = privilege.grantee
    where default_acl.defaclrole = 'postgres'::regrole
      and namespace.nspname in ('public', 'private')
      and default_acl.defaclobjtype in ('r', 'S', 'f')
      and coalesce(grantee.rolname, 'PUBLIC') in (
        'PUBLIC', 'anon', 'authenticated', 'service_role'
      )
  ),
  0::bigint,
  'future versioned W1/W2 objects are closed by default for the migration owner'
);

select is(
  (
    select count(*)
    from (
      select schema_name, proname, prosecdef from w2e_authorization_functions
      except all
      select schema_name, proname, prosecdef from w2e_expected_authorization_functions
    ) as unexpected
  ),
  0::bigint,
  'the authorization inventory contains no routine or security mode outside the explicit W0-W2 and W4A-W4C.3 allowlist'
);
select is(
  (
    select count(*)
    from (
      select schema_name, proname, prosecdef from w2e_expected_authorization_functions
      except all
      select schema_name, proname, prosecdef from w2e_authorization_functions
    ) as missing
  ),
  0::bigint,
  'every explicitly allowlisted W0-W2 and W4A-W4C.3 routine remains present with its approved security mode'
);
select is(
  (
    select count(*)
    from w2e_authorization_functions as actual
    join w2e_expected_authorization_functions as expected
      using (schema_name, proname, prosecdef)
    where expected.source_wave = 'W4A'
  ),
  5::bigint,
  'each W4A private helper has its individually approved security mode'
);
select is(
  (
    select count(*)
    from w2e_authorization_functions as actual
    join w2e_expected_authorization_functions as expected
      using (schema_name, proname, prosecdef)
    where expected.source_wave = 'W4B.1'
  ),
  1::bigint,
  'the W4B.1 rollout has its individually approved privileged security mode'
);
select is(
  (
    select count(*)
    from w2e_authorization_functions as actual
    join w2e_expected_authorization_functions as expected
      using (schema_name, proname, prosecdef)
    where expected.source_wave = 'W4B.2'
  ),
  23::bigint,
  'all W4B.2 helpers and public boundaries have individually approved security modes'
);
select is(
  (
    select count(*)
    from w2e_authorization_functions as actual
    join w2e_expected_authorization_functions as expected
      using (schema_name, proname, prosecdef)
    where expected.source_wave = 'W4C.1'
  ),
  1::bigint,
  'the W4C.1 rollout has its individually approved privileged security mode'
);
select is(
  (
    select count(*)
    from w2e_authorization_functions as actual
    join w2e_expected_authorization_functions as expected
      using (schema_name, proname, prosecdef)
    where expected.source_wave = 'W4C.2'
  ),
  20::bigint,
  'all W4C.2 helpers and public boundaries have individually approved security modes'
);
select is(
  (
    select count(*)
    from w2e_authorization_functions as actual
    join w2e_expected_authorization_functions as expected
      using (schema_name, proname, prosecdef)
    where expected.source_wave = 'W4C.3'
  ),
  28::bigint,
  'all W4C.3 helpers and public boundaries have individually approved security modes'
);
select is(
  (
    select count(*)
    from (
      select procedure.oid::regprocedure
      from pg_catalog.pg_proc as procedure
      join pg_catalog.pg_namespace as namespace on namespace.oid = procedure.pronamespace
      where namespace.nspname = 'public' and procedure.prosecdef
      except all
      select routine from w2e_expected_public_security_definers
    ) as unexpected
  ),
  0::bigint,
  'no unknown public SECURITY DEFINER authority boundary exists'
);
select is(
  (
    select count(*)
    from information_schema.routine_privileges
    where routine_schema = 'private'
      and routine_name in (
        'apply_w4a_authorization_rollout', 'protect_w4a_catalog_mutation',
        'can_access_w4a_catalog', 'assert_w4a_catalog_access',
        'execute_w4a_catalog_command', 'apply_w4b_authorization_rollout',
        'apply_w4c_authorization_rollout',
        'protect_team_mutation', 'enforce_team_integrity',
        'protect_team_membership_mutation', 'enforce_team_membership_integrity',
        'bump_tenant_membership_revision_for_team',
        'protect_sector_team_dependency', 'team_reaches', 'can_access_team',
        'assert_w4b_all_tenant_access', 'execute_team_command',
        'execute_team_membership_command',
        'protect_w4c_taxonomy_mutation', 'can_access_w4c_taxonomy',
        'assert_w4c_taxonomy_access', 'execute_w4c_taxonomy_command',
        'protect_w4c3_catalog_mutation', 'protect_category_checklist_dependency',
        'can_access_w4c3_catalog', 'assert_w4c3_catalog_access',
        'execute_w4c3_simple_catalog_command', 'validate_checklist_template_items',
        'execute_checklist_template_command'
      )
      and grantee in ('PUBLIC', 'anon', 'authenticated', 'service_role', 'cw_worker')
  ),
  0::bigint,
  'W4A through W4C.3 private helpers expose no execution grant to client or technical API roles'
);
select is(
  (
    select count(*)
    from w2e_authorization_functions as function_inventory
    join pg_catalog.pg_roles as owner_role on owner_role.oid = function_inventory.proowner
    where owner_role.rolname <> 'postgres'
  ),
  0::bigint,
  'all authorization routines have the controlled postgres owner'
);
select is(
  (
    select count(*)
    from w2e_authorization_functions
    where not exists (
      select 1
      from pg_catalog.unnest(coalesce(proconfig, array[]::text[])) as setting(value)
      where setting.value = 'search_path=""'
    )
  ),
  0::bigint,
  'every W1/W2 routine fixes an empty search_path'
);
select is(
  (
    select count(*)
    from w2e_authorization_functions
    where prosrc ~* E'(^|[^a-z_])execute[[:space:]]'
  ),
  0::bigint,
  'no W1/W2 routine uses dynamic SQL'
);
select is(
  (
    select count(*)
    from w2e_authorization_functions
    cross join lateral pg_catalog.aclexplode(
      coalesce(
        (select procedure.proacl from pg_catalog.pg_proc as procedure where procedure.oid = w2e_authorization_functions.oid),
        pg_catalog.acldefault('f', proowner)
      )
    ) as privilege
    where privilege.grantee = 0
  ),
  0::bigint,
  'no W1/W2 routine has PUBLIC EXECUTE'
);
select is(
  (
    select count(*)
    from w2e_authorization_functions
    where pg_catalog.has_function_privilege('anon', oid, 'EXECUTE')
  ),
  0::bigint,
  'anon cannot execute a W1/W2 routine'
);
select is(
  pg_catalog.has_function_privilege(
    'service_role', 'public.resolve_my_tenant_context(uuid)', 'EXECUTE'
  ),
  false,
  'service_role cannot call the authenticated self context projection'
);
select is(
  (
    select count(*)
    from information_schema.routine_privileges
    where routine_schema = 'public'
      and grantee = 'service_role'
      and privilege_type = 'EXECUTE'
      and routine_name in (
        'bootstrap_initial_tenant', 'create_tenant_invitation',
        'revoke_tenant_invitation', 'expire_tenant_invitation'
      )
  ),
  4::bigint,
  'service_role retains only the four documented technical W1 operations'
);
select is(
  (
    select count(*)
    from w2e_authorization_functions
    where schema_name = 'public'
      and pg_catalog.has_function_privilege('authenticated', oid, 'EXECUTE')
      and pg_catalog.pg_get_function_identity_arguments(oid) ~ '(actor_user_id|operator_user_id)'
  ),
  0::bigint,
  'no authenticated RPC accepts actor identity from payload'
);
select is(
  pg_catalog.pg_get_function_identity_arguments('public.resolve_my_authorization()'::regprocedure),
  ''::text,
  'authorization projection accepts no target, tenant or actor input'
);
select is(
  pg_catalog.has_function_privilege('service_role', 'public.resolve_my_authorization()', 'EXECUTE'),
  false,
  'service_role is not a functional authorization principal'
);

-- Two-tenant fixture with valid IDs known to the opposite principal.
insert into auth.users (id, aud, role, email, email_confirmed_at, created_at, updated_at)
values
  ('1e000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'w2e-a@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp()),
  ('1e000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'w2e-b@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp()),
  ('1e000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'w2e-limited@example.invalid', statement_timestamp(), statement_timestamp(), statement_timestamp());

insert into public.tenants (id, tenant_ref, display_name, status, created_by)
values
  ('2e000000-0000-4000-8000-000000000001', '3e000000-0000-4000-8000-000000000001', 'W2E Tenant A', 'active', '1e000000-0000-4000-8000-000000000001'),
  ('2e000000-0000-4000-8000-000000000002', '3e000000-0000-4000-8000-000000000002', 'W2E Tenant B', 'active', '1e000000-0000-4000-8000-000000000002');

select * from private.provision_tenant_authorization('2e000000-0000-4000-8000-000000000001', null, '1e000000-0000-4000-8000-000000000001', '4e000000-0000-4000-8000-000000000001');
select * from private.provision_tenant_authorization('2e000000-0000-4000-8000-000000000002', null, '1e000000-0000-4000-8000-000000000002', '4e000000-0000-4000-8000-000000000002');

insert into public.tenant_entitlements (tenant_id, module_key, enabled, created_by)
values
  ('2e000000-0000-4000-8000-000000000001', 'maintenance', true, '1e000000-0000-4000-8000-000000000001'),
  ('2e000000-0000-4000-8000-000000000002', 'maintenance', true, '1e000000-0000-4000-8000-000000000002');

insert into public.tenant_memberships (
  id, tenant_id, user_id, status, joined_at, created_by,
  profile_id, profile_assigned_at, profile_assigned_by
)
select
  target.membership_id, target.tenant_id, target.user_id, 'active',
  statement_timestamp(), target.user_id, profile.id, statement_timestamp(), target.user_id
from (
  values
    ('5e000000-0000-4000-8000-000000000001'::uuid, '2e000000-0000-4000-8000-000000000001'::uuid, '1e000000-0000-4000-8000-000000000001'::uuid),
    ('5e000000-0000-4000-8000-000000000002'::uuid, '2e000000-0000-4000-8000-000000000002'::uuid, '1e000000-0000-4000-8000-000000000002'::uuid)
) as target(membership_id, tenant_id, user_id)
join public.tenant_profiles as profile
  on profile.tenant_id = target.tenant_id and profile.template_key = 'manager';

create temporary table w2e_refs (
  key text primary key,
  id uuid not null,
  version bigint not null
);
grant select on table w2e_refs to authenticated;
insert into w2e_refs (key, id, version)
select
  case
    when profile.tenant_id = '2e000000-0000-4000-8000-000000000002' then 'tenant_b_technician'
    else 'tenant_a_technician'
  end,
  profile.id,
  profile.version
from public.tenant_profiles as profile
where profile.template_key = 'technician'
  and profile.tenant_id in (
    '2e000000-0000-4000-8000-000000000001',
    '2e000000-0000-4000-8000-000000000002'
  );

set local "request.jwt.claim.sub" = '1e000000-0000-4000-8000-000000000001';
set local role authenticated;

select is((select count(*) from public.app_users), 1::bigint, 'Tenant A principal sees only its own application identity');
select is((select count(*) from public.tenants), 1::bigint, 'Tenant A cannot enumerate Tenant B');
select is((select count(*) from public.tenant_memberships), 1::bigint, 'Tenant A cannot enumerate Tenant B membership');
select is((select count(*) from public.tenant_entitlements), 1::bigint, 'Tenant A cannot enumerate Tenant B entitlement');
select is(
  (select context_status from public.resolve_my_tenant_context('3e000000-0000-4000-8000-000000000002')),
  'tenant_context_unavailable',
  'a valid Tenant B route reference cannot redefine the authoritative tenant'
);
select is(
  (select tenant_id from public.resolve_my_authorization()),
  '2e000000-0000-4000-8000-000000000001'::uuid,
  'the self projection remains bound to Tenant A'
);
select throws_ok(
  $$ select * from public.update_tenant_profile('6e000000-0000-4000-8000-000000000099', 1, 'Unknown', 'probe', pg_catalog.gen_random_uuid()) $$,
  'P0001', 'AUTHORIZATION_OPERATION_UNAVAILABLE',
  'a nonexistent profile returns the generic public error'
);
select throws_ok(
  format(
    'select * from public.update_tenant_profile(%L, %s, %L, %L, %L)',
    (select id from w2e_refs where key = 'tenant_b_technician'),
    (select version from w2e_refs where key = 'tenant_b_technician'),
    'Cross tenant', 'probe', pg_catalog.gen_random_uuid()
  ),
  'P0001', 'AUTHORIZATION_OPERATION_UNAVAILABLE',
  'a known Tenant B profile is non-enumerable and cannot be changed'
);
select throws_ok(
  $$ update public.tenant_memberships set profile_id = profile_id where id = '5e000000-0000-4000-8000-000000000002' $$,
  '42501', null,
  'authenticated cannot bypass commands with direct membership mutation'
);
select throws_ok(
  $$ insert into public.tenant_profile_permissions (tenant_id, profile_id, permission_id) values ('2e000000-0000-4000-8000-000000000001', pg_catalog.gen_random_uuid(), '91000000-0000-4000-8000-000000000001') $$,
  '42501', null,
  'authenticated cannot add a baseline directly'
);
select throws_ok(
  $$ insert into public.tenant_permission_overrides (tenant_id, membership_id, permission_id, effect) values ('2e000000-0000-4000-8000-000000000001', '5e000000-0000-4000-8000-000000000001', '91000000-0000-4000-8000-000000000001', 'allow') $$,
  '42501', null,
  'authenticated cannot add an override directly'
);
select throws_ok(
  $$ update public.audit_events set metadata = '{}'::jsonb $$,
  '42501', null,
  'authenticated cannot alter audit rows'
);
select throws_ok(
  $$ update public.permission_catalog set status = 'deprecated', deprecated_at = statement_timestamp() $$,
  '42501', null,
  'authenticated cannot mutate the platform permission catalog'
);
select throws_ok(
  $$ update private.authorization_profile_templates set default_name = 'Forged' $$,
  '42501', null,
  'authenticated cannot mutate private platform templates'
);

reset role;

select is(
  (select count(*) from private.resolve_effective_scopes('users', 'read')),
  1::bigint,
  'ALL_TENANT resolves only inside the current authoritative tenant'
);
select is(
  private.has_effective_permission('users', 'read', 'OWN'),
  false,
  'ALL_TENANT does not imply OWN or any scope hierarchy'
);
select is(
  private.has_effective_permission('users', '*', 'ALL_TENANT'),
  false,
  'wildcard actions fail closed'
);
select is(
  private.has_effective_permission('user', 'read', 'ALL_TENANT'),
  false,
  'prefix and substring resource matches fail closed'
);

-- Stale JWT must lose authority against current database lifecycle and entitlement facts.
update public.tenant_memberships
set status = 'blocked', blocked_at = statement_timestamp()
where id = '5e000000-0000-4000-8000-000000000001';
set local role authenticated;
select is((select projection_status from public.resolve_my_authorization()), 'membership_unavailable', 'blocked membership invalidates a still-valid JWT');
select throws_ok(
  $$ select * from public.create_tenant_profile('Blocked actor', 'probe', pg_catalog.gen_random_uuid()) $$,
  'P0001', 'AUTHORIZATION_OPERATION_UNAVAILABLE',
  'blocked membership cannot retain command authority'
);
reset role;
update public.tenant_memberships
set status = 'active', blocked_at = null
where id = '5e000000-0000-4000-8000-000000000001';

update public.app_users
set status = 'blocked', blocked_at = statement_timestamp()
where id = '1e000000-0000-4000-8000-000000000001';
set local role authenticated;
select is((select projection_status from public.resolve_my_authorization()), 'principal_unavailable', 'blocked app user invalidates a still-valid JWT');
reset role;
update public.app_users
set status = 'active', blocked_at = null
where id = '1e000000-0000-4000-8000-000000000001';

update public.tenants
set status = 'suspended', suspended_at = statement_timestamp()
where id = '2e000000-0000-4000-8000-000000000001';
set local role authenticated;
select is((select projection_status from public.resolve_my_authorization()), 'tenant_unavailable', 'suspended tenant invalidates a still-valid JWT');
reset role;
update public.tenants
set status = 'active', suspended_at = null
where id = '2e000000-0000-4000-8000-000000000001';

insert into public.permission_catalog (
  id, code, module_code, resource_code, action_code, scope,
  required_entitlement_key, tenant_delegable, label_key
)
values
  ('9e000000-0000-4000-8000-000000000001', 'probe.hardening.read.own', 'probe', 'hardening', 'read', 'OWN', 'maintenance', true, 'probe.hardening.read.own.label'),
  ('9e000000-0000-4000-8000-000000000002', 'probe.hardening.read.assigned', 'probe', 'hardening', 'read', 'ASSIGNED', 'maintenance', true, 'probe.hardening.read.assigned.label'),
  ('9e000000-0000-4000-8000-000000000003', 'probe.hardening.read.team', 'probe', 'hardening', 'read', 'TEAM', 'maintenance', true, 'probe.hardening.read.team.label'),
  ('9e000000-0000-4000-8000-000000000004', 'probe.hardening.read.all_tenant', 'probe', 'hardening', 'read', 'ALL_TENANT', 'maintenance', true, 'probe.hardening.read.all_tenant.label');

insert into public.tenant_profile_permissions (tenant_id, profile_id, permission_id, created_by)
select '2e000000-0000-4000-8000-000000000001', profile.id, permission.id,
  '1e000000-0000-4000-8000-000000000001'
from public.tenant_profiles as profile
cross join public.permission_catalog as permission
where profile.tenant_id = '2e000000-0000-4000-8000-000000000001'
  and profile.template_key = 'manager'
  and permission.id in (
    '9e000000-0000-4000-8000-000000000001',
    '9e000000-0000-4000-8000-000000000002',
    '9e000000-0000-4000-8000-000000000003',
    '9e000000-0000-4000-8000-000000000004'
  );

insert into public.tenant_permission_overrides (
  tenant_id, membership_id, permission_id, effect, created_by, updated_by
)
values (
  '2e000000-0000-4000-8000-000000000001',
  '5e000000-0000-4000-8000-000000000001',
  '9e000000-0000-4000-8000-000000000001',
  'deny',
  '1e000000-0000-4000-8000-000000000001',
  '1e000000-0000-4000-8000-000000000001'
);

select is(
  (select array_agg(scope order by scope) from private.resolve_effective_scopes('hardening', 'read') as scope),
  array['ASSIGNED', 'TEAM', 'ALL_TENANT']::public.authorization_scope[],
  'DENY OWN replaces only OWN while the remaining scopes form a union'
);

delete from public.tenant_permission_overrides
where membership_id = '5e000000-0000-4000-8000-000000000001'
  and permission_id = '9e000000-0000-4000-8000-000000000001';
insert into public.tenant_permission_overrides (
  tenant_id, membership_id, permission_id, effect, created_by, updated_by
)
values (
  '2e000000-0000-4000-8000-000000000001',
  '5e000000-0000-4000-8000-000000000001',
  '9e000000-0000-4000-8000-000000000002',
  'deny',
  '1e000000-0000-4000-8000-000000000001',
  '1e000000-0000-4000-8000-000000000001'
);

select is(
  (select array_agg(scope order by scope) from private.resolve_effective_scopes('hardening', 'read') as scope),
  array['OWN', 'TEAM', 'ALL_TENANT']::public.authorization_scope[],
  'DENY ASSIGNED does not remove TEAM or ALL_TENANT'
);

delete from public.tenant_permission_overrides
where membership_id = '5e000000-0000-4000-8000-000000000001'
  and permission_id = '9e000000-0000-4000-8000-000000000002';
insert into public.tenant_permission_overrides (
  tenant_id, membership_id, permission_id, effect, created_by, updated_by
)
values (
  '2e000000-0000-4000-8000-000000000001',
  '5e000000-0000-4000-8000-000000000001',
  '9e000000-0000-4000-8000-000000000003',
  'deny',
  '1e000000-0000-4000-8000-000000000001',
  '1e000000-0000-4000-8000-000000000001'
);

select is(
  (select array_agg(scope order by scope) from private.resolve_effective_scopes('hardening', 'read') as scope),
  array['OWN', 'ASSIGNED', 'ALL_TENANT']::public.authorization_scope[],
  'DENY TEAM does not remove ALL_TENANT'
);

update public.tenant_entitlements
set enabled = false
where tenant_id = '2e000000-0000-4000-8000-000000000001'
  and module_key = 'maintenance';
select is((select count(*) from private.resolve_effective_scopes('hardening', 'read')), 0::bigint, 'disabled entitlement suppresses baseline and override authority');
select is(private.has_effective_permission('users', 'read', 'ALL_TENANT'), true, 'core permission without entitlement remains governed by its formal rule');
set local role authenticated;
select is(
  (select count(*) from unnest((select permission_codes from public.resolve_my_authorization())) as code where code like 'probe.hardening.%'),
  0::bigint,
  'projection cannot bypass a disabled entitlement'
);
select is(
  (select count(*) from unnest((select permission_codes from public.resolve_my_authorization())) as code where code = 'core.users.read.all_tenant'),
  1::bigint,
  'projection retains unrelated core authority exactly'
);
reset role;
update public.tenant_entitlements
set enabled = true
where tenant_id = '2e000000-0000-4000-8000-000000000001'
  and module_key = 'maintenance';

update public.permission_catalog
set status = 'deprecated', deprecated_at = statement_timestamp()
where id = '9e000000-0000-4000-8000-000000000003';
select is(
  (select count(*) from public.tenant_profile_permissions where permission_id = '9e000000-0000-4000-8000-000000000003'),
  1::bigint,
  'deprecation preserves historical baseline rows'
);
select is(private.has_effective_permission('hardening', 'read', 'TEAM'), false, 'deprecated permission no longer resolves');
set local role authenticated;
select throws_ok(
  format(
    'select * from public.set_tenant_profile_permission(%L, %L, true, %s, %L, %L)',
    (select id from w2e_refs where key = 'tenant_a_technician'),
    '9e000000-0000-4000-8000-000000000003',
    (select version from w2e_refs where key = 'tenant_a_technician'),
    'probe', pg_catalog.gen_random_uuid()
  ),
  'P0001', 'AUTHORIZATION_OPERATION_UNAVAILABLE',
  'deprecated permission cannot receive a new baseline'
);
reset role;

-- service_role keeps technical RPCs but no direct authorization data plane.
set local role service_role;
select throws_ok(
  $$ select count(*) from public.tenant_memberships $$,
  '42501', null,
  'service_role cannot read membership authority directly'
);
select throws_ok(
  $$ update public.audit_events set metadata = '{}'::jsonb $$,
  '42501', null,
  'service_role cannot mutate audit directly'
);
reset role;

select is(
  (
    select count(*)
    from public.audit_events
    where metadata::text ~* '(invitation_token|password|jwt|service_role|secret)'
  ),
  0::bigint,
  'authorization audit contains no token, JWT, password or secret material'
);
select throws_ok(
  $$ update public.audit_events set metadata = metadata $$,
  '55000', 'audit_events is append-only',
  'audit remains append-only even for the controlled owner'
);
select is(
  (
    select count(*)
    from public.permission_catalog
    where code like '%*%'
       or code like '%global_admin%'
       or code like '%platform%'
  ),
  0::bigint,
  'catalog contains no wildcard, Global Admin or platform tenant permission'
);

select * from finish();
rollback;
