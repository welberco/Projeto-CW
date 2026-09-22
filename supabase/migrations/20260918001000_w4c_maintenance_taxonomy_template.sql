-- CW ERP V2 / W4C.2: tenant-owned maintenance taxonomy and explicit CW template.

create table public.maintenance_categories (
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
  constraint maintenance_categories_tenant_id_id_uq unique (tenant_id,id),
  constraint maintenance_categories_code_ck check (code is null or (code = pg_catalog.btrim(code) and code ~ '^[A-Za-z0-9][A-Za-z0-9._/-]{0,63}$')),
  constraint maintenance_categories_name_ck check (name = pg_catalog.btrim(name) and pg_catalog.char_length(name) between 1 and 160),
  constraint maintenance_categories_description_ck check (description is null or (description = pg_catalog.btrim(description) and pg_catalog.char_length(description) <= 2000)),
  constraint maintenance_categories_status_ck check (status in ('active','inactive')),
  constraint maintenance_categories_version_ck check (version > 0),
  constraint maintenance_categories_lifecycle_ck check ((status='active' and inactivated_at is null) or (status='inactive' and inactivated_at is not null))
);
create unique index maintenance_categories_tenant_code_uq
  on public.maintenance_categories (tenant_id,pg_catalog.lower(code)) where code is not null;
create index maintenance_categories_tenant_status_name_idx
  on public.maintenance_categories (tenant_id,status,pg_catalog.lower(name),id);

create table public.maintenance_subcategories (
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
  constraint maintenance_subcategories_tenant_id_id_uq unique (tenant_id,id),
  constraint maintenance_subcategories_category_fk foreign key (tenant_id,category_id)
    references public.maintenance_categories (tenant_id,id) on delete restrict,
  constraint maintenance_subcategories_code_ck check (code is null or (code = pg_catalog.btrim(code) and code ~ '^[A-Za-z0-9][A-Za-z0-9._/-]{0,63}$')),
  constraint maintenance_subcategories_name_ck check (name = pg_catalog.btrim(name) and pg_catalog.char_length(name) between 1 and 160),
  constraint maintenance_subcategories_description_ck check (description is null or (description = pg_catalog.btrim(description) and pg_catalog.char_length(description) <= 2000)),
  constraint maintenance_subcategories_status_ck check (status in ('active','inactive')),
  constraint maintenance_subcategories_version_ck check (version > 0),
  constraint maintenance_subcategories_lifecycle_ck check ((status='active' and inactivated_at is null) or (status='inactive' and inactivated_at is not null))
);
create unique index maintenance_subcategories_category_code_uq
  on public.maintenance_subcategories (tenant_id,category_id,pg_catalog.lower(code)) where code is not null;
create index maintenance_subcategories_tenant_category_status_name_idx
  on public.maintenance_subcategories (tenant_id,category_id,status,pg_catalog.lower(name),id);

create table private.catalog_templates (
  id uuid primary key,
  template_key text not null,
  template_version bigint not null,
  schema_version integer not null,
  name text not null,
  status text not null,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  constraint catalog_templates_identity_uq unique (template_key,template_version),
  constraint catalog_templates_key_ck check (template_key ~ '^[a-z][a-z0-9_]{2,79}$'),
  constraint catalog_templates_version_ck check (template_version > 0 and schema_version > 0),
  constraint catalog_templates_name_ck check (name = pg_catalog.btrim(name) and pg_catalog.char_length(name) between 1 and 160),
  constraint catalog_templates_status_ck check (status in ('active','retired'))
);

create table private.catalog_template_entries (
  id uuid primary key,
  template_id uuid not null references private.catalog_templates (id) on delete restrict,
  entry_key text not null,
  entry_kind text not null,
  parent_entry_key text,
  code text not null,
  name text not null,
  position integer not null,
  constraint catalog_template_entries_template_key_uq unique (template_id,entry_key),
  constraint catalog_template_entries_template_position_uq unique (template_id,position),
  constraint catalog_template_entries_parent_fk foreign key (template_id,parent_entry_key)
    references private.catalog_template_entries (template_id,entry_key) on delete restrict,
  constraint catalog_template_entries_key_ck check (entry_key ~ '^[a-z][a-z0-9_]{2,119}$'),
  constraint catalog_template_entries_kind_ck check (entry_kind in ('maintenance_category','maintenance_subcategory')),
  constraint catalog_template_entries_parent_ck check (
    (entry_kind='maintenance_category' and parent_entry_key is null)
    or (entry_kind='maintenance_subcategory' and parent_entry_key is not null)
  ),
  constraint catalog_template_entries_code_ck check (code ~ '^[A-Z0-9][A-Z0-9_]{0,63}$'),
  constraint catalog_template_entries_name_ck check (name = pg_catalog.btrim(name) and pg_catalog.char_length(name) between 1 and 160),
  constraint catalog_template_entries_position_ck check (position > 0)
);

create table private.catalog_template_applications (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete restrict,
  template_key text not null,
  template_version bigint not null,
  status text not null default 'applied',
  version bigint not null default 1,
  category_ids uuid[] not null,
  subcategory_ids uuid[] not null,
  category_count integer not null,
  subcategory_count integer not null,
  command_id uuid not null,
  command_correlation_id uuid not null,
  applied_at timestamptz not null default pg_catalog.clock_timestamp(),
  applied_by uuid not null references public.app_users (id) on delete restrict,
  constraint catalog_template_applications_tenant_template_uq unique (tenant_id,template_key),
  constraint catalog_template_applications_status_ck check (status='applied'),
  constraint catalog_template_applications_version_ck check (version > 0 and template_version > 0),
  constraint catalog_template_applications_counts_ck check (
    category_count = pg_catalog.cardinality(category_ids)
    and subcategory_count = pg_catalog.cardinality(subcategory_ids)
    and category_count > 0 and subcategory_count > 0
  )
);

revoke all on table private.catalog_templates, private.catalog_template_entries,
  private.catalog_template_applications from public, anon, authenticated, service_role, cw_worker;

