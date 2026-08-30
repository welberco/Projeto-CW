-- Execute depois do backup e teste em homologação. Não executa exclusões de dados.
-- Códigos internos gestor_manutencao/lojista são preservados; a interface muda os nomes.
begin;

create table if not exists public.cw_migracoes (versao text primary key, aplicado_em timestamptz default now());
revoke all on public.cw_migracoes from public, anon, authenticated;
alter table public.perfis add column if not exists aprovacao text not null default 'aprovado';
alter table public.perfis add column if not exists aprovado_por uuid references auth.users(id);
alter table public.perfis add column if not exists aprovado_em timestamptz;
alter table public.perfis drop constraint if exists perfis_aprovacao_check;
alter table public.perfis add constraint perfis_aprovacao_check check(aprovacao in ('pendente','aprovado','rejeitado'));
alter table public.perfis drop constraint if exists perfis_ativo_aprovado_check;
alter table public.perfis add constraint perfis_ativo_aprovado_check check(not ativo or aprovacao='aprovado');
alter table public.perfis drop constraint if exists perfis_papel_check;
alter table public.perfis add constraint perfis_papel_check check(papel in ('administrador','empreendimento','gestor_manutencao','tecnico','lojista'));
alter table public.perfis alter column papel set default 'lojista';

create or replace function public.cw_org_atual() returns uuid language sql stable security definer set search_path=public as $$
  select organizacao_id from public.perfis where id=auth.uid() and ativo and aprovacao='aprovado';
$$;
create or replace function public.cw_admin() returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.perfis where id=auth.uid() and ativo and aprovacao='aprovado' and papel='administrador');
$$;
create or replace function public.cw_acesso_org(org uuid) returns boolean language sql stable security definer set search_path=public as $$
  select coalesce(public.cw_admin() or (org is not null and org=public.cw_org_atual()),false);
$$;
create or replace function public.cw_matriz(org uuid) returns boolean language sql stable security definer set search_path=public as $$
  select public.cw_admin() or exists(select 1 from public.perfis where id=auth.uid() and ativo and aprovacao='aprovado' and papel='empreendimento' and organizacao_id=org);
$$;
create or replace function public.tem_permissao_usuario(acao_consultada text) returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.perfis p where p.id=auth.uid() and p.ativo and p.aprovacao='aprovado' and (
    p.papel in ('administrador','empreendimento') or
    (acao_consultada<>'gerenciar_permissoes' and exists(select 1 from public.permissoes_perfis r where r.organizacao_id=p.organizacao_id and r.papel=p.papel and r.acao=acao_consultada and r.permitido))
  ));
$$;
create or replace function public.pode_gerenciar(org uuid) returns boolean language sql stable security definer set search_path=public as $$
  select public.cw_acesso_org(org) and public.tem_permissao_usuario('gerenciar_usuarios');
$$;
create or replace function public.pode_visualizar_demanda(demanda bigint) returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.demandas d where d.id=demanda and public.cw_acesso_org(d.organizacao_id) and
    (public.tem_permissao_usuario('visualizar_todas') or (d.criado_por=auth.uid() and public.tem_permissao_usuario('visualizar_proprias'))));
$$;
create or replace function public.cw_editar_demanda(demanda bigint) returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.demandas d where d.id=demanda and public.cw_acesso_org(d.organizacao_id) and
    (public.tem_permissao_usuario('editar_todas') or (d.criado_por=auth.uid() and public.tem_permissao_usuario('editar_proprias'))));
$$;

create or replace function public.cw_inicializar_matriz() returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.permissoes_perfis(organizacao_id,papel,acao,permitido)
  select new.id,r.papel,a.acao,case when r.papel='gestor_manutencao' then a.acao<>'gerenciar_permissoes'
    when r.papel='tecnico' then a.acao in ('visualizar_todas','visualizar_historico')
    else a.acao in ('visualizar_proprias','criar_corretiva','criar_agendamento','editar_proprias','excluir_midia','visualizar_historico') end
  from (values('gestor_manutencao'),('tecnico'),('lojista')) r(papel)
  cross join (values('visualizar_todas'),('visualizar_proprias'),('criar_corretiva'),('criar_agendamento'),('criar_preventiva'),('aprovar_agendamento'),('editar_todas'),('editar_proprias'),('classificar_prioridade'),('alterar_status'),('excluir_midia'),('apagar_demanda'),('visualizar_historico'),('emitir_relatorios'),('gerenciar_usuarios'),('gerenciar_empreendimento'),('gerenciar_permissoes')) a(acao)
  on conflict do nothing;
  return new;
