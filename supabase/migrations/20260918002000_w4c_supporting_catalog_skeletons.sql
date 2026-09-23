-- CW ERP V2 / W4C.3: supporting maintenance catalog skeletons.

create table public.maintenance_reasons (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  usage_context text not null,
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
  constraint maintenance_reasons_tenant_id_id_uq unique (tenant_id,id),
  constraint maintenance_reasons_context_ck check (usage_context in (
    'CANCEL_REQUEST','REJECT_REQUEST','PAUSE_WORK_ORDER','CANCEL_WORK_ORDER','RETURN_WORK_ORDER'
  )),
  constraint maintenance_reasons_code_ck check (
    code=pg_catalog.btrim(code) and code ~ '^[A-Za-z0-9][A-Za-z0-9._/-]{0,63}$'
  ),
  constraint maintenance_reasons_name_ck check (
    name=pg_catalog.btrim(name) and pg_catalog.char_length(name) between 1 and 160
  ),
  constraint maintenance_reasons_description_ck check (
    description is null or (description=pg_catalog.btrim(description) and pg_catalog.char_length(description)<=2000)
  ),
  constraint maintenance_reasons_status_ck check (status in ('active','inactive')),
  constraint maintenance_reasons_version_ck check (version>0),
  constraint maintenance_reasons_lifecycle_ck check (
    (status='active' and inactivated_at is null) or (status='inactive' and inactivated_at is not null)
  )
);
create unique index maintenance_reasons_tenant_context_code_uq
  on public.maintenance_reasons (tenant_id,usage_context,pg_catalog.lower(code));
create index maintenance_reasons_tenant_context_status_name_idx
  on public.maintenance_reasons (tenant_id,usage_context,status,pg_catalog.lower(name),id);

create table public.document_types (
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
  constraint document_types_tenant_id_id_uq unique (tenant_id,id),
  constraint document_types_code_ck check (
    code is null or (code=pg_catalog.btrim(code) and code ~ '^[A-Za-z0-9][A-Za-z0-9._/-]{0,63}$')
  ),
  constraint document_types_name_ck check (
    name=pg_catalog.btrim(name) and pg_catalog.char_length(name) between 1 and 160
  ),
  constraint document_types_description_ck check (
    description is null or (description=pg_catalog.btrim(description) and pg_catalog.char_length(description)<=2000)
  ),
  constraint document_types_status_ck check (status in ('active','inactive')),
  constraint document_types_version_ck check (version>0),
  constraint document_types_lifecycle_ck check (
    (status='active' and inactivated_at is null) or (status='inactive' and inactivated_at is not null)
  )
);
create unique index document_types_tenant_code_uq
  on public.document_types (tenant_id,pg_catalog.lower(code)) where code is not null;
create index document_types_tenant_status_name_idx
  on public.document_types (tenant_id,status,pg_catalog.lower(name),id);

create table public.checklist_templates (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  category_id uuid not null,
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
  constraint checklist_templates_tenant_id_id_uq unique (tenant_id,id),
  constraint checklist_templates_category_fk foreign key (tenant_id,category_id)
    references public.maintenance_categories (tenant_id,id) on delete restrict,
  constraint checklist_templates_code_ck check (
    code is null or (code=pg_catalog.btrim(code) and code ~ '^[A-Za-z0-9][A-Za-z0-9._/-]{0,63}$')
  ),
  constraint checklist_templates_name_ck check (
    name=pg_catalog.btrim(name) and pg_catalog.char_length(name) between 1 and 160
  ),
  constraint checklist_templates_description_ck check (
    description is null or (description=pg_catalog.btrim(description) and pg_catalog.char_length(description)<=2000)
  ),
  constraint checklist_templates_status_ck check (status in ('active','inactive')),
  constraint checklist_templates_version_ck check (version>0),
  constraint checklist_templates_lifecycle_ck check (
    (status='active' and inactivated_at is null) or (status='inactive' and inactivated_at is not null)
  )
);
create unique index checklist_templates_tenant_code_uq
  on public.checklist_templates (tenant_id,pg_catalog.lower(code)) where code is not null;
create index checklist_templates_tenant_category_status_name_idx
  on public.checklist_templates (tenant_id,category_id,status,pg_catalog.lower(name),id);

create table public.checklist_template_items (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  template_id uuid not null,
  position integer not null,
  prompt text not null,
  response_type text not null,
  required boolean not null,
  instructions text,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  created_by uuid not null references public.app_users (id) on delete restrict,
  constraint checklist_template_items_tenant_id_id_uq unique (tenant_id,id),
  constraint checklist_template_items_template_fk foreign key (tenant_id,template_id)
    references public.checklist_templates (tenant_id,id) on delete restrict,
  constraint checklist_template_items_position_uq unique (tenant_id,template_id,position),
  constraint checklist_template_items_position_ck check (position between 1 and 10000),
  constraint checklist_template_items_prompt_ck check (
    prompt=pg_catalog.btrim(prompt) and pg_catalog.char_length(prompt) between 1 and 500
  ),
  constraint checklist_template_items_response_type_ck check (response_type in (
    'DONE_NOT_DONE','CONFORMING_NONCONFORMING','YES_NO','TEXT','NUMBER','OBSERVATION'
  )),
  constraint checklist_template_items_instructions_ck check (
    instructions is null or (instructions=pg_catalog.btrim(instructions) and pg_catalog.char_length(instructions)<=2000)
  )
);
create index checklist_template_items_tenant_template_position_idx
  on public.checklist_template_items (tenant_id,template_id,position,id);