insert into private.catalog_templates (id,template_key,template_version,schema_version,name,status)
values ('4c200000-0000-4000-8000-000000000001','cw_maintenance_taxonomy',1,1,'Template CW de taxonomia de manutenção','active');

insert into private.catalog_template_entries (id,template_id,entry_key,entry_kind,parent_entry_key,code,name,position)
values
('4c210000-0000-4000-8000-000000000001','4c200000-0000-4000-8000-000000000001','category_electrical','maintenance_category',null,'ELETRICA','Elétrica',1),
('4c210000-0000-4000-8000-000000000002','4c200000-0000-4000-8000-000000000001','category_hydraulic','maintenance_category',null,'HIDRAULICA','Hidráulica',2),
('4c210000-0000-4000-8000-000000000003','4c200000-0000-4000-8000-000000000001','category_civil','maintenance_category',null,'CIVIL','Civil',3),
('4c210000-0000-4000-8000-000000000004','4c200000-0000-4000-8000-000000000001','category_hvac','maintenance_category',null,'CLIMATIZACAO','Climatização',4),
('4c210000-0000-4000-8000-000000000005','4c200000-0000-4000-8000-000000000001','category_fire_safety','maintenance_category',null,'SEGURANCA_INCENDIO','Segurança contra incêndio',5),
('4c210000-0000-4000-8000-000000000006','4c200000-0000-4000-8000-000000000001','category_elevators','maintenance_category',null,'ELEVADORES','Elevadores',6),
('4c210000-0000-4000-8000-000000000007','4c200000-0000-4000-8000-000000000001','category_doors_access','maintenance_category',null,'PORTAS_ACESSOS','Portas e acessos',7),
('4c210000-0000-4000-8000-000000000008','4c200000-0000-4000-8000-000000000001','category_cctv_security','maintenance_category',null,'CFTV_SEGURANCA_ELETRONICA','CFTV e segurança eletrônica',8),
('4c210000-0000-4000-8000-000000000009','4c200000-0000-4000-8000-000000000001','category_gardening_outdoors','maintenance_category',null,'JARDINAGEM_AREAS_EXTERNAS','Jardinagem e áreas externas',9),
('4c210000-0000-4000-8000-000000000010','4c200000-0000-4000-8000-000000000001','category_cleaning_conservation','maintenance_category',null,'LIMPEZA_CONSERVACAO','Limpeza e conservação',10),
('4c210000-0000-4000-8000-000000000011','4c200000-0000-4000-8000-000000000001','category_other','maintenance_category',null,'OUTROS','Outros',11),
('4c220000-0000-4000-8000-000000000001','4c200000-0000-4000-8000-000000000001','electrical_lighting','maintenance_subcategory','category_electrical','ILUMINACAO','Iluminação',101),
('4c220000-0000-4000-8000-000000000002','4c200000-0000-4000-8000-000000000001','electrical_outlets','maintenance_subcategory','category_electrical','TOMADAS','Tomadas',102),
('4c220000-0000-4000-8000-000000000003','4c200000-0000-4000-8000-000000000001','electrical_panels','maintenance_subcategory','category_electrical','QUADROS_ELETRICOS','Quadros elétricos',103),
('4c220000-0000-4000-8000-000000000004','4c200000-0000-4000-8000-000000000001','electrical_circuits','maintenance_subcategory','category_electrical','CIRCUITOS','Circuitos',104),
('4c220000-0000-4000-8000-000000000005','4c200000-0000-4000-8000-000000000001','electrical_emergency_lighting','maintenance_subcategory','category_electrical','ILUMINACAO_EMERGENCIA','Iluminação de emergência',105),
('4c220000-0000-4000-8000-000000000006','4c200000-0000-4000-8000-000000000001','hydraulic_supply','maintenance_subcategory','category_hydraulic','ABASTECIMENTO','Abastecimento',201),
('4c220000-0000-4000-8000-000000000007','4c200000-0000-4000-8000-000000000001','hydraulic_leaks','maintenance_subcategory','category_hydraulic','VAZAMENTOS','Vazamentos',202),
('4c220000-0000-4000-8000-000000000008','4c200000-0000-4000-8000-000000000001','hydraulic_sewage','maintenance_subcategory','category_hydraulic','ESGOTO','Esgoto',203),
('4c220000-0000-4000-8000-000000000009','4c200000-0000-4000-8000-000000000001','hydraulic_pumps','maintenance_subcategory','category_hydraulic','BOMBAS','Bombas',204),
('4c220000-0000-4000-8000-000000000010','4c200000-0000-4000-8000-000000000001','hydraulic_reservoirs','maintenance_subcategory','category_hydraulic','RESERVATORIOS','Reservatórios',205),
('4c220000-0000-4000-8000-000000000011','4c200000-0000-4000-8000-000000000001','civil_masonry','maintenance_subcategory','category_civil','ALVENARIA','Alvenaria',301),
('4c220000-0000-4000-8000-000000000012','4c200000-0000-4000-8000-000000000001','civil_painting','maintenance_subcategory','category_civil','PINTURA','Pintura',302),
('4c220000-0000-4000-8000-000000000013','4c200000-0000-4000-8000-000000000001','civil_coatings','maintenance_subcategory','category_civil','REVESTIMENTOS','Revestimentos',303),
('4c220000-0000-4000-8000-000000000014','4c200000-0000-4000-8000-000000000001','civil_waterproofing','maintenance_subcategory','category_civil','IMPERMEABILIZACAO','Impermeabilização',304),
('4c220000-0000-4000-8000-000000000015','4c200000-0000-4000-8000-000000000001','civil_roofing','maintenance_subcategory','category_civil','COBERTURA','Cobertura',305),
('4c220000-0000-4000-8000-000000000016','4c200000-0000-4000-8000-000000000001','hvac_air_conditioning','maintenance_subcategory','category_hvac','AR_CONDICIONADO','Ar-condicionado',401),
('4c220000-0000-4000-8000-000000000017','4c200000-0000-4000-8000-000000000001','hvac_vrf','maintenance_subcategory','category_hvac','VRF','VRF',402),
('4c220000-0000-4000-8000-000000000018','4c200000-0000-4000-8000-000000000001','hvac_ventilation','maintenance_subcategory','category_hvac','VENTILACAO','Ventilação',403),
('4c220000-0000-4000-8000-000000000019','4c200000-0000-4000-8000-000000000001','hvac_exhaust','maintenance_subcategory','category_hvac','EXAUSTAO','Exaustão',404),
('4c220000-0000-4000-8000-000000000020','4c200000-0000-4000-8000-000000000001','fire_extinguishers','maintenance_subcategory','category_fire_safety','EXTINTORES','Extintores',501),
('4c220000-0000-4000-8000-000000000021','4c200000-0000-4000-8000-000000000001','fire_hydrants','maintenance_subcategory','category_fire_safety','HIDRANTES','Hidrantes',502),
('4c220000-0000-4000-8000-000000000022','4c200000-0000-4000-8000-000000000001','fire_alarm','maintenance_subcategory','category_fire_safety','ALARME','Alarme',503),
('4c220000-0000-4000-8000-000000000023','4c200000-0000-4000-8000-000000000001','fire_emergency_lighting','maintenance_subcategory','category_fire_safety','ILUMINACAO_EMERGENCIA','Iluminação de emergência',504),
('4c220000-0000-4000-8000-000000000024','4c200000-0000-4000-8000-000000000001','elevators_elevators','maintenance_subcategory','category_elevators','ELEVADORES','Elevadores',601),
('4c220000-0000-4000-8000-000000000025','4c200000-0000-4000-8000-000000000001','elevators_platforms','maintenance_subcategory','category_elevators','PLATAFORMAS','Plataformas',602),
('4c220000-0000-4000-8000-000000000026','4c200000-0000-4000-8000-000000000001','elevators_vertical_transport','maintenance_subcategory','category_elevators','TRANSPORTE_VERTICAL','Transporte vertical',603),
('4c220000-0000-4000-8000-000000000027','4c200000-0000-4000-8000-000000000001','doors_doors','maintenance_subcategory','category_doors_access','PORTAS','Portas',701),
('4c220000-0000-4000-8000-000000000028','4c200000-0000-4000-8000-000000000001','doors_locks','maintenance_subcategory','category_doors_access','FECHADURAS','Fechaduras',702),
('4c220000-0000-4000-8000-000000000029','4c200000-0000-4000-8000-000000000001','doors_gates','maintenance_subcategory','category_doors_access','PORTOES','Portões',703),
('4c220000-0000-4000-8000-000000000030','4c200000-0000-4000-8000-000000000001','doors_access_control','maintenance_subcategory','category_doors_access','CONTROLE_ACESSO','Controle de acesso',704),
('4c220000-0000-4000-8000-000000000031','4c200000-0000-4000-8000-000000000001','cctv_cameras','maintenance_subcategory','category_cctv_security','CAMERAS','Câmeras',801),
('4c220000-0000-4000-8000-000000000032','4c200000-0000-4000-8000-000000000001','cctv_recorders','maintenance_subcategory','category_cctv_security','GRAVADORES','Gravadores',802),
('4c220000-0000-4000-8000-000000000033','4c200000-0000-4000-8000-000000000001','cctv_sensors','maintenance_subcategory','category_cctv_security','SENSORES','Sensores',803),
('4c220000-0000-4000-8000-000000000034','4c200000-0000-4000-8000-000000000001','gardening_landscaping','maintenance_subcategory','category_gardening_outdoors','PAISAGISMO','Paisagismo',901),
('4c220000-0000-4000-8000-000000000035','4c200000-0000-4000-8000-000000000001','gardening_irrigation','maintenance_subcategory','category_gardening_outdoors','IRRIGACAO','Irrigação',902),
('4c220000-0000-4000-8000-000000000036','4c200000-0000-4000-8000-000000000001','gardening_outdoor_areas','maintenance_subcategory','category_gardening_outdoors','AREAS_EXTERNAS','Áreas externas',903),
('4c220000-0000-4000-8000-000000000037','4c200000-0000-4000-8000-000000000001','cleaning_technical','maintenance_subcategory','category_cleaning_conservation','LIMPEZA_TECNICA','Limpeza técnica',1001),
('4c220000-0000-4000-8000-000000000038','4c200000-0000-4000-8000-000000000001','cleaning_conservation','maintenance_subcategory','category_cleaning_conservation','CONSERVACAO','Conservação',1002),
('4c220000-0000-4000-8000-000000000039','4c200000-0000-4000-8000-000000000001','other_residual','maintenance_subcategory','category_other','CLASSIFICACAO_GENERICA_RESIDUAL','classificação genérica residual',1101);