end; $$;
drop trigger if exists cw_inicializar_matriz on public.organizacoes;
create trigger cw_inicializar_matriz after insert on public.organizacoes for each row execute function public.cw_inicializar_matriz();
-- Inicialização única, sem sobrescrever matrizes já personalizadas em reexecuções.
do $$ begin
  if not exists(select 1 from public.cw_migracoes where versao='multiempresa-v1') then
    insert into public.permissoes_perfis(organizacao_id,papel,acao,permitido)
    select o.id,r.papel,a.acao,case when r.papel='gestor_manutencao' then a.acao<>'gerenciar_permissoes'
      when r.papel='tecnico' then a.acao in ('visualizar_todas','visualizar_historico')
      else a.acao in ('visualizar_proprias','criar_corretiva','criar_agendamento','editar_proprias','excluir_midia','visualizar_historico') end
    from public.organizacoes o cross join (values('gestor_manutencao'),('tecnico'),('lojista')) r(papel)
    cross join (values('visualizar_todas'),('visualizar_proprias'),('criar_corretiva'),('criar_agendamento'),('criar_preventiva'),('aprovar_agendamento'),('editar_todas'),('editar_proprias'),('classificar_prioridade'),('alterar_status'),('excluir_midia'),('apagar_demanda'),('visualizar_historico'),('emitir_relatorios'),('gerenciar_usuarios'),('gerenciar_empreendimento'),('gerenciar_permissoes')) a(acao)
    on conflict(organizacao_id,papel,acao) do update set permitido=excluded.permitido;
  end if;
end $$;
update public.permissoes_perfis set permitido=false where acao='gerenciar_permissoes';
alter table public.permissoes_perfis drop constraint if exists cw_matriz_reservada;
alter table public.permissoes_perfis add constraint cw_matriz_reservada check(acao<>'gerenciar_permissoes' or not permitido);

create or replace function public.lista_empreendimentos_cadastro() returns table(id uuid,nome text) language sql stable security definer set search_path=public as $$
  select id,nome from public.organizacoes order by nome;
$$;
create or replace function public.criar_perfil_usuario() returns trigger language plpgsql security definer set search_path=public as $$
declare org uuid;
begin
  begin org:=(new.raw_user_meta_data->>'organizacao_id')::uuid; exception when invalid_text_representation then raise exception 'Selecione um empreendimento válido'; end;
  if org is null or not exists(select 1 from public.organizacoes where id=org) then raise exception 'Selecione um empreendimento válido'; end if;
  -- Nunca confiar em papel, ativo ou aprovação enviados em user_metadata.
  insert into public.perfis(id,organizacao_id,nome,email,papel,ativo,aprovacao)
  values(new.id,org,coalesce(nullif(trim(new.raw_user_meta_data->>'nome'),''),split_part(new.email,'@',1)),new.email,'lojista',false,'pendente');
  return new;
end; $$;
drop trigger if exists ao_criar_usuario on auth.users;
create trigger ao_criar_usuario after insert on auth.users for each row execute function public.criar_perfil_usuario();

-- Remove políticas antigas somente das tabelas próprias desta aplicação.
do $$ declare p record; begin
  for p in select schemaname,tablename,policyname from pg_policies where schemaname='public' and tablename in
    ('organizacoes','perfis','permissoes_perfis','demandas','historico_demandas','anexos_demandas')
  loop execute format('drop policy %I on %I.%I',p.policyname,p.schemaname,p.tablename); end loop;
