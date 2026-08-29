-- Códigos anuais, fluxos por tipo e permissões. Script idempotente.
create table if not exists public.sequencias_demandas (ano integer primary key, ultimo_numero integer not null default 0);
alter table public.demandas add column if not exists codigo text;
alter table public.demandas add column if not exists tipo_demanda text not null default 'corretiva';
alter table public.demandas add column if not exists agendamento_em timestamptz;
alter table public.demandas add column if not exists empresa_prestador text;
alter table public.demandas add column if not exists tipo_servico text;
alter table public.demandas add column if not exists observacoes_adicionais text;

alter table public.demandas drop constraint if exists demandas_tipo_demanda_check;
alter table public.demandas drop constraint if exists demandas_prioridade_check;
alter table public.demandas drop constraint if exists demandas_status_check;
drop trigger if exists restringir_campos_por_permissao on public.demandas;

update public.demandas set prioridade='A definir' where prioridade is null or prioridade not in ('A definir','Baixa','Média','Alta','Urgente');
update public.demandas set status=case status when 'A Fazer' then 'Registrado' when 'Em Andamento' then 'Em andamento' when 'Aguardando Terceiros' then 'Em análise' when 'Aguardando Aprovação' then 'Aguardando aprovação' when 'Concluída' then 'Concluído' when 'Cancelada' then 'Cancelado' else status end;
update public.demandas set status='Registrado' where status is null or status not in ('Registrado','Em análise','Programado','Em andamento','Aguardando aprovação','Aprovado','Reprovado','Agendado','Em execução','Concluído','Cancelado');

alter table public.demandas add constraint demandas_tipo_demanda_check check (tipo_demanda in ('corretiva','agendamento','preventiva'));
alter table public.demandas add constraint demandas_prioridade_check check (prioridade in ('A definir','Baixa','Média','Alta','Urgente'));
alter table public.demandas add constraint demandas_status_check check (status in ('Registrado','Em análise','Programado','Em andamento','Aguardando aprovação','Aprovado','Reprovado','Agendado','Em execução','Concluído','Cancelado'));

create or replace function public.gerar_codigo_demanda() returns trigger language plpgsql security definer set search_path=public as $$
declare ano_codigo integer; proximo integer;
begin
  if new.codigo is not null then return new; end if;
  ano_codigo:=extract(year from coalesce(new.criado_em,now()))::integer;
  insert into public.sequencias_demandas(ano,ultimo_numero) values(ano_codigo,1) on conflict(ano) do update set ultimo_numero=public.sequencias_demandas.ultimo_numero+1 returning ultimo_numero into proximo;
  new.codigo:=ano_codigo::text||'-'||lpad(proximo::text,4,'0'); return new;
end; $$;
with numeradas as (select id,extract(year from criado_em)::integer ano,row_number() over(partition by extract(year from criado_em) order by criado_em,id) numero from public.demandas where codigo is null)
update public.demandas d set codigo=n.ano::text||'-'||lpad(n.numero::text,4,'0') from numeradas n where n.id=d.id;
insert into public.sequencias_demandas(ano,ultimo_numero) select extract(year from criado_em)::integer,count(*) from public.demandas group by 1 on conflict(ano) do update set ultimo_numero=greatest(public.sequencias_demandas.ultimo_numero,excluded.ultimo_numero);
create unique index if not exists demandas_codigo_unique on public.demandas(codigo);
drop trigger if exists gerar_codigo_demanda on public.demandas;
create trigger gerar_codigo_demanda before insert on public.demandas for each row execute procedure public.gerar_codigo_demanda();

insert into public.permissoes_perfis(organizacao_id,papel,acao,permitido)
select o.id,r.papel,a.acao,case when r.papel='gestor_manutencao' then true when r.papel='lojista' and a.acao in ('criar_corretiva','criar_agendamento') then true else false end
from public.organizacoes o cross join (values('gestor_manutencao'),('tecnico'),('lojista')) r(papel) cross join (values('criar_corretiva'),('criar_agendamento'),('criar_preventiva'),('aprovar_agendamento')) a(acao)
on conflict(organizacao_id,papel,acao) do nothing;
drop policy if exists "permissao cria demanda" on public.demandas;
create policy "permissao cria demanda" on public.demandas for insert to authenticated with check (criado_por=auth.uid() and public.tem_permissao_usuario(case tipo_demanda when 'corretiva' then 'criar_corretiva' when 'agendamento' then 'criar_agendamento' else 'criar_preventiva' end));
drop policy if exists "administrador cria qualquer demanda" on public.demandas;
create policy "administrador cria qualquer demanda" on public.demandas for insert to authenticated
with check (
  criado_por=auth.uid() and exists (
    select 1 from public.perfis p
    where p.id=auth.uid() and p.ativo and p.papel='administrador'
      and p.organizacao_id=demandas.organizacao_id
  )
);