create function private.protect_w4c3_catalog_mutation()
returns trigger language plpgsql set search_path='' as $$
begin
  if tg_op='DELETE' then
    raise exception using errcode='42501',message='SUPPORTING_CATALOG_DELETE_FORBIDDEN';
  end if;
  if new.id<>old.id or new.tenant_id<>old.tenant_id or new.created_at<>old.created_at
     or new.created_by<>old.created_by or new.version<>old.version then
    raise exception using errcode='42501',message='SUPPORTING_CATALOG_PROTECTED_FIELD';
  end if;
  if tg_table_schema='public' and tg_table_name='maintenance_reasons' then
    if new.usage_context<>old.usage_context then
      raise exception using errcode='42501',message='MAINTENANCE_REASON_CONTEXT_IMMUTABLE';
    end if;
  end if;
  return new;
end $$;
revoke all on function private.protect_w4c3_catalog_mutation()
  from public,anon,authenticated,service_role,cw_worker;

create trigger maintenance_reasons_protect_mutation before update or delete on public.maintenance_reasons
for each row execute function private.protect_w4c3_catalog_mutation();
create trigger maintenance_reasons_set_updated_at_and_version before update on public.maintenance_reasons
for each row execute function private.set_updated_at_and_version();
create trigger document_types_protect_mutation before update or delete on public.document_types
for each row execute function private.protect_w4c3_catalog_mutation();
create trigger document_types_set_updated_at_and_version before update on public.document_types
for each row execute function private.set_updated_at_and_version();
create trigger checklist_templates_protect_mutation before update or delete on public.checklist_templates
for each row execute function private.protect_w4c3_catalog_mutation();
create trigger checklist_templates_set_updated_at_and_version before update on public.checklist_templates
for each row execute function private.set_updated_at_and_version();

create function private.protect_category_checklist_dependency()
returns trigger language plpgsql set search_path='' as $$
begin
  if old.status='active' and new.status='inactive' and exists (
    select 1 from public.checklist_templates template
    where template.tenant_id=old.tenant_id and template.category_id=old.id and template.status='active'
  ) then
    raise exception using errcode='23514',message='ACTIVE_CHECKLIST_TEMPLATE_DEPENDENCY';
  end if;
  return new;
end $$;
revoke all on function private.protect_category_checklist_dependency()
  from public,anon,authenticated,service_role,cw_worker;
create trigger maintenance_categories_checklist_dependency before update on public.maintenance_categories
for each row execute function private.protect_category_checklist_dependency();

alter table public.maintenance_reasons enable row level security;
alter table public.maintenance_reasons force row level security;
alter table public.document_types enable row level security;
alter table public.document_types force row level security;
alter table public.checklist_templates enable row level security;
alter table public.checklist_templates force row level security;
alter table public.checklist_template_items enable row level security;
alter table public.checklist_template_items force row level security;

revoke all on table public.maintenance_reasons,public.document_types,
  public.checklist_templates,public.checklist_template_items
  from public,anon,authenticated,service_role,cw_worker;
grant select on table public.maintenance_reasons,public.document_types,public.checklist_templates
  to authenticated;

create function private.can_access_w4c3_catalog(
  target_tenant_id uuid,target_resource_code text,target_action_code text
)
returns boolean language sql stable security definer set search_path='' as $$
  select exists (
    select 1 from public.tenant_memberships membership
    join public.app_users app_user on app_user.id=membership.user_id and app_user.status='active'
    join public.tenants tenant on tenant.id=membership.tenant_id and tenant.status='active'
    join public.tenant_profiles profile on profile.id=membership.profile_id
      and profile.tenant_id=membership.tenant_id and profile.status='active'
    where membership.user_id=auth.uid() and membership.tenant_id=target_tenant_id
      and membership.status='active'
      and private.has_effective_permission(
        target_resource_code,target_action_code,'ALL_TENANT'::public.authorization_scope
      )
  )
$$;
revoke all on function private.can_access_w4c3_catalog(uuid,text,text)
  from public,anon,authenticated,service_role,cw_worker;
alter function private.can_access_w4c3_catalog(uuid,text,text) owner to postgres;

create function private.assert_w4c3_catalog_access(target_resource_code text,target_action_code text)
returns uuid language plpgsql security definer set search_path='' as $$
declare target_tenant_id uuid;
begin
  select membership.tenant_id into target_tenant_id
  from public.tenant_memberships membership
  where membership.user_id=auth.uid() and membership.status='active';
  if target_tenant_id is null
     or not private.can_access_w4c3_catalog(target_tenant_id,target_resource_code,target_action_code) then
    raise exception using errcode='42501',message='AUTHORIZATION_DENIED';
  end if;
  return target_tenant_id;
end $$;
revoke all on function private.assert_w4c3_catalog_access(text,text)
  from public,anon,authenticated,service_role,cw_worker;
alter function private.assert_w4c3_catalog_access(text,text) owner to postgres;

create policy maintenance_reasons_read on public.maintenance_reasons for select to authenticated
using (private.can_access_w4c3_catalog(tenant_id,'maintenance_reasons','read'));
create policy document_types_read on public.document_types for select to authenticated
using (private.can_access_w4c3_catalog(tenant_id,'document_types','read'));
create policy checklist_templates_read on public.checklist_templates for select to authenticated
using (private.can_access_w4c3_catalog(tenant_id,'checklist_templates','read'));