end $$;
create policy cw_org_select on public.organizacoes for select to authenticated using(public.cw_acesso_org(id));
create policy cw_org_insert on public.organizacoes for insert to authenticated with check(public.cw_admin());
create policy cw_org_update on public.organizacoes for update to authenticated using(public.cw_acesso_org(id) and public.tem_permissao_usuario('gerenciar_empreendimento')) with check(public.cw_acesso_org(id) and public.tem_permissao_usuario('gerenciar_empreendimento'));
create policy cw_profile_select on public.perfis for select to authenticated using(id=auth.uid() or public.pode_gerenciar(organizacao_id));
-- Perfil privilegiado é atualizado exclusivamente pela função administrativa verificada.
revoke insert,update,delete on public.perfis from anon,authenticated;
create policy cw_matrix_select on public.permissoes_perfis for select to authenticated using(public.cw_acesso_org(organizacao_id));
create policy cw_matrix_write on public.permissoes_perfis for all to authenticated using(public.cw_matriz(organizacao_id)) with check(public.cw_matriz(organizacao_id));
create policy cw_demand_select on public.demandas for select to authenticated using(public.pode_visualizar_demanda(id));
create policy cw_demand_insert on public.demandas for insert to authenticated with check(criado_por=auth.uid() and public.cw_acesso_org(organizacao_id) and public.tem_permissao_usuario('criar_'||tipo_demanda));
create policy cw_demand_update on public.demandas for update to authenticated using(public.cw_editar_demanda(id)) with check(public.cw_editar_demanda(id));
create policy cw_demand_delete on public.demandas for delete to authenticated using(public.cw_acesso_org(organizacao_id) and public.tem_permissao_usuario('apagar_demanda'));
create policy cw_history_select on public.historico_demandas for select to authenticated using(public.pode_visualizar_demanda(demanda_id) and public.tem_permissao_usuario('visualizar_historico'));
create policy cw_attachment_select on public.anexos_demandas for select to authenticated using(public.pode_visualizar_demanda(demanda_id));
create policy cw_attachment_insert on public.anexos_demandas for insert to authenticated with check(criado_por=auth.uid() and public.cw_editar_demanda(demanda_id) and split_part(storage_path,'/',1)=demanda_id::text);
create policy cw_attachment_delete on public.anexos_demandas for delete to authenticated using(public.cw_editar_demanda(demanda_id) and public.tem_permissao_usuario('excluir_midia'));

-- Guardas também cobrem RPCs antigas SECURITY DEFINER que ignoram RLS.
create or replace function public.cw_guardar_demanda() returns trigger language plpgsql security definer set search_path=public as $$
declare org uuid; registro bigint; especial boolean:=false;
begin
  if auth.uid() is null then if tg_op='DELETE' then return old; else return new; end if; end if;
  if tg_op='INSERT' then
    if not public.cw_acesso_org(new.organizacao_id) or not public.tem_permissao_usuario('criar_'||new.tipo_demanda) then raise exception 'Sem permissão neste empreendimento'; end if;
    new.criado_por:=auth.uid(); new.criado_em:=now();
    new.status:=case new.tipo_demanda when 'corretiva' then 'Registrado' when 'agendamento' then 'Aguardando aprovação' else 'Agendado' end;
    if not public.tem_permissao_usuario('classificar_prioridade') then new.prioridade:='A definir'; end if;
    if not public.tem_permissao_usuario('alterar_status') then new.responsavel:=null; new.prazo:=null; new.proxima_acao:=null; end if;
    return new;
  end if;
  if not public.cw_acesso_org(old.organizacao_id) then raise exception 'Sem acesso ao empreendimento'; end if;
  if tg_op='DELETE' then
    if not public.tem_permissao_usuario('apagar_demanda') then raise exception 'Sem permissão para excluir'; end if;
    return old;
  end if;
  -- Reagendamento/cancelamento não libera edição dos outros campos da solicitação aprovada.
  especial:=old.tipo_demanda='agendamento' and old.status='Aprovado' and old.criado_por=auth.uid()
    and public.tem_permissao_usuario('editar_proprias') and (
      (new.status='Aguardando aprovação' and new.agendamento_em>now() and new.agendamento_em is distinct from old.agendamento_em)
      or (new.status='Cancelado' and nullif(trim(new.observacoes_adicionais),'') is not null));
  if especial then
    if (to_jsonb(new)-array['agendamento_em','status','observacoes_adicionais','atualizado_em']) is distinct from
       (to_jsonb(old)-array['agendamento_em','status','observacoes_adicionais','atualizado_em']) then raise exception 'Use somente reagendar ou cancelar'; end if;
    return new;
  end if;
  if not public.cw_editar_demanda(old.id) and not (
    public.tem_permissao_usuario('aprovar_agendamento') and old.tipo_demanda='agendamento' and old.status='Aguardando aprovação'
    and new.status in ('Aprovado','Reprovado') and (to_jsonb(new)-array['status','atualizado_em'])=(to_jsonb(old)-array['status','atualizado_em'])
  ) then raise exception 'Sem permissão para editar'; end if;
  if old.tipo_demanda='agendamento' and old.status='Aprovado' and exists(select 1 from public.perfis where id=auth.uid() and papel='lojista') then raise exception 'Use reagendar ou cancelar'; end if;
  new.organizacao_id:=old.organizacao_id; new.criado_por:=old.criado_por; new.criado_em:=old.criado_em; new.codigo:=old.codigo; new.tipo_demanda:=old.tipo_demanda;
  if not public.tem_permissao_usuario('classificar_prioridade') then new.prioridade:=old.prioridade; end if;
  if old.tipo_demanda='agendamento' and new.status is distinct from old.status and not public.tem_permissao_usuario('aprovar_agendamento') then raise exception 'Sem permissão para decidir agendamento'; end if;
  if not public.tem_permissao_usuario('alterar_status') then
    new.responsavel:=old.responsavel; new.prazo:=old.prazo; new.proxima_acao:=old.proxima_acao;
    if old.tipo_demanda<>'agendamento' then new.status:=old.status; end if;
  end if;
  return new;