create function private.protect_w4c_taxonomy_mutation()
returns trigger language plpgsql set search_path='' as $$
begin
  if tg_op='DELETE' then raise exception using errcode='42501',message='MAINTENANCE_TAXONOMY_DELETE_FORBIDDEN'; end if;
  if new.id<>old.id or new.tenant_id<>old.tenant_id or new.created_at<>old.created_at
     or new.created_by<>old.created_by or new.version<>old.version then
    raise exception using errcode='42501',message='MAINTENANCE_TAXONOMY_PROTECTED_FIELD';
  end if;
  return new;
end $$;
revoke all on function private.protect_w4c_taxonomy_mutation() from public,anon,authenticated,service_role,cw_worker;

create trigger maintenance_categories_protect_mutation before update or delete on public.maintenance_categories
for each row execute function private.protect_w4c_taxonomy_mutation();
create trigger maintenance_categories_set_updated_at_and_version before update on public.maintenance_categories
for each row execute function private.set_updated_at_and_version();
create trigger maintenance_subcategories_protect_mutation before update or delete on public.maintenance_subcategories
for each row execute function private.protect_w4c_taxonomy_mutation();
create trigger maintenance_subcategories_set_updated_at_and_version before update on public.maintenance_subcategories
for each row execute function private.set_updated_at_and_version();

