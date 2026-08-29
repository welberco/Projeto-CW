-- CW Manutenção - perfis, gestão de usuários e permissões por função

alter table public.perfis add column if not exists loja text;
alter table public.perfis add column if not exists ativo boolean not null default true;

alter table public.perfis drop constraint if exists perfis_papel_check;
update public.perfis set papel = case
  when papel = 'gestor' then 'gestor_manutencao'
  when papel = 'manutencao' then 'tecnico'
  when papel = 'solicitante' then 'lojista'
  else papel end;
alter table public.perfis alter column papel set default 'lojista';
alter table public.perfis add constraint perfis_papel_check
check (papel in ('administrador','gestor_manutencao','tecnico','lojista'));

alter table public.demandas drop constraint if exists demandas_prioridade_check;
alter table public.demandas add constraint demandas_prioridade_check
check (prioridade in ('Não classificada','Baixa','Média','Alta','Urgente'));

create or replace function public.pode_gerenciar(org uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.perfis p where p.id=auth.uid() and p.organizacao_id=org and p.ativo and p.papel in ('administrador','gestor_manutencao'));
$$;

create or replace function public.pode_visualizar_demanda(demanda bigint)
returns boolean language sql stable security definer set search_path = public as $$
  select exists(
    select 1 from public.demandas d join public.perfis p on p.id=auth.uid()
    where d.id=demanda and p.ativo and p.organizacao_id=d.organizacao_id
      and (p.papel in ('administrador','gestor_manutencao','tecnico') or d.criado_por=auth.uid())
  );
$$;

drop policy if exists "usuario visualiza o proprio perfil" on public.perfis;
drop policy if exists "usuario atualiza o proprio perfil" on public.perfis;
create policy "usuario visualiza perfil permitido" on public.perfis for select to authenticated
using (id=auth.uid() or public.pode_gerenciar(organizacao_id));
create policy "gestao atualiza perfis" on public.perfis for update to authenticated
using (public.pode_gerenciar(organizacao_id)) with check (public.pode_gerenciar(organizacao_id));
grant select, update on public.perfis to authenticated;

drop policy if exists "usuario visualiza demandas da organizacao" on public.demandas;
drop policy if exists "usuario cria demanda na organizacao" on public.demandas;
drop policy if exists "usuario atualiza demandas da organizacao" on public.demandas;
drop policy if exists "criador ou administrador atualiza demanda" on public.demandas;
create policy "perfis visualizam demandas permitidas" on public.demandas for select to authenticated
using (public.pode_visualizar_demanda(id));
create policy "perfis autorizados criam demandas" on public.demandas for insert to authenticated
with check (
  criado_por=auth.uid() and organizacao_id=(select organizacao_id from public.perfis where id=auth.uid() and ativo)
  and (
    public.pode_gerenciar(organizacao_id)
    or exists(select 1 from public.perfis p where p.id=auth.uid() and p.papel='lojista' and prioridade='Não classificada' and categoria='Manutenção' and status='A Fazer' and responsavel is null and prazo is null and proxima_acao is null)
  )
);
create policy "gestao ou criador atualiza demanda" on public.demandas for update to authenticated
using (public.pode_gerenciar(organizacao_id) or (criado_por=auth.uid() and exists(select 1 from public.perfis p where p.id=auth.uid() and p.ativo and p.papel='lojista')))
with check (public.pode_gerenciar(organizacao_id) or (criado_por=auth.uid() and exists(select 1 from public.perfis p where p.id=auth.uid() and p.ativo and p.papel='lojista')));

create or replace function public.restringir_edicao_lojista()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if exists(select 1 from public.perfis p where p.id=auth.uid() and p.papel='lojista') then
    new.organizacao_id:=old.organizacao_id; new.categoria:=old.categoria; new.prioridade:=old.prioridade;
    new.responsavel:=old.responsavel; new.status:=old.status; new.prazo:=old.prazo;
    new.proxima_acao:=old.proxima_acao; new.criado_por:=old.criado_por; new.criado_em:=old.criado_em;
  end if;
  return new;
end; $$;
drop trigger if exists restringir_edicao_lojista on public.demandas;
create trigger restringir_edicao_lojista before update on public.demandas for each row execute procedure public.restringir_edicao_lojista();

drop policy if exists "usuario visualiza historico da organizacao" on public.historico_demandas;
create policy "usuario visualiza historico permitido" on public.historico_demandas for select to authenticated using (public.pode_visualizar_demanda(demanda_id));

drop policy if exists "usuario visualiza anexos da organizacao" on public.anexos_demandas;
drop policy if exists "usuario adiciona anexos na organizacao" on public.anexos_demandas;
drop policy if exists "usuario exclui os proprios anexos" on public.anexos_demandas;
drop policy if exists "criador ou administrador exclui anexo" on public.anexos_demandas;
create policy "usuario visualiza anexos permitidos" on public.anexos_demandas for select to authenticated using (public.pode_visualizar_demanda(demanda_id));
create policy "usuario adiciona anexos permitidos" on public.anexos_demandas for insert to authenticated
with check (criado_por=auth.uid() and public.pode_visualizar_demanda(demanda_id) and exists(select 1 from public.perfis p where p.id=auth.uid() and p.ativo and p.papel<>'tecnico'));
create policy "criador ou gestao exclui anexo" on public.anexos_demandas for delete to authenticated
using (criado_por=auth.uid() or exists(select 1 from public.demandas d where d.id=demanda_id and public.pode_gerenciar(d.organizacao_id)));

drop policy if exists "usuario visualiza arquivos da organizacao" on storage.objects;
drop policy if exists "usuario envia arquivos para a organizacao" on storage.objects;
drop policy if exists "usuario exclui os proprios arquivos" on storage.objects;
drop policy if exists "criador ou administrador exclui arquivo" on storage.objects;
create policy "usuario visualiza arquivos permitidos" on storage.objects for select to authenticated
using (bucket_id='cw-anexos' and public.pode_visualizar_demanda(((storage.foldername(name))[1])::bigint));
create policy "usuario envia arquivos permitidos" on storage.objects for insert to authenticated
with check (bucket_id='cw-anexos' and public.pode_visualizar_demanda(((storage.foldername(name))[1])::bigint) and exists(select 1 from public.perfis p where p.id=auth.uid() and p.ativo and p.papel<>'tecnico'));
create policy "criador ou gestao exclui arquivo" on storage.objects for delete to authenticated
using (bucket_id='cw-anexos' and (owner_id=auth.uid()::text or exists(select 1 from public.demandas d where d.id=((storage.foldername(name))[1])::bigint and public.pode_gerenciar(d.organizacao_id))));