create function private.execute_w4c3_simple_catalog_command(
  target_resource text,target_action text,target_id uuid,expected_version bigint,
  target_usage_context text,target_code text,target_name text,target_description text,
  command_reason text,command_correlation_id uuid,command_idempotency_key text
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  actor record; idem record; fingerprint bytea;
  entity_id uuid:=coalesce(target_id,pg_catalog.gen_random_uuid());
  correlation_id uuid:=coalesce(command_correlation_id,pg_catalog.gen_random_uuid());
  command_name text; aggregate_type text; event_type text; event_action text;
  entity_version bigint; entity_status text; entity_code text; entity_name text; entity_context text;
  result jsonb;
begin
  if target_resource not in ('maintenance_reasons','document_types')
     or target_action not in ('create','update','inactivate','reactivate') then
    raise exception using errcode='22023',message='INVALID_SUPPORTING_CATALOG_COMMAND';
  end if;
  if command_reason is null or command_reason<>pg_catalog.btrim(command_reason)
     or pg_catalog.char_length(command_reason) not between 1 and 500 then
    raise exception using errcode='22023',message='INVALID_COMMAND_REASON';
  end if;
  if target_action='create' and target_resource='maintenance_reasons'
     and target_usage_context not in (
       'CANCEL_REQUEST','REJECT_REQUEST','PAUSE_WORK_ORDER','CANCEL_WORK_ORDER','RETURN_WORK_ORDER'
     ) then
    raise exception using errcode='22023',message='INVALID_MAINTENANCE_REASON_CONTEXT';
  end if;
  select * into actor from private.lock_authorization_actor(target_resource,target_action);
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(actor.actor_tenant_id::text||':'||target_resource,0)
  );
  aggregate_type:=case target_resource
    when 'maintenance_reasons' then 'maintenance_reason' else 'document_type' end;
  command_name:='maintenance.'||target_action||'_'||aggregate_type;
  fingerprint:=private.semantic_fingerprint(pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
    'resource',target_resource,'action',target_action,'id',target_id,'expected_version',expected_version,
    'usage_context',target_usage_context,'code',target_code,'name',target_name,'description',target_description
  )));
  select * into idem from private.acquire_command_idempotency(
    actor.actor_tenant_id,'application_user','user_command',command_name,
    command_idempotency_key,fingerprint,actor.actor_user_id,null,null
  );
  if idem.replayed then return idem.stored_result; end if;
  event_action:=case target_action when 'create' then 'created' when 'update' then 'updated'
    when 'inactivate' then 'inactivated' else 'reactivated' end;
  event_type:=case target_resource when 'maintenance_reasons' then 'maintenance.reason.'
    else 'cadastros.document_type.' end||event_action;

  if target_action='create' then
    if target_name is null or target_name<>pg_catalog.btrim(target_name) then
      raise exception using errcode='22023',message='INVALID_SUPPORTING_CATALOG_NAME';
    end if;
    if target_resource='maintenance_reasons' then
      insert into public.maintenance_reasons(
        id,tenant_id,usage_context,code,name,description,created_by,updated_by
      ) values (
        entity_id,actor.actor_tenant_id,target_usage_context,target_code,target_name,
        target_description,actor.actor_user_id,actor.actor_user_id
      ) returning version,status,code,name,usage_context
        into entity_version,entity_status,entity_code,entity_name,entity_context;
    else
      insert into public.document_types(
        id,tenant_id,code,name,description,created_by,updated_by
      ) values (
        entity_id,actor.actor_tenant_id,target_code,target_name,target_description,
        actor.actor_user_id,actor.actor_user_id
      ) returning version,status,code,name
        into entity_version,entity_status,entity_code,entity_name;
    end if;
  elsif target_action='update' then
    if target_id is null or expected_version is null
       or target_name is null or target_name<>pg_catalog.btrim(target_name) then
      raise exception using errcode='22023',message='INVALID_UPDATE_INPUT';
    end if;
    if target_resource='maintenance_reasons' then
      update public.maintenance_reasons set
        code=target_code,name=target_name,description=target_description,updated_by=actor.actor_user_id
      where tenant_id=actor.actor_tenant_id and id=target_id
        and version=expected_version and status='active'
      returning version,status,code,name,usage_context
        into entity_version,entity_status,entity_code,entity_name,entity_context;
    else
      update public.document_types set
        code=target_code,name=target_name,description=target_description,updated_by=actor.actor_user_id
      where tenant_id=actor.actor_tenant_id and id=target_id
        and version=expected_version and status='active'
      returning version,status,code,name
        into entity_version,entity_status,entity_code,entity_name;
    end if;
    if not found then
      raise exception using errcode='P0001',message='SUPPORTING_CATALOG_VERSION_CONFLICT';
    end if;
  else
    if target_id is null or expected_version is null then
      raise exception using errcode='22023',message='INVALID_STATUS_INPUT';
    end if;
    if target_resource='maintenance_reasons' then
      update public.maintenance_reasons set
        status=case target_action when 'inactivate' then 'inactive' else 'active' end,
        inactivated_at=case target_action when 'inactivate' then pg_catalog.statement_timestamp() else null end,
        updated_by=actor.actor_user_id
      where tenant_id=actor.actor_tenant_id and id=target_id and version=expected_version
        and status=case target_action when 'inactivate' then 'active' else 'inactive' end
      returning version,status,code,name,usage_context
        into entity_version,entity_status,entity_code,entity_name,entity_context;
    else
      update public.document_types set
        status=case target_action when 'inactivate' then 'inactive' else 'active' end,
        inactivated_at=case target_action when 'inactivate' then pg_catalog.statement_timestamp() else null end,
        updated_by=actor.actor_user_id
      where tenant_id=actor.actor_tenant_id and id=target_id and version=expected_version
        and status=case target_action when 'inactivate' then 'active' else 'inactive' end
      returning version,status,code,name
        into entity_version,entity_status,entity_code,entity_name;
    end if;
    if not found then
      raise exception using errcode='P0001',message='SUPPORTING_CATALOG_STATE_OR_VERSION_CONFLICT';
    end if;
  end if;

  perform private.append_audit(
    actor.actor_tenant_id,'application_user',event_type,aggregate_type,correlation_id,'user_command',
    actor.actor_user_id,null,entity_id,idem.acquired_command_id,null,1,command_reason,
    pg_catalog.jsonb_build_object('version',entity_version,'status',entity_status)
  );
  perform private.append_history(
    actor.actor_tenant_id,aggregate_type,entity_id,event_type,'application_user',command_name,
    idem.acquired_command_id,correlation_id,'user_command',entity_version,entity_code,1,
    actor.actor_user_id,null,null,pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
      'name',entity_name,'status',entity_status,'usage_context',entity_context
    ))
  );
  perform private.enqueue_event(
    actor.actor_tenant_id,event_type,'application_user','user_command',idem.acquired_command_id,
    correlation_id,aggregate_type,entity_id,1,entity_version,actor.actor_user_id,null,null,
    pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
      'id',entity_id,'version',entity_version,'status',entity_status,'code',entity_code,
      'usage_context',entity_context
    )),pg_catalog.jsonb_build_object('command',command_name)
  );
  result:=pg_catalog.jsonb_build_object(
    'id',entity_id,'version',entity_version,'status',entity_status,
    'command_correlation_id',correlation_id
  );
  perform private.complete_command_idempotency(idem.acquired_command_id,1,result);
  return result;