alter table public.maintenance_categories enable row level security;
alter table public.maintenance_categories force row level security;
alter table public.maintenance_subcategories enable row level security;
alter table public.maintenance_subcategories force row level security;
revoke all on table public.maintenance_categories, public.maintenance_subcategories
  from public,anon,authenticated,service_role,cw_worker;
grant select on table public.maintenance_categories, public.maintenance_subcategories to authenticated;

create function private.can_access_w4c_taxonomy(target_tenant_id uuid,target_resource_code text,target_action_code text)
returns boolean language sql stable security definer set search_path='' as $$
  select exists (
    select 1 from public.tenant_memberships membership
    join public.app_users app_user on app_user.id=membership.user_id and app_user.status='active'
    join public.tenants tenant on tenant.id=membership.tenant_id and tenant.status='active'
    join public.tenant_profiles profile on profile.id=membership.profile_id and profile.tenant_id=membership.tenant_id and profile.status='active'
    where membership.user_id=auth.uid() and membership.tenant_id=target_tenant_id and membership.status='active'
      and private.has_effective_permission(target_resource_code,target_action_code,'ALL_TENANT'::public.authorization_scope)
  )
$$;
revoke all on function private.can_access_w4c_taxonomy(uuid,text,text) from public,anon,authenticated,service_role,cw_worker;
alter function private.can_access_w4c_taxonomy(uuid,text,text) owner to postgres;

create function private.assert_w4c_taxonomy_access(target_resource_code text,target_action_code text)
returns uuid language plpgsql security definer set search_path='' as $$
declare target_tenant_id uuid;
begin
  select membership.tenant_id into target_tenant_id from public.tenant_memberships membership
  where membership.user_id=auth.uid() and membership.status='active';
  if target_tenant_id is null or not private.can_access_w4c_taxonomy(target_tenant_id,target_resource_code,target_action_code) then
    raise exception using errcode='42501',message='AUTHORIZATION_DENIED';
  end if;
  return target_tenant_id;
end $$;
revoke all on function private.assert_w4c_taxonomy_access(text,text) from public,anon,authenticated,service_role,cw_worker;
alter function private.assert_w4c_taxonomy_access(text,text) owner to postgres;

create policy maintenance_categories_read on public.maintenance_categories for select to authenticated
using (private.can_access_w4c_taxonomy(tenant_id,'maintenance_categories','read'));
create policy maintenance_subcategories_read on public.maintenance_subcategories for select to authenticated
using (private.can_access_w4c_taxonomy(tenant_id,'maintenance_subcategories','read'));