end; $$;
drop trigger if exists preparar_demanda_lojista on public.demandas;
drop trigger if exists restringir_edicao_lojista on public.demandas;
drop trigger if exists restringir_campos_por_permissao on public.demandas;
drop trigger if exists cw_guardar_demanda on public.demandas;
create trigger cw_guardar_demanda before insert or update or delete on public.demandas for each row execute function public.cw_guardar_demanda();

create or replace function public.cw_storage_permitido(bucket text,caminho text,acao text) returns boolean language plpgsql stable security definer set search_path=public as $$
declare demanda bigint; org uuid;
begin
  if bucket='cw-anexos' then
    begin demanda:=split_part(caminho,'/',1)::bigint; exception when others then return false; end;
    if acao='select' then return public.pode_visualizar_demanda(demanda); end if;
    return public.cw_editar_demanda(demanda) and (acao<>'delete' or public.tem_permissao_usuario('excluir_midia'));
  elsif bucket='cw-logos' then
    begin org:=split_part(caminho,'/',1)::uuid; exception when others then return false; end;
    if acao='select' then return public.cw_acesso_org(org); end if;
    return public.cw_acesso_org(org) and public.tem_permissao_usuario('gerenciar_empreendimento');
  end if;
  return false;
end; $$;
-- Só substitui políticas referentes aos dois buckets do CW.
do $$ declare p record; begin
  for p in select policyname from pg_policies where schemaname='storage' and tablename='objects'
    and (coalesce(qual,'')||coalesce(with_check,'')) ~ 'cw-anexos|cw-logos|cw_storage_permitido'
  loop execute format('drop policy %I on storage.objects',p.policyname); end loop;
end $$;
create policy cw_storage_read on storage.objects for select to authenticated using(public.cw_storage_permitido(bucket_id,name,'select'));
create policy cw_storage_insert on storage.objects for insert to authenticated with check(public.cw_storage_permitido(bucket_id,name,'insert'));
create policy cw_storage_update on storage.objects for update to authenticated using(public.cw_storage_permitido(bucket_id,name,'update')) with check(public.cw_storage_permitido(bucket_id,name,'update'));
create policy cw_storage_delete on storage.objects for delete to authenticated using(public.cw_storage_permitido(bucket_id,name,'delete'));
-- Política restritiva impede que uma política antiga genérica reabra os buckets CW.
drop policy if exists cw_storage_guard on storage.objects;
drop policy if exists cw_storage_guard_select on storage.objects;
drop policy if exists cw_storage_guard_insert on storage.objects;
drop policy if exists cw_storage_guard_update on storage.objects;
drop policy if exists cw_storage_guard_delete on storage.objects;
create policy cw_storage_guard_select on storage.objects as restrictive for select to authenticated
using(bucket_id not in ('cw-anexos','cw-logos') or public.cw_storage_permitido(bucket_id,name,'select'));
create policy cw_storage_guard_insert on storage.objects as restrictive for insert to authenticated
with check(bucket_id not in ('cw-anexos','cw-logos') or public.cw_storage_permitido(bucket_id,name,'insert'));
create policy cw_storage_guard_update on storage.objects as restrictive for update to authenticated
using(bucket_id not in ('cw-anexos','cw-logos') or public.cw_storage_permitido(bucket_id,name,'update'))
with check(bucket_id not in ('cw-anexos','cw-logos') or public.cw_storage_permitido(bucket_id,name,'update'));
create policy cw_storage_guard_delete on storage.objects as restrictive for delete to authenticated
using(bucket_id not in ('cw-anexos','cw-logos') or public.cw_storage_permitido(bucket_id,name,'delete'));
update storage.buckets set public=false where id in ('cw-anexos','cw-logos');