end $$;
revoke all on function private.execute_w4c3_simple_catalog_command(
  text,text,uuid,bigint,text,text,text,text,text,uuid,text
) from public,anon,authenticated,service_role,cw_worker;
alter function private.execute_w4c3_simple_catalog_command(
  text,text,uuid,bigint,text,text,text,text,text,uuid,text
) owner to postgres;

create function private.validate_checklist_template_items(target_items jsonb)
returns jsonb language plpgsql immutable set search_path='' as $$
declare item jsonb; normalized jsonb;
begin
  if target_items is null or pg_catalog.jsonb_typeof(target_items)<>'array'
     or pg_catalog.jsonb_array_length(target_items) not between 1 and 200 then
    raise exception using errcode='22023',message='INVALID_CHECKLIST_TEMPLATE_ITEMS';
  end if;
  for item in select value from pg_catalog.jsonb_array_elements(target_items) loop
    if pg_catalog.jsonb_typeof(item)<>'object'
       or not (item ?& array['position','prompt','response_type','required'])
       or exists (
         select 1
         from pg_catalog.jsonb_object_keys(item) as item_key(key_name)
         where item_key.key_name not in (
           'position','prompt','response_type','required','instructions'
         )
       )
       or pg_catalog.jsonb_typeof(item->'position')<>'number'
       or (item->>'position') !~ '^[1-9][0-9]*$'
       or (item->>'position')::integer not between 1 and 10000
       or pg_catalog.jsonb_typeof(item->'prompt')<>'string'
       or item->>'prompt'<>pg_catalog.btrim(item->>'prompt')
       or pg_catalog.char_length(item->>'prompt') not between 1 and 500
       or pg_catalog.jsonb_typeof(item->'response_type')<>'string'
       or item->>'response_type' not in (
         'DONE_NOT_DONE','CONFORMING_NONCONFORMING','YES_NO','TEXT','NUMBER','OBSERVATION'
       )
       or pg_catalog.jsonb_typeof(item->'required')<>'boolean'
       or (item ? 'instructions' and pg_catalog.jsonb_typeof(item->'instructions') not in ('string','null'))
       or (pg_catalog.jsonb_typeof(item->'instructions')='string' and (
         item->>'instructions'<>pg_catalog.btrim(item->>'instructions')
         or pg_catalog.char_length(item->>'instructions')>2000
       )) then
      raise exception using errcode='22023',message='INVALID_CHECKLIST_TEMPLATE_ITEM';
    end if;
  end loop;
  if (select count(*) from pg_catalog.jsonb_array_elements(target_items)) <>
     (select count(distinct (value->>'position')::integer)
      from pg_catalog.jsonb_array_elements(target_items)) then
    raise exception using errcode='22023',message='DUPLICATE_CHECKLIST_TEMPLATE_ITEM_POSITION';
  end if;
  select pg_catalog.jsonb_agg(value order by (value->>'position')::integer)
    into normalized from pg_catalog.jsonb_array_elements(target_items);
  return normalized;
end $$;
revoke all on function private.validate_checklist_template_items(jsonb)
  from public,anon,authenticated,service_role,cw_worker;
alter function private.validate_checklist_template_items(jsonb) owner to postgres;