create function private.execute_w4c_taxonomy_command(
  target_resource text,target_action text,target_id uuid,expected_version bigint,
  target_category_id uuid,target_code text,target_name text,target_description text,
  command_reason text,command_correlation_id uuid,command_idempotency_key text
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  actor record; idem record; fingerprint bytea;
  entity_id uuid:=coalesce(target_id,pg_catalog.gen_random_uuid());
  correlation_id uuid:=coalesce(command_correlation_id,pg_catalog.gen_random_uuid());
  command_name text; aggregate_type text; event_type text; event_action text;
  entity_version bigint; entity_status text; entity_code text; entity_name text; entity_category_id uuid;
  current_record record; category_status text; result jsonb;
begin
  if target_resource not in ('maintenance_categories','maintenance_subcategories')
     or target_action not in ('create','update','inactivate','reactivate') then
    raise exception using errcode='22023',message='INVALID_MAINTENANCE_TAXONOMY_COMMAND';
  end if;
  if command_reason is null or command_reason<>pg_catalog.btrim(command_reason)
     or pg_catalog.char_length(command_reason) not between 1 and 500 then
    raise exception using errcode='22023',message='INVALID_COMMAND_REASON';
  end if;
  select * into actor from private.lock_authorization_actor(target_resource,target_action);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(actor.actor_tenant_id::text||':maintenance_taxonomy',0));
  command_name:='maintenance.'||target_action||'_'||case when target_resource='maintenance_categories' then 'maintenance_category' else 'maintenance_subcategory' end;
  fingerprint:=private.semantic_fingerprint(pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
    'resource',target_resource,'action',target_action,'id',target_id,'expected_version',expected_version,
    'category_id',target_category_id,'code',target_code,'name',target_name,'description',target_description)));
  select * into idem from private.acquire_command_idempotency(actor.actor_tenant_id,'application_user','user_command',
    command_name,command_idempotency_key,fingerprint,actor.actor_user_id,null,null);
  if idem.replayed then return idem.stored_result; end if;
  aggregate_type:=case target_resource when 'maintenance_categories' then 'maintenance_category' else 'maintenance_subcategory' end;
  event_action:=case target_action when 'create' then 'created' when 'update' then 'updated'
    when 'inactivate' then 'inactivated' else 'reactivated' end;
  event_type:='maintenance.'||case target_resource when 'maintenance_categories' then 'category' else 'subcategory' end||'.'||event_action;

  if target_action='create' then
    if target_name is null or target_name<>pg_catalog.btrim(target_name) then
      raise exception using errcode='22023',message='INVALID_MAINTENANCE_TAXONOMY_NAME';
    end if;
    if target_resource='maintenance_categories' then
      insert into public.maintenance_categories(id,tenant_id,code,name,description,created_by,updated_by)
      values(entity_id,actor.actor_tenant_id,target_code,target_name,target_description,actor.actor_user_id,actor.actor_user_id)
      returning version,status,code,name into entity_version,entity_status,entity_code,entity_name;
    else
      select id,status into current_record from public.maintenance_categories
      where tenant_id=actor.actor_tenant_id and id=target_category_id for update;
      if not found or current_record.status<>'active' then
        raise exception using errcode='P0001',message='MAINTENANCE_CATEGORY_UNAVAILABLE';
      end if;
      insert into public.maintenance_subcategories(id,tenant_id,category_id,code,name,description,created_by,updated_by)
      values(entity_id,actor.actor_tenant_id,target_category_id,target_code,target_name,target_description,actor.actor_user_id,actor.actor_user_id)
      returning version,status,code,name,category_id into entity_version,entity_status,entity_code,entity_name,entity_category_id;
    end if;
  elsif target_action='update' then
    if target_id is null or expected_version is null or target_name is null or target_name<>pg_catalog.btrim(target_name) then
      raise exception using errcode='22023',message='INVALID_UPDATE_INPUT';
    end if;
    if target_resource='maintenance_categories' then
      update public.maintenance_categories set code=target_code,name=target_name,description=target_description,updated_by=actor.actor_user_id
      where tenant_id=actor.actor_tenant_id and id=target_id and version=expected_version and status='active'
      returning version,status,code,name into entity_version,entity_status,entity_code,entity_name;
    else
      select id,status into current_record from public.maintenance_categories
      where tenant_id=actor.actor_tenant_id and id=target_category_id for update;
      if not found or current_record.status<>'active' then
        raise exception using errcode='P0001',message='MAINTENANCE_CATEGORY_UNAVAILABLE';
      end if;
      update public.maintenance_subcategories set category_id=target_category_id,code=target_code,name=target_name,
        description=target_description,updated_by=actor.actor_user_id
      where tenant_id=actor.actor_tenant_id and id=target_id and version=expected_version and status='active'
      returning version,status,code,name,category_id into entity_version,entity_status,entity_code,entity_name,entity_category_id;
    end if;
    if not found then raise exception using errcode='P0001',message='MAINTENANCE_TAXONOMY_VERSION_CONFLICT'; end if;
  else
    if target_id is null or expected_version is null then
      raise exception using errcode='22023',message='INVALID_STATUS_INPUT';
    end if;
    if target_resource='maintenance_categories' then
      if target_action='inactivate' and exists(select 1 from public.maintenance_subcategories s
        where s.tenant_id=actor.actor_tenant_id and s.category_id=target_id and s.status='active') then
        raise exception using errcode='23514',message='ACTIVE_MAINTENANCE_SUBCATEGORY_DEPENDENCY';
      end if;
      update public.maintenance_categories set status=case target_action when 'inactivate' then 'inactive' else 'active' end,
        inactivated_at=case target_action when 'inactivate' then pg_catalog.statement_timestamp() else null end,
        updated_by=actor.actor_user_id
      where tenant_id=actor.actor_tenant_id and id=target_id and version=expected_version
        and status=case target_action when 'inactivate' then 'active' else 'inactive' end
      returning version,status,code,name into entity_version,entity_status,entity_code,entity_name;
    else
      select s.category_id,c.status into entity_category_id,category_status
      from public.maintenance_subcategories s join public.maintenance_categories c
        on c.tenant_id=s.tenant_id and c.id=s.category_id
      where s.tenant_id=actor.actor_tenant_id and s.id=target_id for update of c;
      if target_action='reactivate' and (not found or category_status<>'active') then
        raise exception using errcode='23514',message='MAINTENANCE_CATEGORY_INACTIVE';
      end if;
      update public.maintenance_subcategories set status=case target_action when 'inactivate' then 'inactive' else 'active' end,
        inactivated_at=case target_action when 'inactivate' then pg_catalog.statement_timestamp() else null end,
        updated_by=actor.actor_user_id
      where tenant_id=actor.actor_tenant_id and id=target_id and version=expected_version
        and status=case target_action when 'inactivate' then 'active' else 'inactive' end
      returning version,status,code,name,category_id into entity_version,entity_status,entity_code,entity_name,entity_category_id;
    end if;
    if not found then raise exception using errcode='P0001',message='MAINTENANCE_TAXONOMY_STATE_OR_VERSION_CONFLICT'; end if;
  end if;

  perform private.append_audit(actor.actor_tenant_id,'application_user',event_type,aggregate_type,correlation_id,'user_command',
    actor.actor_user_id,null,entity_id,idem.acquired_command_id,null,1,command_reason,
    pg_catalog.jsonb_build_object('version',entity_version,'status',entity_status));
  perform private.append_history(actor.actor_tenant_id,aggregate_type,entity_id,event_type,'application_user',command_name,
    idem.acquired_command_id,correlation_id,'user_command',entity_version,entity_code,1,actor.actor_user_id,null,null,
    pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object('name',entity_name,'status',entity_status,'category_id',entity_category_id)));
  perform private.enqueue_event(actor.actor_tenant_id,event_type,'application_user','user_command',idem.acquired_command_id,correlation_id,
    aggregate_type,entity_id,1,entity_version,actor.actor_user_id,null,null,
    pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object('id',entity_id,'version',entity_version,'status',entity_status,'code',entity_code,'category_id',entity_category_id)),
    pg_catalog.jsonb_build_object('command',command_name));
  result:=pg_catalog.jsonb_build_object('id',entity_id,'version',entity_version,'status',entity_status,'command_correlation_id',correlation_id);
  perform private.complete_command_idempotency(idem.acquired_command_id,1,result);
  return result;
end $$;
revoke all on function private.execute_w4c_taxonomy_command(text,text,uuid,bigint,uuid,text,text,text,text,uuid,text)
from public,anon,authenticated,service_role,cw_worker;
alter function private.execute_w4c_taxonomy_command(text,text,uuid,bigint,uuid,text,text,text,text,uuid,text) owner to postgres;