-- Sem credenciais de serviço no navegador. Validação usada pela Edge Function.
create or replace function public.cw_pode_gerenciar_usuario(p_org uuid,p_usuario uuid,p_papel text) returns boolean language sql stable security definer set search_path=public as $$
  select public.pode_gerenciar(p_org) and p_papel in ('administrador','empreendimento','gestor_manutencao','tecnico','lojista') and (
    public.cw_admin() or (p_papel in ('gestor_manutencao','tecnico','lojista') and
      (p_usuario is null or exists(select 1 from public.perfis where id=p_usuario and organizacao_id=p_org and papel not in ('administrador','empreendimento'))))
  );
$$;
create or replace function public.cw_salvar_usuario(p_usuario uuid,p_nome text,p_email text,p_loja text,p_papel text,p_ativo boolean,p_aprovacao text) returns void language plpgsql security definer set search_path=public as $$
declare alvo public.perfis%rowtype;
begin
  select * into alvo from public.perfis where id=p_usuario for update;
  if alvo.id is null or not public.cw_pode_gerenciar_usuario(alvo.organizacao_id,p_usuario,p_papel) then raise exception 'Sem permissão para alterar este usuário'; end if;
  if p_usuario=auth.uid() and (p_papel<>alvo.papel or not p_ativo or p_aprovacao<>'aprovado') then raise exception 'Não altere seu próprio perfil ou acesso'; end if;
  if p_aprovacao not in ('pendente','aprovado','rejeitado') or p_ativo is null or nullif(trim(p_nome),'') is null then raise exception 'Dados inválidos'; end if;
  update public.perfis set nome=trim(p_nome),email=trim(p_email),loja=nullif(trim(p_loja),''),papel=p_papel,
    aprovacao=p_aprovacao,ativo=(p_ativo and p_aprovacao='aprovado'),
    aprovado_por=case when p_aprovacao='aprovado' and alvo.aprovacao<>'aprovado' then auth.uid() else aprovado_por end,
    aprovado_em=case when p_aprovacao='aprovado' and alvo.aprovacao<>'aprovado' then now() else aprovado_em end where id=p_usuario;
end; $$;