create function private.execute_checklist_template_command(
  target_action text,target_id uuid,expected_version bigint,target_category_id uuid,
  target_code text,target_name text,target_description text,target_items jsonb,
  command_reason text,command_correlation_id uuid,command_idempotency_key text
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  actor record; idem record; fingerprint bytea; current_record record;
  entity_id uuid:=coalesce(target_id,pg_catalog.gen_random_uuid());
  correlation_id uuid:=coalesce(command_correlation_id,pg_catalog.gen_random_uuid());
  normalized_items jsonb; command_name text; event_type text; event_action text;
  entity_version bigint; entity_status text; entity_code text; entity_name text;
  entity_category_id uuid; category_status text; item_count integer; result jsonb;
begin
  if target_action not in ('create','update','inactivate','reactivate') then
    raise exception using errcode='22023',message='INVALID_CHECKLIST_TEMPLATE_COMMAND';
  end if;
  if command_reason is null or command_reason<>pg_catalog.btrim(command_reason)
     or pg_catalog.char_length(command_reason) not between 1 and 500 then
    raise exception using errcode='22023',message='INVALID_COMMAND_REASON';
  end if;
  if target_action in ('create','update') then
    if target_name is null or target_name<>pg_catalog.btrim(target_name) or target_category_id is null then
      raise exception using errcode='22023',message='INVALID_CHECKLIST_TEMPLATE_INPUT';
    end if;
    normalized_items:=private.validate_checklist_template_items(target_items);
  end if;
  select * into actor from private.lock_authorization_actor('checklist_templates',
    case target_action when 'update' then 'update' else target_action end);
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(actor.actor_tenant_id::text||':maintenance_taxonomy',0)
  );
  command_name:='maintenance.'||case target_action
    when 'update' then 'update_checklist_template_definition'
    else target_action||'_checklist_template' end;
  fingerprint:=private.semantic_fingerprint(pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
    'action',target_action,'id',target_id,'expected_version',expected_version,
    'category_id',target_category_id,'code',target_code,'name',target_name,
    'description',target_description,'items',normalized_items
  )));
  select * into idem from private.acquire_command_idempotency(
    actor.actor_tenant_id,'application_user','user_command',command_name,
    command_idempotency_key,fingerprint,actor.actor_user_id,null,null
  );
  if idem.replayed then return idem.stored_result; end if;
  event_action:=case target_action when 'create' then 'created' when 'update' then 'updated'
    when 'inactivate' then 'inactivated' else 'reactivated' end;
  event_type:='maintenance.checklist_template.'||event_action;

  if target_action in ('create','update') then
    select category.id,category.status into current_record
    from public.maintenance_categories category
    where category.tenant_id=actor.actor_tenant_id and category.id=target_category_id
    for update;
    if not found or current_record.status<>'active' then
      raise exception using errcode='P0001',message='MAINTENANCE_CATEGORY_UNAVAILABLE';
    end if;
  end if;

  if target_action='create' then
    insert into public.checklist_templates(
      id,tenant_id,category_id,code,name,description,created_by,updated_by
    ) values (
      entity_id,actor.actor_tenant_id,target_category_id,target_code,target_name,
      target_description,actor.actor_user_id,actor.actor_user_id
    ) returning version,status,code,name,category_id
      into entity_version,entity_status,entity_code,entity_name,entity_category_id;
  elsif target_action='update' then
    if target_id is null or expected_version is null then
      raise exception using errcode='22023',message='INVALID_UPDATE_INPUT';
    end if;
    update public.checklist_templates set
      category_id=target_category_id,code=target_code,name=target_name,
      description=target_description,updated_by=actor.actor_user_id
    where tenant_id=actor.actor_tenant_id and id=target_id
      and version=expected_version and status='active'
    returning version,status,code,name,category_id
      into entity_version,entity_status,entity_code,entity_name,entity_category_id;
    if not found then
      raise exception using errcode='P0001',message='CHECKLIST_TEMPLATE_VERSION_CONFLICT';
    end if;
    delete from public.checklist_template_items
    where tenant_id=actor.actor_tenant_id and template_id=target_id;
  else
    if target_id is null or expected_version is null then
      raise exception using errcode='22023',message='INVALID_STATUS_INPUT';
    end if;
    if target_action='reactivate' then
      select template.category_id,category.status into entity_category_id,category_status
      from public.checklist_templates template
      join public.maintenance_categories category
        on category.tenant_id=template.tenant_id and category.id=template.category_id
      where template.tenant_id=actor.actor_tenant_id and template.id=target_id
      for update of category;
      if not found or category_status<>'active' then
        raise exception using errcode='23514',message='MAINTENANCE_CATEGORY_INACTIVE';
      end if;
    end if;
    update public.checklist_templates set
      status=case target_action when 'inactivate' then 'inactive' else 'active' end,
      inactivated_at=case target_action when 'inactivate' then pg_catalog.statement_timestamp() else null end,
      updated_by=actor.actor_user_id
    where tenant_id=actor.actor_tenant_id and id=target_id and version=expected_version
      and status=case target_action when 'inactivate' then 'active' else 'inactive' end
    returning version,status,code,name,category_id
      into entity_version,entity_status,entity_code,entity_name,entity_category_id;
    if not found then
      raise exception using errcode='P0001',message='CHECKLIST_TEMPLATE_STATE_OR_VERSION_CONFLICT';
    end if;
  end if;

  if target_action in ('create','update') then
    insert into public.checklist_template_items(
      tenant_id,template_id,position,prompt,response_type,required,instructions,created_by
    )
    select actor.actor_tenant_id,entity_id,(item->>'position')::integer,item->>'prompt',
      item->>'response_type',(item->>'required')::boolean,
      case when pg_catalog.jsonb_typeof(item->'instructions')='string' then item->>'instructions' else null end,
      actor.actor_user_id
    from pg_catalog.jsonb_array_elements(normalized_items) item;
  end if;
  select count(*)::integer into item_count from public.checklist_template_items item
  where item.tenant_id=actor.actor_tenant_id and item.template_id=entity_id;

  perform private.append_audit(
    actor.actor_tenant_id,'application_user',event_type,'checklist_template',correlation_id,'user_command',
    actor.actor_user_id,null,entity_id,idem.acquired_command_id,null,1,command_reason,
    pg_catalog.jsonb_build_object('version',entity_version,'status',entity_status,'item_count',item_count)
  );
  perform private.append_history(
    actor.actor_tenant_id,'checklist_template',entity_id,event_type,'application_user',command_name,
    idem.acquired_command_id,correlation_id,'user_command',entity_version,entity_code,1,
    actor.actor_user_id,null,null,pg_catalog.jsonb_build_object(
      'name',entity_name,'status',entity_status,'category_id',entity_category_id,'item_count',item_count
    )
  );
  perform private.enqueue_event(
    actor.actor_tenant_id,event_type,'application_user','user_command',idem.acquired_command_id,
    correlation_id,'checklist_template',entity_id,1,entity_version,actor.actor_user_id,null,null,
    pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
      'id',entity_id,'version',entity_version,'status',entity_status,'code',entity_code,
      'category_id',entity_category_id,'item_count',item_count
    )),pg_catalog.jsonb_build_object('command',command_name)
  );
  result:=pg_catalog.jsonb_build_object(
    'id',entity_id,'version',entity_version,'status',entity_status,
    'command_correlation_id',correlation_id
  );
  perform private.complete_command_idempotency(idem.acquired_command_id,1,result);
  return result;