create function public.create_maintenance_category(code text,name text,description text,reason text,correlation_id uuid,idempotency_key text) returns jsonb
language sql security definer set search_path='' as $$ select private.execute_w4c_taxonomy_command('maintenance_categories','create',null,null,null,code,name,description,reason,correlation_id,idempotency_key) $$;
create function public.update_maintenance_category(id uuid,expected_version bigint,code text,name text,description text,reason text,correlation_id uuid,idempotency_key text) returns jsonb
language sql security definer set search_path='' as $$ select private.execute_w4c_taxonomy_command('maintenance_categories','update',id,expected_version,null,code,name,description,reason,correlation_id,idempotency_key) $$;
create function public.inactivate_maintenance_category(id uuid,expected_version bigint,reason text,correlation_id uuid,idempotency_key text) returns jsonb
language sql security definer set search_path='' as $$ select private.execute_w4c_taxonomy_command('maintenance_categories','inactivate',id,expected_version,null,null,null,null,reason,correlation_id,idempotency_key) $$;
create function public.reactivate_maintenance_category(id uuid,expected_version bigint,reason text,correlation_id uuid,idempotency_key text) returns jsonb
language sql security definer set search_path='' as $$ select private.execute_w4c_taxonomy_command('maintenance_categories','reactivate',id,expected_version,null,null,null,null,reason,correlation_id,idempotency_key) $$;
create function public.create_maintenance_subcategory(category_id uuid,code text,name text,description text,reason text,correlation_id uuid,idempotency_key text) returns jsonb
language sql security definer set search_path='' as $$ select private.execute_w4c_taxonomy_command('maintenance_subcategories','create',null,null,category_id,code,name,description,reason,correlation_id,idempotency_key) $$;
create function public.update_maintenance_subcategory(id uuid,expected_version bigint,category_id uuid,code text,name text,description text,reason text,correlation_id uuid,idempotency_key text) returns jsonb
language sql security definer set search_path='' as $$ select private.execute_w4c_taxonomy_command('maintenance_subcategories','update',id,expected_version,category_id,code,name,description,reason,correlation_id,idempotency_key) $$;
create function public.inactivate_maintenance_subcategory(id uuid,expected_version bigint,reason text,correlation_id uuid,idempotency_key text) returns jsonb
language sql security definer set search_path='' as $$ select private.execute_w4c_taxonomy_command('maintenance_subcategories','inactivate',id,expected_version,null,null,null,null,reason,correlation_id,idempotency_key) $$;
create function public.reactivate_maintenance_subcategory(id uuid,expected_version bigint,reason text,correlation_id uuid,idempotency_key text) returns jsonb
language sql security definer set search_path='' as $$ select private.execute_w4c_taxonomy_command('maintenance_subcategories','reactivate',id,expected_version,null,null,null,null,reason,correlation_id,idempotency_key) $$;

create function public.list_maintenance_categories(search_text text default null,status_filter text default null,result_limit integer default 50,result_offset integer default 0)
returns table(id uuid,code text,name text,description text,status text,version bigint,updated_at timestamptz)
language plpgsql security definer set search_path='' as $$ declare t uuid; begin t:=private.assert_w4c_taxonomy_access('maintenance_categories','read');
if result_limit not between 1 and 100 or result_offset<0 or (status_filter is not null and status_filter not in ('active','inactive')) then raise exception using errcode='22023',message='INVALID_QUERY_INPUT'; end if;
return query select x.id,x.code,x.name,x.description,x.status,x.version,x.updated_at from public.maintenance_categories x where x.tenant_id=t and (status_filter is null or x.status=status_filter) and (search_text is null or x.name ilike '%'||search_text||'%' or x.code ilike '%'||search_text||'%') order by pg_catalog.lower(x.name),x.id limit result_limit offset result_offset; end $$;
create function public.get_maintenance_category(target_id uuid)
returns table(id uuid,code text,name text,description text,status text,version bigint,created_at timestamptz,updated_at timestamptz)
language plpgsql security definer set search_path='' as $$ declare t uuid; begin t:=private.assert_w4c_taxonomy_access('maintenance_categories','read'); return query select x.id,x.code,x.name,x.description,x.status,x.version,x.created_at,x.updated_at from public.maintenance_categories x where x.tenant_id=t and x.id=target_id; end $$;
create function public.lookup_maintenance_categories(search_text text default null,result_limit integer default 20)
returns table(id uuid,code text,name text)
language plpgsql security definer set search_path='' as $$ declare t uuid; begin t:=private.assert_w4c_taxonomy_access('maintenance_categories','lookup'); if result_limit not between 1 and 100 then raise exception using errcode='22023',message='INVALID_QUERY_INPUT'; end if; return query select x.id,x.code,x.name from public.maintenance_categories x where x.tenant_id=t and x.status='active' and (search_text is null or x.name ilike '%'||search_text||'%' or x.code ilike '%'||search_text||'%') order by pg_catalog.lower(x.name),x.id limit result_limit; end $$;

create function public.list_maintenance_subcategories(category_filter uuid default null,search_text text default null,status_filter text default null,result_limit integer default 50,result_offset integer default 0)
returns table(id uuid,category_id uuid,code text,name text,description text,status text,version bigint,updated_at timestamptz)
language plpgsql security definer set search_path='' as $$ declare t uuid; begin t:=private.assert_w4c_taxonomy_access('maintenance_subcategories','read'); if result_limit not between 1 and 100 or result_offset<0 or (status_filter is not null and status_filter not in ('active','inactive')) then raise exception using errcode='22023',message='INVALID_QUERY_INPUT'; end if; return query select x.id,x.category_id,x.code,x.name,x.description,x.status,x.version,x.updated_at from public.maintenance_subcategories x where x.tenant_id=t and (category_filter is null or x.category_id=category_filter) and (status_filter is null or x.status=status_filter) and (search_text is null or x.name ilike '%'||search_text||'%' or x.code ilike '%'||search_text||'%') order by pg_catalog.lower(x.name),x.id limit result_limit offset result_offset; end $$;
create function public.get_maintenance_subcategory(target_id uuid)
returns table(id uuid,category_id uuid,code text,name text,description text,status text,version bigint,created_at timestamptz,updated_at timestamptz)
language plpgsql security definer set search_path='' as $$ declare t uuid; begin t:=private.assert_w4c_taxonomy_access('maintenance_subcategories','read'); return query select x.id,x.category_id,x.code,x.name,x.description,x.status,x.version,x.created_at,x.updated_at from public.maintenance_subcategories x where x.tenant_id=t and x.id=target_id; end $$;
create function public.lookup_maintenance_subcategories(category_filter uuid default null,search_text text default null,result_limit integer default 20)
returns table(id uuid,code text,name text)
language plpgsql security definer set search_path='' as $$ declare t uuid; begin t:=private.assert_w4c_taxonomy_access('maintenance_subcategories','lookup'); if result_limit not between 1 and 100 then raise exception using errcode='22023',message='INVALID_QUERY_INPUT'; end if; return query select x.id,x.code,x.name from public.maintenance_subcategories x where x.tenant_id=t and x.status='active' and (category_filter is null or x.category_id=category_filter) and (search_text is null or x.name ilike '%'||search_text||'%' or x.code ilike '%'||search_text||'%') order by pg_catalog.lower(x.name),x.id limit result_limit; end $$;