create or replace function public.criar_demanda_empresa(p_organizacao_id uuid,p_titulo text,p_local text,p_observacoes text,p_tipo_demanda text,p_agendamento_em timestamptz,p_empresa_prestador text,p_prioridade text,p_responsavel text,p_prazo date,p_observacoes_adicionais text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare perfil public.perfis%rowtype; demanda_id bigint; permissao text; status_inicial text;
begin
  select * into perfil from public.perfis where id=auth.uid() and ativo and aprovacao='aprovado';
  if not public.cw_acesso_org(p_organizacao_id) then raise exception 'Sem acesso ao empreendimento'; end if;
  if perfil.id is null then raise exception 'Perfil ativo não encontrado'; end if;
  if p_tipo_demanda not in ('corretiva','agendamento','preventiva') then raise exception 'Tipo de demanda inválido'; end if;
  permissao:=case p_tipo_demanda when 'corretiva' then 'criar_corretiva' when 'agendamento' then 'criar_agendamento' else 'criar_preventiva' end;
  if perfil.papel<>'administrador' and not public.tem_permissao_usuario(permissao) then raise exception 'Sem permissão para criar este tipo de demanda'; end if;
  if nullif(trim(p_titulo),'') is null or nullif(trim(p_local),'') is null then raise exception 'Tipo e local são obrigatórios'; end if;
  if p_tipo_demanda in ('corretiva','preventiva') and nullif(trim(p_observacoes),'') is null then raise exception 'A descrição é obrigatória'; end if;
  if p_tipo_demanda in ('agendamento','preventiva') and (p_agendamento_em is null or nullif(trim(p_empresa_prestador),'') is null) then raise exception 'Data prevista e prestador/responsável são obrigatórios'; end if;
  status_inicial:=case p_tipo_demanda when 'corretiva' then 'Registrado' when 'agendamento' then 'Aguardando aprovação' else 'Agendado' end;
  insert into public.demandas(organizacao_id,titulo,categoria,local,prioridade,responsavel,status,prazo,observacoes,observacoes_adicionais,criado_por,tipo_demanda,agendamento_em,empresa_prestador,tipo_servico)
  values(p_organizacao_id,trim(p_titulo),'Manutenção',trim(p_local),case when p_tipo_demanda='corretiva' and (perfil.papel='administrador' or public.tem_permissao_usuario('classificar_prioridade')) then coalesce(nullif(trim(p_prioridade),''),'A definir') else 'A definir' end,case when p_tipo_demanda='corretiva' and (perfil.papel='administrador' or public.tem_permissao_usuario('alterar_status')) then nullif(trim(p_responsavel),'') else null end,status_inicial,case when p_tipo_demanda='corretiva' and (perfil.papel='administrador' or public.tem_permissao_usuario('alterar_status')) then p_prazo else null end,nullif(trim(p_observacoes),''),nullif(trim(p_observacoes_adicionais),''),auth.uid(),p_tipo_demanda,p_agendamento_em,nullif(trim(p_empresa_prestador),''),trim(p_titulo)) returning id into demanda_id;
  return jsonb_build_object('id',demanda_id);
end; $$;
revoke all on function public.criar_demanda_empresa(uuid,text,text,text,text,timestamptz,text,text,text,date,text) from public;
grant execute on function public.criar_demanda_empresa(uuid,text,text,text,text,timestamptz,text,text,text,date,text) to authenticated;


create or replace function public.dados_relatorio_empresa(p_organizacao_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare perfil public.perfis%rowtype; resultado jsonb;
begin
  select * into perfil from public.perfis where id=auth.uid() and ativo and aprovacao='aprovado';
  if not public.cw_acesso_org(p_organizacao_id) then raise exception 'Sem acesso ao empreendimento'; end if;
  if perfil.id is null then raise exception 'Perfil ativo não encontrado'; end if;
  if perfil.papel<>'administrador' and not public.tem_permissao_usuario('emitir_relatorios') then raise exception 'Sem permissão para emitir relatórios'; end if;
  select jsonb_build_object(
    'organizacao',to_jsonb(o),
    'solicitante',jsonb_build_object('nome',perfil.nome,'email',perfil.email),
    'demandas',coalesce((select jsonb_agg(jsonb_build_object(
      'id',d.id,'codigo',d.codigo,'tipo_demanda',d.tipo_demanda,'tipo',d.titulo,'local',d.local,
      'status',d.status,'prioridade',d.prioridade,'responsavel',d.responsavel,'prestador',d.empresa_prestador,
      'data_cadastro',d.criado_em,'data_prevista',d.agendamento_em,'prazo',d.prazo,
      'descricao',d.observacoes,'usuario_id',d.criado_por,'usuario_nome',coalesce(p.nome,p.email,'Usuário'),'loja',p.loja
    ) order by d.criado_em desc) from public.demandas d left join public.perfis p on p.id=d.criado_por where d.organizacao_id=p_organizacao_id and public.pode_visualizar_demanda(d.id)),'[]'::jsonb)
  ) into resultado from public.organizacoes o where o.id=p_organizacao_id;
  return resultado;
end; $$;
revoke all on function public.dados_relatorio_empresa(uuid) from public;
grant execute on function public.dados_relatorio_empresa(uuid) to authenticated;
-- Clientes antigos também respeitam a visibilidade das demandas no relatório.
create or replace function public.dados_relatorio() returns jsonb language sql security definer set search_path=public as $$
  select public.dados_relatorio_empresa(public.cw_org_atual());
$$;
-- Funções novas não ficam executáveis por anônimos por padrão.
do $$ declare f record; begin
  for f in select oid::regprocedure assinatura from pg_proc where pronamespace='public'::regnamespace and (proname like 'cw_%' or proname='lista_empreendimentos_cadastro')
  loop execute format('revoke all on function %s from public, anon',f.assinatura); execute format('grant execute on function %s to authenticated',f.assinatura); end loop;
end $$;
grant execute on function public.lista_empreendimentos_cadastro() to anon;
grant insert,select,update on public.organizacoes to authenticated;
insert into public.cw_migracoes(versao) values('multiempresa-v1') on conflict do nothing;
commit;