end $$;
revoke all on function private.execute_checklist_template_command(
  text,uuid,bigint,uuid,text,text,text,jsonb,text,uuid,text
) from public,anon,authenticated,service_role,cw_worker;
alter function private.execute_checklist_template_command(
  text,uuid,bigint,uuid,text,text,text,jsonb,text,uuid,text
) owner to postgres;

create function public.create_maintenance_reason(
  usage_context text,code text,name text,description text,reason text,correlation_id uuid,idempotency_key text
) returns jsonb language sql security definer set search_path='' as $$
  select private.execute_w4c3_simple_catalog_command(
    'maintenance_reasons','create',null,null,usage_context,code,name,description,reason,correlation_id,idempotency_key
  )
$$;
create function public.update_maintenance_reason(
  id uuid,expected_version bigint,code text,name text,description text,reason text,correlation_id uuid,idempotency_key text
) returns jsonb language sql security definer set search_path='' as $$
  select private.execute_w4c3_simple_catalog_command(
    'maintenance_reasons','update',id,expected_version,null,code,name,description,reason,correlation_id,idempotency_key
  )
$$;
create function public.inactivate_maintenance_reason(
  id uuid,expected_version bigint,reason text,correlation_id uuid,idempotency_key text
) returns jsonb language sql security definer set search_path='' as $$
  select private.execute_w4c3_simple_catalog_command(
    'maintenance_reasons','inactivate',id,expected_version,null,null,null,null,reason,correlation_id,idempotency_key
  )
$$;
create function public.reactivate_maintenance_reason(
  id uuid,expected_version bigint,reason text,correlation_id uuid,idempotency_key text
) returns jsonb language sql security definer set search_path='' as $$
  select private.execute_w4c3_simple_catalog_command(
    'maintenance_reasons','reactivate',id,expected_version,null,null,null,null,reason,correlation_id,idempotency_key
  )
$$;

create function public.create_document_type(
  code text,name text,description text,reason text,correlation_id uuid,idempotency_key text
) returns jsonb language sql security definer set search_path='' as $$
  select private.execute_w4c3_simple_catalog_command(
    'document_types','create',null,null,null,code,name,description,reason,correlation_id,idempotency_key
  )
$$;
create function public.update_document_type(
  id uuid,expected_version bigint,code text,name text,description text,reason text,correlation_id uuid,idempotency_key text
) returns jsonb language sql security definer set search_path='' as $$
  select private.execute_w4c3_simple_catalog_command(
    'document_types','update',id,expected_version,null,code,name,description,reason,correlation_id,idempotency_key
  )
$$;
create function public.inactivate_document_type(
  id uuid,expected_version bigint,reason text,correlation_id uuid,idempotency_key text
) returns jsonb language sql security definer set search_path='' as $$
  select private.execute_w4c3_simple_catalog_command(
    'document_types','inactivate',id,expected_version,null,null,null,null,reason,correlation_id,idempotency_key
  )
$$;
create function public.reactivate_document_type(
  id uuid,expected_version bigint,reason text,correlation_id uuid,idempotency_key text
) returns jsonb language sql security definer set search_path='' as $$
  select private.execute_w4c3_simple_catalog_command(
    'document_types','reactivate',id,expected_version,null,null,null,null,reason,correlation_id,idempotency_key
  )
$$;

create function public.create_checklist_template(
  category_id uuid,code text,name text,description text,items jsonb,
  reason text,correlation_id uuid,idempotency_key text
) returns jsonb language sql security definer set search_path='' as $$
  select private.execute_checklist_template_command(
    'create',null,null,category_id,code,name,description,items,reason,correlation_id,idempotency_key
  )
$$;
create function public.update_checklist_template_definition(
  id uuid,expected_version bigint,category_id uuid,code text,name text,description text,items jsonb,
  reason text,correlation_id uuid,idempotency_key text
) returns jsonb language sql security definer set search_path='' as $$
  select private.execute_checklist_template_command(
    'update',id,expected_version,category_id,code,name,description,items,reason,correlation_id,idempotency_key
  )
$$;
create function public.inactivate_checklist_template(
  id uuid,expected_version bigint,reason text,correlation_id uuid,idempotency_key text
) returns jsonb language sql security definer set search_path='' as $$
  select private.execute_checklist_template_command(
    'inactivate',id,expected_version,null,null,null,null,null,reason,correlation_id,idempotency_key
  )
$$;
create function public.reactivate_checklist_template(
  id uuid,expected_version bigint,reason text,correlation_id uuid,idempotency_key text
) returns jsonb language sql security definer set search_path='' as $$
  select private.execute_checklist_template_command(
    'reactivate',id,expected_version,null,null,null,null,null,reason,correlation_id,idempotency_key
  )
$$;

