-- Códigos anuais, tipos de demanda e permissões específicas
create table if not exists public.sequencias_demandas (
  ano integer primary key,
  ultimo_numero integer not null default 0
);

alter table public.demandas add column if not exists codigo text;
alter table public.demandas add column if not exists tipo_demanda text not null default 'corretiva';
alter table public.demandas add column if not exists agendamento_em timestamptz;
alter table public.demandas add column if not exists empresa_prestador text;
alter table public.demandas add column if not exists tipo_servico text;
alter table public.demandas drop constraint if exists demandas_tipo_demanda_check;
alter table public.demandas add constraint demandas_tipo_demanda_check
check (tipo_demanda in ('corretiva','agendamento','preventiva'));

create or replace function public.gerar_codigo_demanda()
returns trigger language plpgsql security definer set search_path=public as $$
declare ano_codigo integer; proximo integer;
begin
  if new.codigo is not null then return new; end if;
  ano_codigo:=extract(year from coalesce(new.criado_em,now()))::integer;
  insert into public.sequencias_demandas(ano,ultimo_numero) values(ano_codigo,1)
  on conflict(ano) do update set ultimo_numero=public.sequencias_demandas.ultimo_numero+1
  returning ultimo_numero into proximo;
  new.codigo:=ano_codigo::text||'-'||lpad(proximo::text,4,'0');
  return new;
end; $$;

-- Numera registros antigos pela ordem de criação.
with numeradas as (
  select id,extract(year from criado_em)::integer ano,
         row_number() over(partition by extract(year from criado_em) order by criado_em,id) numero
  from public.demandas where codigo is null
)
update public.demandas d set codigo=n.ano::text||'-'||lpad(n.numero::text,4,'0')
from numeradas n where n.id=d.id;

insert into public.sequencias_demandas(ano,ultimo_numero)
select extract(year from criado_em)::integer,count(*) from public.demandas group by 1
on conflict(ano) do update set ultimo_numero=greatest(public.sequencias_demandas.ultimo_numero,excluded.ultimo_numero);

create unique index if not exists demandas_codigo_unique on public.demandas(codigo);
drop trigger if exists gerar_codigo_demanda on public.demandas;
create trigger gerar_codigo_demanda before insert on public.demandas for each row execute procedure public.gerar_codigo_demanda();

insert into public.permissoes_perfis(organizacao_id,papel,acao,permitido)
select o.id,r.papel,a.acao,
case when r.papel='gestor_manutencao' then true
     when r.papel='lojista' and a.acao in ('criar_corretiva','criar_agendamento') then true
     else false end
from public.organizacoes o
cross join (values('gestor_manutencao'),('tecnico'),('lojista')) r(papel)
cross join (values('criar_corretiva'),('criar_agendamento'),('criar_preventiva')) a(acao)
on conflict(organizacao_id,papel,acao) do nothing;

drop policy if exists "permissao cria demanda" on public.demandas;
create policy "permissao cria demanda" on public.demandas for insert to authenticated
with check (
  criado_por=auth.uid() and public.tem_permissao_usuario(
    case tipo_demanda when 'corretiva' then 'criar_corretiva'
      when 'agendamento' then 'criar_agendamento' else 'criar_preventiva' end
  )
);

drop function if exists public.criar_demanda_lojista(text,text,text);
create or replace function public.criar_demanda_lojista(
  p_titulo text,p_local text,p_observacoes text,p_tipo_demanda text,
  p_agendamento_em timestamptz default null,p_empresa_prestador text default null,p_tipo_servico text default null
)
returns jsonb language plpgsql security definer set search_path=public as $$
declare perfil public.perfis%rowtype; demanda_id bigint; permissao text;
begin
  select * into perfil from public.perfis where id=auth.uid() and ativo and papel='lojista';
  if perfil.id is null then raise exception 'Perfil Lojista ativo não encontrado'; end if;
  if p_tipo_demanda not in ('corretiva','agendamento') then raise exception 'Tipo de demanda não permitido'; end if;
  permissao:=case when p_tipo_demanda='corretiva' then 'criar_corretiva' else 'criar_agendamento' end;
  if not public.tem_permissao_usuario(permissao) then raise exception 'Sem permissão para criar este tipo de demanda'; end if;
  if nullif(trim(p_titulo),'') is null or nullif(trim(p_local),'') is null or nullif(trim(p_observacoes),'') is null then raise exception 'Título, local e descrição são obrigatórios'; end if;
  if p_tipo_demanda='agendamento' and (p_agendamento_em is null or nullif(trim(p_empresa_prestador),'') is null or nullif(trim(p_tipo_servico),'') is null) then raise exception 'Data, empresa e tipo de serviço são obrigatórios'; end if;
  insert into public.demandas(organizacao_id,titulo,categoria,local,prioridade,status,observacoes,criado_por,tipo_demanda,agendamento_em,empresa_prestador,tipo_servico)
  values(perfil.organizacao_id,trim(p_titulo),'Manutenção',trim(p_local),'Não classificada','A Fazer',trim(p_observacoes),auth.uid(),p_tipo_demanda,p_agendamento_em,nullif(trim(p_empresa_prestador),''),nullif(trim(p_tipo_servico),''))
  returning id into demanda_id;
  return jsonb_build_object('id',demanda_id);
end; $$;
revoke all on function public.criar_demanda_lojista(text,text,text,text,timestamptz,text,text) from public;
grant execute on function public.criar_demanda_lojista(text,text,text,text,timestamptz,text,text) to authenticated;

drop policy if exists "permissao adiciona anexo" on public.anexos_demandas;
create policy "permissao adiciona anexo" on public.anexos_demandas for insert to authenticated
with check (
  criado_por=auth.uid() and public.pode_visualizar_demanda(demanda_id)
  and (
    public.tem_permissao_usuario('criar_corretiva') or public.tem_permissao_usuario('criar_agendamento')
    or public.tem_permissao_usuario('criar_preventiva') or public.tem_permissao_usuario('editar_todas')
    or public.tem_permissao_usuario('editar_proprias')
  )
);

drop policy if exists "permissao envia arquivo" on storage.objects;
create policy "permissao envia arquivo" on storage.objects for insert to authenticated
with check (
  bucket_id='cw-anexos' and public.pode_visualizar_demanda(((storage.foldername(name))[1])::bigint)
  and (
    public.tem_permissao_usuario('criar_corretiva') or public.tem_permissao_usuario('criar_agendamento')
    or public.tem_permissao_usuario('criar_preventiva') or public.tem_permissao_usuario('editar_todas')
    or public.tem_permissao_usuario('editar_proprias')
  )
);