create function public.get_cw_catalog_template_preview(template_key text default 'cw_maintenance_taxonomy',template_version bigint default 1)
returns jsonb
language plpgsql security definer set search_path='' as $$
declare t uuid; preview jsonb;
begin
  t:=private.assert_w4c_taxonomy_access('catalog_templates','apply');
  select pg_catalog.jsonb_build_object(
    'template_key',template.template_key,'template_version',template.template_version,
    'category_count',count(*) filter(where entry.entry_kind='maintenance_category')::integer,
    'subcategory_count',count(*) filter(where entry.entry_kind='maintenance_subcategory')::integer,
    'categories',(select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'key',category.entry_key,'code',category.code,'name',category.name,'subcategories',
      (select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('key',child.entry_key,'code',child.code,'name',child.name) order by child.position)
       from private.catalog_template_entries child where child.template_id=template.id and child.parent_entry_key=category.entry_key)
    ) order by category.position) from private.catalog_template_entries category
      where category.template_id=template.id and category.entry_kind='maintenance_category')) into preview
  from private.catalog_templates template join private.catalog_template_entries entry on entry.template_id=template.id
  where template.template_key=$1 and template.template_version=$2 and template.status='active'
  group by template.id,template.template_key,template.template_version;
  if preview is null then raise exception using errcode='P0001',message='CW_CATALOG_TEMPLATE_UNAVAILABLE'; end if;
  return preview;
end $$;

create function public.apply_cw_catalog_template(template_key text,template_version bigint,reason text,correlation_id uuid,idempotency_key text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  actor record; idem record; template record; entry record; application record;
  fingerprint bytea; command_correlation_id uuid:=coalesce(correlation_id,pg_catalog.gen_random_uuid());
  category_map jsonb:='{}'::jsonb; category_ids uuid[]:='{}'::uuid[]; subcategory_ids uuid[]:='{}'::uuid[];
  created_id uuid; result jsonb;
begin
  if reason is null or reason<>pg_catalog.btrim(reason) or pg_catalog.char_length(reason) not between 1 and 500 then
    raise exception using errcode='22023',message='INVALID_COMMAND_REASON';
  end if;
  select * into actor from private.lock_authorization_actor('catalog_templates','apply');
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(actor.actor_tenant_id::text||':maintenance_taxonomy',0));
  fingerprint:=private.semantic_fingerprint(pg_catalog.jsonb_build_object('template_key',template_key,'template_version',template_version));
  select * into idem from private.acquire_command_idempotency(actor.actor_tenant_id,'application_user','user_command',
    'maintenance.apply_cw_catalog_template',idempotency_key,fingerprint,actor.actor_user_id,null,null);
  if idem.replayed then return idem.stored_result; end if;
  select * into template from private.catalog_templates t
    where t.template_key=$1 and t.template_version=$2 and t.status='active' for update;
  if not found then raise exception using errcode='P0001',message='CW_CATALOG_TEMPLATE_UNAVAILABLE'; end if;

  select * into application from private.catalog_template_applications a
    where a.tenant_id=actor.actor_tenant_id and a.template_key=template.template_key for update;
  if found then
    if application.template_version<>template.template_version then raise exception using errcode='P0001',message='CW_CATALOG_TEMPLATE_ALREADY_APPLIED'; end if;
    result:=pg_catalog.jsonb_build_object('id',application.id,'version',application.version,'status',application.status,
      'command_correlation_id',application.command_correlation_id,'template_key',application.template_key,
      'template_version',application.template_version,'category_ids',application.category_ids,
      'subcategory_ids',application.subcategory_ids,'category_count',application.category_count,'subcategory_count',application.subcategory_count);
    perform private.complete_command_idempotency(idem.acquired_command_id,1,result);
    return result;
  end if;
  if exists(select 1 from public.maintenance_categories c where c.tenant_id=actor.actor_tenant_id)
     or exists(select 1 from public.maintenance_subcategories s where s.tenant_id=actor.actor_tenant_id) then
    raise exception using errcode='23514',message='MAINTENANCE_TAXONOMY_NOT_EMPTY';
  end if;

  for entry in select e.* from private.catalog_template_entries e where e.template_id=template.id and e.entry_kind='maintenance_category' order by e.position loop
    created_id:=pg_catalog.gen_random_uuid();
    insert into public.maintenance_categories(id,tenant_id,code,name,created_by,updated_by)
    values(created_id,actor.actor_tenant_id,entry.code,entry.name,actor.actor_user_id,actor.actor_user_id);
    category_ids:=pg_catalog.array_append(category_ids,created_id);
    category_map:=category_map||pg_catalog.jsonb_build_object(entry.entry_key,created_id);
    perform private.append_history(actor.actor_tenant_id,'maintenance_category',created_id,'maintenance.category.created','application_user',
      'maintenance.apply_cw_catalog_template',idem.acquired_command_id,command_correlation_id,'user_command',1,entry.code,1,actor.actor_user_id,null,null,
      pg_catalog.jsonb_build_object('name',entry.name,'status','active','template_key',template.template_key));
    perform private.enqueue_event(actor.actor_tenant_id,'maintenance.category.created','application_user','user_command',idem.acquired_command_id,
      command_correlation_id,'maintenance_category',created_id,1,1,actor.actor_user_id,null,null,
      pg_catalog.jsonb_build_object('id',created_id,'version',1,'status','active','code',entry.code),
      pg_catalog.jsonb_build_object('command','maintenance.apply_cw_catalog_template','template_key',template.template_key));
  end loop;
  for entry in select e.* from private.catalog_template_entries e where e.template_id=template.id and e.entry_kind='maintenance_subcategory' order by e.position loop
    created_id:=pg_catalog.gen_random_uuid();
    insert into public.maintenance_subcategories(id,tenant_id,category_id,code,name,created_by,updated_by)
    values(created_id,actor.actor_tenant_id,(category_map->>entry.parent_entry_key)::uuid,entry.code,entry.name,actor.actor_user_id,actor.actor_user_id);
    subcategory_ids:=pg_catalog.array_append(subcategory_ids,created_id);
    perform private.append_history(actor.actor_tenant_id,'maintenance_subcategory',created_id,'maintenance.subcategory.created','application_user',
      'maintenance.apply_cw_catalog_template',idem.acquired_command_id,command_correlation_id,'user_command',1,entry.code,1,actor.actor_user_id,null,null,
      pg_catalog.jsonb_build_object('name',entry.name,'status','active','category_id',category_map->>entry.parent_entry_key,'template_key',template.template_key));
    perform private.enqueue_event(actor.actor_tenant_id,'maintenance.subcategory.created','application_user','user_command',idem.acquired_command_id,
      command_correlation_id,'maintenance_subcategory',created_id,1,1,actor.actor_user_id,null,null,
      pg_catalog.jsonb_build_object('id',created_id,'version',1,'status','active','code',entry.code,'category_id',category_map->>entry.parent_entry_key),
      pg_catalog.jsonb_build_object('command','maintenance.apply_cw_catalog_template','template_key',template.template_key));
  end loop;
  insert into private.catalog_template_applications(tenant_id,template_key,template_version,category_ids,subcategory_ids,
    category_count,subcategory_count,command_id,command_correlation_id,applied_by)
  values(actor.actor_tenant_id,template.template_key,template.template_version,category_ids,subcategory_ids,
    pg_catalog.cardinality(category_ids),pg_catalog.cardinality(subcategory_ids),idem.acquired_command_id,command_correlation_id,actor.actor_user_id)
  returning * into application;
  perform private.append_audit(actor.actor_tenant_id,'application_user','cadastros.catalog_template.applied','catalog_template_application',
    command_correlation_id,'user_command',actor.actor_user_id,null,application.id,idem.acquired_command_id,null,1,reason,
    pg_catalog.jsonb_build_object('template_key',template.template_key,'template_version',template.template_version,
      'category_count',application.category_count,'subcategory_count',application.subcategory_count));
  perform private.enqueue_event(actor.actor_tenant_id,'cadastros.catalog_template.applied','application_user','user_command',
    idem.acquired_command_id,command_correlation_id,'catalog_template_application',application.id,1,application.version,
    actor.actor_user_id,null,null,pg_catalog.jsonb_build_object('id',application.id,'version',application.version,'status','applied',
      'template_key',template.template_key,'template_version',template.template_version,'category_count',application.category_count,
      'subcategory_count',application.subcategory_count),pg_catalog.jsonb_build_object('command','maintenance.apply_cw_catalog_template'));
  result:=pg_catalog.jsonb_build_object('id',application.id,'version',application.version,'status',application.status,
    'command_correlation_id',command_correlation_id,'template_key',application.template_key,'template_version',application.template_version,
    'category_ids',application.category_ids,'subcategory_ids',application.subcategory_ids,
    'category_count',application.category_count,'subcategory_count',application.subcategory_count);
  perform private.complete_command_idempotency(idem.acquired_command_id,1,result);
  return result;