create function public.list_maintenance_reasons(
  usage_context_filter text default null,search_text text default null,status_filter text default null,
  result_limit integer default 50,result_offset integer default 0
) returns table(
  id uuid,usage_context text,code text,name text,description text,status text,version bigint,updated_at timestamptz
) language plpgsql security definer set search_path='' as $$
declare target_tenant_id uuid;
begin
  target_tenant_id:=private.assert_w4c3_catalog_access('maintenance_reasons','read');
  if result_limit not between 1 and 100 or result_offset<0
     or (status_filter is not null and status_filter not in ('active','inactive'))
     or (usage_context_filter is not null and usage_context_filter not in (
       'CANCEL_REQUEST','REJECT_REQUEST','PAUSE_WORK_ORDER','CANCEL_WORK_ORDER','RETURN_WORK_ORDER'
     )) then raise exception using errcode='22023',message='INVALID_QUERY_INPUT'; end if;
  return query select reason.id,reason.usage_context,reason.code,reason.name,reason.description,
    reason.status,reason.version,reason.updated_at
  from public.maintenance_reasons reason where reason.tenant_id=target_tenant_id
    and (usage_context_filter is null or reason.usage_context=usage_context_filter)
    and (status_filter is null or reason.status=status_filter)
    and (search_text is null or reason.name ilike '%'||search_text||'%' or reason.code ilike '%'||search_text||'%')
  order by pg_catalog.lower(reason.name),reason.id limit result_limit offset result_offset;
end $$;
create function public.get_maintenance_reason(target_id uuid)
returns table(
  id uuid,usage_context text,code text,name text,description text,status text,version bigint,
  created_at timestamptz,updated_at timestamptz
) language plpgsql security definer set search_path='' as $$
declare target_tenant_id uuid;
begin
  target_tenant_id:=private.assert_w4c3_catalog_access('maintenance_reasons','read');
  return query select reason.id,reason.usage_context,reason.code,reason.name,reason.description,
    reason.status,reason.version,reason.created_at,reason.updated_at
  from public.maintenance_reasons reason
  where reason.tenant_id=target_tenant_id and reason.id=target_id;
end $$;
create function public.lookup_maintenance_reasons(
  usage_context text,search_text text default null,result_limit integer default 20
) returns table(id uuid,code text,name text)
language plpgsql security definer set search_path='' as $$
declare target_tenant_id uuid;
begin
  target_tenant_id:=private.assert_w4c3_catalog_access('maintenance_reasons','lookup');
  if usage_context not in (
    'CANCEL_REQUEST','REJECT_REQUEST','PAUSE_WORK_ORDER','CANCEL_WORK_ORDER','RETURN_WORK_ORDER'
  ) or result_limit not between 1 and 100 then
    raise exception using errcode='22023',message='INVALID_QUERY_INPUT';
  end if;
  return query select reason.id,reason.code,reason.name from public.maintenance_reasons reason
  where reason.tenant_id=target_tenant_id and reason.usage_context=$1 and reason.status='active'
    and (search_text is null or reason.name ilike '%'||search_text||'%' or reason.code ilike '%'||search_text||'%')
  order by pg_catalog.lower(reason.name),reason.id limit result_limit;
end $$;

create function public.list_document_types(
  search_text text default null,status_filter text default null,result_limit integer default 50,result_offset integer default 0
) returns table(id uuid,code text,name text,description text,status text,version bigint,updated_at timestamptz)
language plpgsql security definer set search_path='' as $$
declare target_tenant_id uuid;
begin
  target_tenant_id:=private.assert_w4c3_catalog_access('document_types','read');
  if result_limit not between 1 and 100 or result_offset<0
     or (status_filter is not null and status_filter not in ('active','inactive')) then
    raise exception using errcode='22023',message='INVALID_QUERY_INPUT'; end if;
  return query select document.id,document.code,document.name,document.description,
    document.status,document.version,document.updated_at
  from public.document_types document where document.tenant_id=target_tenant_id
    and (status_filter is null or document.status=status_filter)
    and (search_text is null or document.name ilike '%'||search_text||'%' or document.code ilike '%'||search_text||'%')
  order by pg_catalog.lower(document.name),document.id limit result_limit offset result_offset;
end $$;
create function public.get_document_type(target_id uuid)
returns table(id uuid,code text,name text,description text,status text,version bigint,created_at timestamptz,updated_at timestamptz)
language plpgsql security definer set search_path='' as $$
declare target_tenant_id uuid;
begin
  target_tenant_id:=private.assert_w4c3_catalog_access('document_types','read');
  return query select document.id,document.code,document.name,document.description,
    document.status,document.version,document.created_at,document.updated_at
  from public.document_types document
  where document.tenant_id=target_tenant_id and document.id=target_id;
end $$;
create function public.lookup_document_types(search_text text default null,result_limit integer default 20)
returns table(id uuid,code text,name text)
language plpgsql security definer set search_path='' as $$
declare target_tenant_id uuid;
begin
  target_tenant_id:=private.assert_w4c3_catalog_access('document_types','lookup');
  if result_limit not between 1 and 100 then
    raise exception using errcode='22023',message='INVALID_QUERY_INPUT'; end if;
  return query select document.id,document.code,document.name from public.document_types document
  where document.tenant_id=target_tenant_id and document.status='active'
    and (search_text is null or document.name ilike '%'||search_text||'%' or document.code ilike '%'||search_text||'%')
  order by pg_catalog.lower(document.name),document.id limit result_limit;
end $$;

create function public.list_checklist_templates(
  category_filter uuid default null,search_text text default null,status_filter text default null,
  result_limit integer default 50,result_offset integer default 0
) returns table(
  id uuid,category_id uuid,code text,name text,description text,status text,version bigint,
  item_count integer,updated_at timestamptz
) language plpgsql security definer set search_path='' as $$
declare target_tenant_id uuid;
begin
  target_tenant_id:=private.assert_w4c3_catalog_access('checklist_templates','read');
  if result_limit not between 1 and 100 or result_offset<0
     or (status_filter is not null and status_filter not in ('active','inactive')) then
    raise exception using errcode='22023',message='INVALID_QUERY_INPUT'; end if;
  return query select template.id,template.category_id,template.code,template.name,template.description,
    template.status,template.version,(select count(*)::integer from public.checklist_template_items item
      where item.tenant_id=template.tenant_id and item.template_id=template.id),template.updated_at
  from public.checklist_templates template where template.tenant_id=target_tenant_id
    and (category_filter is null or template.category_id=category_filter)
    and (status_filter is null or template.status=status_filter)
    and (search_text is null or template.name ilike '%'||search_text||'%' or template.code ilike '%'||search_text||'%')
  order by pg_catalog.lower(template.name),template.id limit result_limit offset result_offset;