create or replace function public.preparar_demanda_lojista() returns trigger language plpgsql security definer set search_path=public as $$
declare perfil public.perfis%rowtype;
begin
  select * into perfil from public.perfis where id=auth.uid() and ativo;
  if perfil.papel='lojista' then new.organizacao_id:=perfil.organizacao_id; new.criado_por:=auth.uid(); new.prioridade:='A definir'; new.status:=case when new.tipo_demanda='agendamento' then 'Aguardando aprovação' else 'Registrado' end; end if;
  return new;
end; $$;
drop trigger if exists preparar_demanda_lojista on public.demandas;
create trigger preparar_demanda_lojista before insert on public.demandas for each row execute procedure public.preparar_demanda_lojista();

drop function if exists public.criar_demanda_lojista(text,text,text);
drop function if exists public.criar_demanda_lojista(text,text,text,text,timestamptz,text,text);
create function public.criar_demanda_lojista(p_titulo text,p_local text,p_observacoes text,p_tipo_demanda text,p_agendamento_em timestamptz default null,p_empresa_prestador text default null,p_tipo_servico text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare perfil public.perfis%rowtype; demanda_id bigint; permissao text;
begin
  select * into perfil from public.perfis where id=auth.uid() and ativo and papel='lojista';
  if perfil.id is null then raise exception 'Perfil Lojista ativo não encontrado'; end if;
  if p_tipo_demanda not in ('corretiva','agendamento') then raise exception 'Tipo de demanda não permitido'; end if;
  permissao:=case when p_tipo_demanda='corretiva' then 'criar_corretiva' else 'criar_agendamento' end;
  if not public.tem_permissao_usuario(permissao) then raise exception 'Sem permissão para criar este tipo de demanda'; end if;
  if nullif(trim(p_titulo),'') is null or nullif(trim(p_local),'') is null then raise exception 'Tipo e local são obrigatórios'; end if;
  if p_tipo_demanda='corretiva' and nullif(trim(p_observacoes),'') is null then raise exception 'A descrição do problema é obrigatória'; end if;
  if p_tipo_demanda='agendamento' and (p_agendamento_em is null or nullif(trim(p_empresa_prestador),'') is null) then raise exception 'Prestador e data/hora prevista são obrigatórios'; end if;
  insert into public.demandas(organizacao_id,titulo,categoria,local,prioridade,status,observacoes,criado_por,tipo_demanda,agendamento_em,empresa_prestador,tipo_servico)
  values(perfil.organizacao_id,trim(p_titulo),'Manutenção',trim(p_local),'A definir',case when p_tipo_demanda='agendamento' then 'Aguardando aprovação' else 'Registrado' end,nullif(trim(p_observacoes),''),auth.uid(),p_tipo_demanda,p_agendamento_em,nullif(trim(p_empresa_prestador),''),coalesce(nullif(trim(p_tipo_servico),''),trim(p_titulo))) returning id into demanda_id;
  return jsonb_build_object('id',demanda_id);
end; $$;
revoke all on function public.criar_demanda_lojista(text,text,text,text,timestamptz,text,text) from public;
grant execute on function public.criar_demanda_lojista(text,text,text,text,timestamptz,text,text) to authenticated;

drop function if exists public.criar_demanda_usuario(text,text,text,text,timestamptz,text,text,text,date,text);
create function public.criar_demanda_usuario(p_titulo text,p_local text,p_observacoes text,p_tipo_demanda text,p_agendamento_em timestamptz,p_empresa_prestador text,p_prioridade text,p_responsavel text,p_prazo date,p_observacoes_adicionais text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare perfil public.perfis%rowtype; demanda_id bigint; permissao text; status_inicial text;
begin
  select * into perfil from public.perfis where id=auth.uid() and ativo;
  if perfil.id is null then raise exception 'Perfil ativo não encontrado'; end if;
  if p_tipo_demanda not in ('corretiva','agendamento','preventiva') then raise exception 'Tipo de demanda inválido'; end if;
  permissao:=case p_tipo_demanda when 'corretiva' then 'criar_corretiva' when 'agendamento' then 'criar_agendamento' else 'criar_preventiva' end;
  if perfil.papel<>'administrador' and not public.tem_permissao_usuario(permissao) then raise exception 'Sem permissão para criar este tipo de demanda'; end if;
  if nullif(trim(p_titulo),'') is null or nullif(trim(p_local),'') is null then raise exception 'Tipo e local são obrigatórios'; end if;
  if p_tipo_demanda in ('corretiva','preventiva') and nullif(trim(p_observacoes),'') is null then raise exception 'A descrição é obrigatória'; end if;
  if p_tipo_demanda in ('agendamento','preventiva') and (p_agendamento_em is null or nullif(trim(p_empresa_prestador),'') is null) then raise exception 'Data prevista e prestador/responsável são obrigatórios'; end if;
  status_inicial:=case p_tipo_demanda when 'corretiva' then 'Registrado' when 'agendamento' then 'Aguardando aprovação' else 'Agendado' end;
  insert into public.demandas(organizacao_id,titulo,categoria,local,prioridade,responsavel,status,prazo,observacoes,observacoes_adicionais,criado_por,tipo_demanda,agendamento_em,empresa_prestador,tipo_servico)
  values(perfil.organizacao_id,trim(p_titulo),'Manutenção',trim(p_local),case when p_tipo_demanda='corretiva' and (perfil.papel='administrador' or public.tem_permissao_usuario('classificar_prioridade')) then coalesce(nullif(trim(p_prioridade),''),'A definir') else 'A definir' end,case when p_tipo_demanda='corretiva' and (perfil.papel='administrador' or public.tem_permissao_usuario('alterar_status')) then nullif(trim(p_responsavel),'') else null end,status_inicial,case when p_tipo_demanda='corretiva' and (perfil.papel='administrador' or public.tem_permissao_usuario('alterar_status')) then p_prazo else null end,nullif(trim(p_observacoes),''),nullif(trim(p_observacoes_adicionais),''),auth.uid(),p_tipo_demanda,p_agendamento_em,nullif(trim(p_empresa_prestador),''),trim(p_titulo)) returning id into demanda_id;
  return jsonb_build_object('id',demanda_id);
end; $$;
revoke all on function public.criar_demanda_usuario(text,text,text,text,timestamptz,text,text,text,date,text) from public;
grant execute on function public.criar_demanda_usuario(text,text,text,text,timestamptz,text,text,text,date,text) to authenticated;

create or replace function public.decidir_agendamento(p_demanda_id bigint,p_decisao text) returns void language plpgsql security definer set search_path=public as $$
declare item public.demandas%rowtype;
begin
  if not public.tem_permissao_usuario('aprovar_agendamento') then raise exception 'Sem permissão para decidir agendamentos'; end if;
  if p_decisao not in ('Aprovado','Reprovado') then raise exception 'Decisão inválida'; end if;
  select * into item from public.demandas where id=p_demanda_id;
  if item.id is null or item.tipo_demanda<>'agendamento' then raise exception 'Agendamento não encontrado'; end if;
  if item.status<>'Aguardando aprovação' then raise exception 'Este agendamento já foi decidido'; end if;
  update public.demandas set status=p_decisao where id=p_demanda_id;
end; $$;
revoke all on function public.decidir_agendamento(bigint,text) from public;
grant execute on function public.decidir_agendamento(bigint,text) to authenticated;

-- Reativa a proteção de edição depois da normalização administrativa acima.
drop trigger if exists restringir_campos_por_permissao on public.demandas;
create trigger restringir_campos_por_permissao before update on public.demandas
for each row execute procedure public.restringir_campos_por_permissao();

drop policy if exists "permissao adiciona anexo" on public.anexos_demandas;
create policy "permissao adiciona anexo" on public.anexos_demandas for insert to authenticated with check (criado_por=auth.uid() and public.pode_visualizar_demanda(demanda_id) and (public.tem_permissao_usuario('criar_corretiva') or public.tem_permissao_usuario('criar_agendamento') or public.tem_permissao_usuario('criar_preventiva') or public.tem_permissao_usuario('editar_todas') or public.tem_permissao_usuario('editar_proprias')));
drop policy if exists "permissao envia arquivo" on storage.objects;
create policy "permissao envia arquivo" on storage.objects for insert to authenticated with check (bucket_id='cw-anexos' and public.pode_visualizar_demanda(((storage.foldername(name))[1])::bigint) and (public.tem_permissao_usuario('criar_corretiva') or public.tem_permissao_usuario('criar_agendamento') or public.tem_permissao_usuario('criar_preventiva') or public.tem_permissao_usuario('editar_todas') or public.tem_permissao_usuario('editar_proprias')));