end $$;

do $$ declare boundary record; begin
  for boundary in select p.oid from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname=any(array[
      'create_maintenance_category','update_maintenance_category','inactivate_maintenance_category','reactivate_maintenance_category',
      'create_maintenance_subcategory','update_maintenance_subcategory','inactivate_maintenance_subcategory','reactivate_maintenance_subcategory',
      'list_maintenance_categories','get_maintenance_category','lookup_maintenance_categories',
      'list_maintenance_subcategories','get_maintenance_subcategory','lookup_maintenance_subcategories',
      'get_cw_catalog_template_preview','apply_cw_catalog_template'])
  loop execute pg_catalog.format('revoke all on function %s from public,anon,service_role,cw_worker',boundary.oid::pg_catalog.regprocedure); end loop;
end $$;

grant execute on function public.create_maintenance_category(text,text,text,text,uuid,text) to authenticated;
grant execute on function public.update_maintenance_category(uuid,bigint,text,text,text,text,uuid,text) to authenticated;
grant execute on function public.inactivate_maintenance_category(uuid,bigint,text,uuid,text) to authenticated;
grant execute on function public.reactivate_maintenance_category(uuid,bigint,text,uuid,text) to authenticated;
grant execute on function public.create_maintenance_subcategory(uuid,text,text,text,text,uuid,text) to authenticated;
grant execute on function public.update_maintenance_subcategory(uuid,bigint,uuid,text,text,text,text,uuid,text) to authenticated;
grant execute on function public.inactivate_maintenance_subcategory(uuid,bigint,text,uuid,text) to authenticated;
grant execute on function public.reactivate_maintenance_subcategory(uuid,bigint,text,uuid,text) to authenticated;
grant execute on function public.list_maintenance_categories(text,text,integer,integer) to authenticated;
grant execute on function public.get_maintenance_category(uuid) to authenticated;
grant execute on function public.lookup_maintenance_categories(text,integer) to authenticated;
grant execute on function public.list_maintenance_subcategories(uuid,text,text,integer,integer) to authenticated;
grant execute on function public.get_maintenance_subcategory(uuid) to authenticated;
grant execute on function public.lookup_maintenance_subcategories(uuid,text,integer) to authenticated;
grant execute on function public.get_cw_catalog_template_preview(text,bigint) to authenticated;
grant execute on function public.apply_cw_catalog_template(text,bigint,text,uuid,text) to authenticated;

comment on table public.maintenance_categories is 'W4C.2 tenant-owned maintenance categories.';
comment on table public.maintenance_subcategories is 'W4C.2 tenant-owned two-level maintenance subcategories.';
comment on table private.catalog_template_applications is 'W4C.2 immutable ledger of explicit tenant template applications; no runtime authority or synchronization.';