end $$;
create function public.get_checklist_template(target_id uuid)
returns table(
  id uuid,category_id uuid,code text,name text,description text,status text,version bigint,
  items jsonb,created_at timestamptz,updated_at timestamptz
) language plpgsql security definer set search_path='' as $$
declare target_tenant_id uuid;
begin
  target_tenant_id:=private.assert_w4c3_catalog_access('checklist_templates','read');
  return query select template.id,template.category_id,template.code,template.name,template.description,
    template.status,template.version,coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'id',item.id,'position',item.position,'prompt',item.prompt,'response_type',item.response_type,
      'required',item.required,'instructions',item.instructions
    ) order by item.position,item.id) from public.checklist_template_items item
      where item.tenant_id=template.tenant_id and item.template_id=template.id),'[]'::jsonb),
    template.created_at,template.updated_at
  from public.checklist_templates template
  where template.tenant_id=target_tenant_id and template.id=target_id;
end $$;
create function public.lookup_checklist_templates(
  category_filter uuid default null,search_text text default null,result_limit integer default 20
) returns table(id uuid,category_id uuid,code text,name text)
language plpgsql security definer set search_path='' as $$
declare target_tenant_id uuid;
begin
  target_tenant_id:=private.assert_w4c3_catalog_access('checklist_templates','lookup');
  if result_limit not between 1 and 100 then
    raise exception using errcode='22023',message='INVALID_QUERY_INPUT'; end if;
  return query select template.id,template.category_id,template.code,template.name
  from public.checklist_templates template
  where template.tenant_id=target_tenant_id and template.status='active'
    and (category_filter is null or template.category_id=category_filter)
    and (search_text is null or template.name ilike '%'||search_text||'%' or template.code ilike '%'||search_text||'%')
  order by pg_catalog.lower(template.name),template.id limit result_limit;
end $$;

do $$ declare boundary record; begin
  for boundary in select procedure.oid from pg_catalog.pg_proc procedure
    join pg_catalog.pg_namespace namespace on namespace.oid=procedure.pronamespace
    where namespace.nspname='public' and procedure.proname=any(array[
      'create_maintenance_reason','update_maintenance_reason','inactivate_maintenance_reason','reactivate_maintenance_reason',
      'create_document_type','update_document_type','inactivate_document_type','reactivate_document_type',
      'create_checklist_template','update_checklist_template_definition','inactivate_checklist_template','reactivate_checklist_template',
      'list_maintenance_reasons','get_maintenance_reason','lookup_maintenance_reasons',
      'list_document_types','get_document_type','lookup_document_types',
      'list_checklist_templates','get_checklist_template','lookup_checklist_templates'
    ])
  loop
    execute pg_catalog.format(
      'revoke all on function %s from public,anon,service_role,cw_worker',
      boundary.oid::pg_catalog.regprocedure
    );
  end loop;
end $$;

grant execute on function public.create_maintenance_reason(text,text,text,text,text,uuid,text) to authenticated;
grant execute on function public.update_maintenance_reason(uuid,bigint,text,text,text,text,uuid,text) to authenticated;
grant execute on function public.inactivate_maintenance_reason(uuid,bigint,text,uuid,text) to authenticated;
grant execute on function public.reactivate_maintenance_reason(uuid,bigint,text,uuid,text) to authenticated;
grant execute on function public.create_document_type(text,text,text,text,uuid,text) to authenticated;
grant execute on function public.update_document_type(uuid,bigint,text,text,text,text,uuid,text) to authenticated;
grant execute on function public.inactivate_document_type(uuid,bigint,text,uuid,text) to authenticated;
grant execute on function public.reactivate_document_type(uuid,bigint,text,uuid,text) to authenticated;
grant execute on function public.create_checklist_template(uuid,text,text,text,jsonb,text,uuid,text) to authenticated;
grant execute on function public.update_checklist_template_definition(uuid,bigint,uuid,text,text,text,jsonb,text,uuid,text) to authenticated;
grant execute on function public.inactivate_checklist_template(uuid,bigint,text,uuid,text) to authenticated;
grant execute on function public.reactivate_checklist_template(uuid,bigint,text,uuid,text) to authenticated;
grant execute on function public.list_maintenance_reasons(text,text,text,integer,integer) to authenticated;
grant execute on function public.get_maintenance_reason(uuid) to authenticated;
grant execute on function public.lookup_maintenance_reasons(text,text,integer) to authenticated;
grant execute on function public.list_document_types(text,text,integer,integer) to authenticated;
grant execute on function public.get_document_type(uuid) to authenticated;
grant execute on function public.lookup_document_types(text,integer) to authenticated;
grant execute on function public.list_checklist_templates(uuid,text,text,integer,integer) to authenticated;
grant execute on function public.get_checklist_template(uuid) to authenticated;
grant execute on function public.lookup_checklist_templates(uuid,text,integer) to authenticated;

comment on table public.maintenance_reasons is
  'W4C.3 tenant-owned maintenance reasons with immutable usage context; no automatic seeds.';
comment on table public.document_types is
  'W4C.3 tenant-owned document classification metadata; no files or Storage.';
comment on table public.checklist_templates is
  'W4C.3 reusable checklist definition skeleton; no execution state.';
comment on table public.checklist_template_items is
  'W4C.3 ordered items owned and authorized exclusively through checklist templates.';
